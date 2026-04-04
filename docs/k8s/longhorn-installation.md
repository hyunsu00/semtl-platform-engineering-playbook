# K8s Longhorn Installation

## 개요

이 문서는 이 저장소의 Kubernetes 환경에 `Longhorn`을 설치하는 절차를 정리합니다.

이 문서의 목적은 다음과 같습니다.

- 운영 핵심 스택용 기본 스토리지를 준비
- `Prometheus`, `Grafana`, `Rancher` 설치 전에 공통 스토리지 계층 확보
- `longhorn` StorageClass를 사용할 수 있는 상태까지 검증

## 사전 조건

- Kubernetes 클러스터가 정상이며 `kubectl` 접근이 가능합니다.
- 각 노드에 기본 디스크 여유 공간이 충분해야 합니다.
- `open-iscsi`와 관련 커널 모듈이 각 노드에 준비되어 있어야 합니다.

노드 공통 확인:

```bash
kubectl get nodes
lsblk
df -h
```

운영 메모:

- Longhorn은 노드 로컬 디스크를 사용하므로 디스크 여유 공간이 중요합니다.
- 운영 핵심 스택에 사용할 예정이면 replica 수와 디스크 용량을 먼저 설계합니다.

노드 준비 원칙:

- `cp1`, `cp2`, `cp3`, `w1`, `w2` 모두 Longhorn 설치 전제 조건은 준비합니다.
- 다만 실제 저장소 사용은 `worker` 노드 우선으로 설계하는 것을 권장합니다.
- `control-plane` 노드는 Kubernetes 핵심 컴포넌트가 함께 동작하므로,
  Longhorn 데이터 저장 비중을 크게 두지 않는 편이 안전합니다.

현재 환경 기준 권장안:

- `cp1`~`cp3`: VM 디스크 `60GB`
- `w1`~`w2`: VM 디스크 `400GB`
- 실제 물리 스토리지: `1TB`

판단 기준:

- `60GB`인 `control-plane` 노드는 OS, 컨테이너 런타임, 로그, Kubernetes 시스템
  리소스를 감당하는 용도로는 가능하지만, Longhorn 주 저장소 역할까지 맡기기에는
  여유가 작습니다.
- `400GB`인 `worker` 노드는 Longhorn replica와 운영 핵심 스택을 올리기에
  더 현실적인 시작점입니다.
- `Prometheus`, `Grafana`, 이후 `Rancher`까지 Longhorn에 둘 계획이면
  현재처럼 `worker 400GB`로 시작하는 구성이 더 안정적입니다.
- 초기 테스트만 빠르게 시작할 때는 `worker 300GB`도 가능하지만,
  여러 앱을 장기 운영할 계획이면 `400GB`가 더 편합니다.

권장 방향:

- 현재 구성인 `cp 60GB`, `worker 400GB`를 Longhorn 기본 기준으로 사용합니다.
- Longhorn 주 저장소는 `worker`에 두는 방향으로 운영합니다.
- `control-plane`은 Longhorn 전제 조건과 기본 동작은 준비하되,
  데이터 저장 비중은 낮게 유지합니다.

## 설치 절차

### 1. 공통 패키지 상태 확인

`open-iscsi`와 `iscsid` 활성화는
[`./installation.md`](./installation.md)에서 모든 노드 공통 준비 항목으로 먼저 수행합니다.

이 문서에서는 설치 대신 상태만 확인합니다.

대상 노드:

- `cp1`, `cp2`, `cp3`
- `w1`, `w2`

```bash
dpkg -l | grep open-iscsi
systemctl is-active iscsid
```

정상 기준:

- `open-iscsi` 패키지가 설치되어 있음
- `is-active` 결과가 `active`

### 2. Longhorn 네임스페이스 생성

```bash
kubectl create namespace longhorn-system
```

이미 존재하면 확인만 수행합니다.

```bash
kubectl get ns longhorn-system
```

### 3. Longhorn 설치

가장 단순한 성공 경로는 공식 manifest를 적용하는 방식입니다.

```bash
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/master/deploy/longhorn.yaml
```

설치 직후 확인:

```bash
kubectl -n longhorn-system get pods
kubectl get storageclass
```

정상 기준:

- `longhorn-manager`, `longhorn-driver-deployer`, `longhorn-ui`,
  `longhorn-csi-plugin` 관련 파드가 생성됨
- `longhorn` StorageClass가 생성됨

### 4. Longhorn 파드 기동 대기

```bash
kubectl -n longhorn-system get pods -o wide
```

정상 기준:

- 주요 파드가 모두 `Running`
- 반복 재시작이 없음

### 5. 기본 StorageClass 여부 확인

권장 기본값은 `longhorn`입니다.

```bash
kubectl get storageclass
```

확인 포인트:

- `longhorn`
- 필요 시 `(default)` 표시 확인

기본 StorageClass로 지정하려면:

```bash
kubectl patch storageclass longhorn \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

참고:

- 이미 `nfs-client`가 기본값이라면 운영 정책에 맞게 하나만 기본으로 유지합니다.
- 일반 앱은 `nfs-client`, 운영 핵심 스택은 `longhorn`을 명시적으로 지정하는 것도 가능합니다.

### 6. 테스트 PVC 생성

Longhorn이 실제로 동작하는지 간단히 확인합니다.

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: longhorn-test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 2Gi
EOF
```

확인:

```bash
kubectl get pvc longhorn-test-pvc
kubectl get pv | grep longhorn-test-pvc
```

정상 기준:

- PVC가 `Bound`

테스트 종료:

```bash
kubectl delete pvc longhorn-test-pvc
```

## 설치 검증

아래를 모두 만족하면 기본 설치 완료로 판단합니다.

```bash
kubectl -n longhorn-system get pods
kubectl get storageclass
```

정상 기준:

- `longhorn-system` 주요 파드 `Running`
- `longhorn` StorageClass 존재

## 운영 메모

- Longhorn은 운영 핵심 스택용 기본 스토리지로 사용합니다.
- `Prometheus`, `Grafana`, `Rancher`는 `storageClassName: longhorn`을 우선 사용합니다.
- 홈랩 환경에서는 replica 수와 노드 디스크 사용량을 과하게 잡지 않도록 주의합니다.
- 현재 표준 디스크 크기는 `control-plane 60GB`, `worker 400GB`입니다.

## 초기 트러블슈팅

### 증상: Longhorn 파드가 `CrashLoopBackOff` 또는 `Init`에서 멈춤

확인 명령:

```bash
kubectl -n longhorn-system get pods
kubectl -n longhorn-system describe pod <pod-name>
```

주요 원인:

- `open-iscsi` 미설치
- `iscsid` 비활성
- 노드 디스크 여유 공간 부족

조치:

- 각 노드에서 `open-iscsi` 설치 상태를 다시 확인합니다.
- `systemctl is-active iscsid` 결과를 점검합니다.
- 노드 디스크 용량을 확인합니다.

## 참고

- 스토리지 역할 구분: [`./storage-guide.md`](./storage-guide.md)
- Kubernetes 기본 설치: [`./installation.md`](./installation.md)
- 공식 사이트: `https://longhorn.io/`
