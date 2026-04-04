# K8s NFS StorageClass Installation

## 개요

이 문서는 Synology NFS를 Kubernetes의 `StorageClass`로 연결하는 절차를 정리합니다.

이 저장소 기준 NFS는 다음 용도로 사용합니다.

- 일반 앱 데이터
- 공유성 높은 파일 데이터
- NAS 의존을 감수할 수 있는 워크로드

## 사전 조건

- Synology NAS에서 NFS 서비스가 활성화되어 있어야 합니다.
- 공유폴더 `nfs`와 하위 폴더 `k8s`가 준비되어 있어야 합니다.
- 예시 NFS export는 `/volume2/nfs`
- Kubernetes 노드는 `192.168.0.0/24` 대역 기준으로 NFS 접근이 가능해야 합니다.
- 각 노드에는 `nfs-common`이 설치되어 있어야 합니다.

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
- Kubernetes 하위 폴더: `/volume2/nfs/k8s`

운영 메모:

- `nfs` 공유폴더 아래에 `k8s` 폴더를 미리 만들어 둡니다.
- 실제 PVC 데이터는 그 아래에 하위 폴더로 자동 생성됩니다.

### 2. Helm 저장소 등록

```bash
helm repo add nfs-subdir-external-provisioner \
  https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo update
```

### 3. 네임스페이스 생성

```bash
kubectl create namespace nfs-provisioner
```

이미 존재하면 확인만 수행합니다.

```bash
kubectl get ns nfs-provisioner
```

### 4. NFS provisioner 설치

```bash
helm upgrade --install nfs-subdir-external-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace nfs-provisioner \
  --set nfs.server=192.168.0.2 \
  --set nfs.path=/volume2/nfs/k8s \
  --set storageClass.name=nfs-client \
  --set storageClass.defaultClass=false \
  --set storageClass.reclaimPolicy=Retain
```

기본값 설명:

- `storageClass.name=nfs-client`: 앱에서 명시적으로 사용
- `defaultClass=false`: 기본 StorageClass는 `longhorn`을 우선 권장
- `reclaimPolicy=Retain`: PVC 삭제 시 실제 데이터는 바로 제거하지 않음

### 5. 설치 확인

```bash
kubectl -n nfs-provisioner get pods
kubectl get storageclass
```

정상 기준:

- `nfs-subdir-external-provisioner` 파드가 `Running`
- `nfs-client` StorageClass 생성

### 6. 테스트 PVC 생성

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

테스트 종료:

```bash
kubectl delete pvc nfs-test-pvc
```

주의:

- `nfs-client`는 `reclaimPolicy=Retain` 기준으로 설정합니다.
- 따라서 `kubectl delete pvc nfs-test-pvc`를 실행해도
  Synology NFS 경로 아래의 실제 하위 폴더는 남을 수 있습니다.
- 테스트 폴더까지 완전히 정리하려면 Synology의
  `/volume2/nfs/k8s` 아래 해당 하위 폴더를 수동으로 삭제합니다.

## 운영 메모

- `nfs-client`는 일반 앱 데이터용으로 유지합니다.
- `Prometheus`, `Grafana`, `Rancher` 같은 운영 핵심 스택은 `longhorn`을 우선 사용합니다.
- NFS는 NAS 장애 시 영향을 받으므로 핵심 모니터링 스택 기본값으로는 권장하지 않습니다.

## 초기 트러블슈팅

### 증상: PVC가 `Pending`

확인 명령:

```bash
kubectl get storageclass
kubectl -n nfs-provisioner get pods
kubectl describe pvc <pvc-name> -n <namespace>
```

주요 원인:

- NFS provisioner 미설치
- `nfs-client` StorageClass 미생성
- Synology NFS 권한 또는 export 경로 문제

조치:

- `showmount -e 192.168.0.2` 결과를 다시 확인합니다.
- `nfs-subdir-external-provisioner` 파드 상태를 확인합니다.
- NFS path와 NAS 권한을 다시 검토합니다.

## 참고

- 스토리지 역할 구분: [`./storage-guide.md`](./storage-guide.md)
- Kubernetes 기본 설치: [`./installation.md`](./installation.md)
- Prometheus 설치: [`../prometheus/installation.md`](../prometheus/installation.md)
