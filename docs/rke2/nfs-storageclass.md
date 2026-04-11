# NFS StorageClass Installation

## 개요

이 문서는 이 저장소의 `RKE2` 표준 클러스터에서 Synology NFS를
Kubernetes `StorageClass`로 연결하는 절차를 정리합니다.

이 저장소 기준 NFS는 다음 용도로 사용합니다.

- 일반 앱 데이터
- 공유성 높은 파일 데이터
- NAS 의존을 감수할 수 있는 워크로드

이 문서 기준은 다음과 같습니다.

- 대상 클러스터는 [`./installation.md`](./installation.md) 기준으로 이미 구축되어 있습니다.
- 모든 노드에 `nfs-common`이 설치되어 있습니다.
- 기본 `StorageClass`는 `longhorn`을 우선 사용하고, NFS는 `nfs-client`로 명시적으로 사용합니다.

## 사전 조건

- Synology NAS에서 NFS 서비스가 활성화되어 있어야 합니다.
- 공유폴더 `nfs`와 하위 폴더 `rke2`가 준비되어 있어야 합니다.
- 예시 NFS export는 `/volume2/nfs`입니다.
- Kubernetes 노드는 `192.168.0.0/24` 대역 기준으로 NFS 접근이 가능해야 합니다.
- `vm-rke2-cp1`, `vm-rke2-w1`, `vm-rke2-w2`, `vm-rke2-w3` 모두 NFS 접근이 가능해야 합니다.

노드 확인:

```bash
showmount -e 192.168.0.2
```

예상 결과:

- `/volume2/nfs 192.168.0.0/24`

## 설치 절차

### 1. Synology 쪽 준비

예시 기준:

- NAS IP: `192.168.0.2`
- 공유폴더: `nfs`
- RKE2 하위 폴더: `/volume2/nfs/rke2`

운영 메모:

- `nfs` 공유폴더 아래에 `rke2` 폴더를 미리 만들어 둡니다.
- 실제 PVC 데이터는 그 아래에 하위 폴더로 자동 생성됩니다.

### 2. RKE2 노드 NFS 접근 확인

`nfs-common`은 [`./installation.md`](./installation.md)의
기본 패키지 설치 단계에서 이미 준비되어 있어야 합니다.

이 문서에서는 설치 대신 상태만 확인합니다.

```bash
dpkg -l | grep nfs-common
showmount -e 192.168.0.2
```

정상 기준:

- `nfs-common` 패키지가 설치되어 있음
- `/volume2/nfs` export가 조회됨

### 3. Helm 저장소 등록

```bash
helm repo add nfs-subdir-external-provisioner \
  https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo update
```

### 4. 네임스페이스 생성

```bash
kubectl create namespace nfs-provisioner
```

이미 존재하면 확인만 수행합니다.

```bash
kubectl get ns nfs-provisioner
```

### 5. NFS provisioner 설치

```bash
helm upgrade --install nfs-subdir-external-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace nfs-provisioner \
  --set nfs.server=192.168.0.2 \
  --set nfs.path=/volume2/nfs/rke2 \
  --set storageClass.name=nfs-client \
  --set storageClass.defaultClass=false \
  --set storageClass.reclaimPolicy=Retain
```

기본값 설명:

- `storageClass.name=nfs-client`: 앱에서 명시적으로 사용
- `defaultClass=false`: 기본 StorageClass는 `longhorn`을 우선 권장
- `reclaimPolicy=Retain`: PVC 삭제 시 실제 데이터는 바로 제거하지 않음

### 6. 설치 확인

```bash
kubectl -n nfs-provisioner get pods
kubectl get storageclass
```

정상 기준:

- `nfs-subdir-external-provisioner` 파드가 `Running`
- `nfs-client` StorageClass 생성

### 7. 테스트 PVC 생성

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: nfs-client
  resources:
    requests:
      storage: 2Gi
EOF
```

확인:

```bash
kubectl get pvc nfs-test-pvc
kubectl get pv | grep nfs-test-pvc
```

정상 기준:

- PVC가 `Bound`

참고:

- 첫 PVC 생성 직후에는 잠시 `Pending`으로 보일 수 있습니다.
- `kubectl get pvc nfs-test-pvc -w`로 `Bound` 전환까지 확인한 뒤 판단하는 편이 안전합니다.

테스트 종료:

```bash
kubectl delete pvc nfs-test-pvc
```

주의:

- `nfs-client`는 `reclaimPolicy=Retain` 기준으로 설정합니다.
- 따라서 `kubectl delete pvc nfs-test-pvc`를 실행해도
  Synology NFS 경로 아래의 실제 하위 폴더는 남을 수 있습니다.
- 테스트 폴더까지 완전히 정리하려면 Synology의
  `/volume2/nfs/rke2` 아래 해당 하위 폴더를 수동으로 삭제합니다.

## 운영 메모

- `nfs-client`는 일반 앱 데이터용으로 유지합니다.
- `Prometheus`, `Grafana`, `Rancher` 같은 운영 핵심 스택은 `longhorn`을 우선 사용합니다.
- NFS는 NAS 장애 시 영향을 받으므로 핵심 모니터링 스택 기본값으로는 권장하지 않습니다.

## 스토리지 구성 완료 후 스냅샷 생성

`rke2-install-clean-v1` 이후 `Longhorn`, `NFS StorageClass`까지 구성하고
기본 검증이 끝났으면 Proxmox에서 각 `RKE2` VM의 두 번째 기준점을 남깁니다.

이 스냅샷도 반드시 불필요 파일(찌꺼기) 정리 후 생성합니다.

### 불필요 파일 정리 `[모든 노드]`

각 노드에서 아래 정리 작업을 먼저 수행합니다.

```bash
# /tmp 전체 삭제
sudo rm -rf /tmp/*

# /var/tmp 전체 삭제
sudo rm -rf /var/tmp/*

# 미사용 패키지 정리
sudo apt autoremove -y

# APT 캐시 정리
sudo apt clean

# journal 로그 전체 정리
sudo journalctl --vacuum-time=1s

# 현재 사용자 bash 히스토리 비우기
cat /dev/null > ~/.bash_history && history -c
```

### Proxmox 스냅샷 생성

권장 시점:

- `vm-rke2-cp1`, `vm-rke2-w1`, `vm-rke2-w2`, `vm-rke2-w3`가 모두 `Ready`
- `kubectl get pods -A` 기준으로 핵심 파드가 모두 `Running`
- `kubectl -n longhorn-system get pods -o wide` 기준 Longhorn 주요 파드가 모두 `Running`
- `kubectl -n nfs-provisioner get pods -o wide` 기준 NFS provisioner 파드가 `Running`
- `kubectl get storageclass` 기준 `longhorn (default)`와 `nfs-client`가 모두 존재
- 테스트용 PVC를 삭제했다면 `kubectl get pvc -A` 결과가 정리된 상태
- `Longhorn`, `NFS StorageClass` 설치 후 기본 검증이 모두 끝난 상태

확인 예시:

```bash
kubectl get nodes
kubectl get pods -A
kubectl -n longhorn-system get pods -o wide
kubectl -n nfs-provisioner get pods -o wide
kubectl get storageclass
kubectl get pvc -A
```

Proxmox Web UI 절차:

1. 대상 VM 선택
1. `스냅샷`
1. `스냅샷 생성`
1. 이름과 설명 입력 후 생성

권장 대상:

- `vm-rke2-cp1`
- `vm-rke2-w1`
- `vm-rke2-w2`
- `vm-rke2-w3`

권장 예시:

- `Name`: `rke2-storage-clean-v2`
- 설명은 노드 역할이 드러나도록 VM별로 다르게 기록합니다.

VM별 권장 설명:

- `vm-rke2-cp1`:
  `[스토리지]`
  `- rke2 : v1.34.6+rke2r1`
  `- role : control-plane`
  `- hostname : vm-rke2-cp1`
  `- node ip : 192.168.0.181`
  `- longhorn : installed`
  `- nfs storageclass : installed`
  `- status : kubectl get nodes 기준 Ready`
- `vm-rke2-w1`:
  `[스토리지]`
  `- rke2 : v1.34.6+rke2r1`
  `- role : worker-1`
  `- hostname : vm-rke2-w1`
  `- node ip : 192.168.0.191`
  `- longhorn replica target : enabled`
  `- nfs client : ready`
  `- status : kubectl get nodes 기준 Ready`
- `vm-rke2-w2`:
  `[스토리지]`
  `- rke2 : v1.34.6+rke2r1`
  `- role : worker-2`
  `- hostname : vm-rke2-w2`
  `- node ip : 192.168.0.192`
  `- longhorn replica target : enabled`
  `- nfs client : ready`
  `- status : kubectl get nodes 기준 Ready`
- `vm-rke2-w3`:
  `[스토리지]`
  `- rke2 : v1.34.6+rke2r1`
  `- role : worker-3`
  `- hostname : vm-rke2-w3`
  `- node ip : 192.168.0.193`
  `- longhorn replica target : enabled`
  `- nfs client : ready`
  `- status : kubectl get nodes 기준 Ready`

운영 메모:

- 이 스냅샷은 `rke2-install-clean-v1` 이후 `Longhorn`, `NFS StorageClass`까지 완료된 기준점으로 사용합니다.
- 스냅샷 이름은 4대 VM 모두 동일하게 `rke2-storage-clean-v2`로 맞추는 것을 권장합니다.
- 이후 `Prometheus`, `Grafana`, `Rancher` 같은 상위 서비스 설치 전 기준점으로 두기 좋습니다.
- 실제 운영 데이터가 본격적으로 쌓이기 시작하면 스냅샷보다는 백업 정책을 우선합니다.

## 참고

- Kubernetes 기본 설치: [`./installation.md`](./installation.md)
- Longhorn 설치: [`./longhorn-installation.md`](./longhorn-installation.md)
- Monitoring 설치: [`../monitoring/installation.md`](../monitoring/installation.md)
