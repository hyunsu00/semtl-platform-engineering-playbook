# MetalLB Installation

## 개요

이 문서는 이 저장소의 `RKE2` 표준 클러스터에 `MetalLB`를 설치해
`LoadBalancer` 타입 서비스를 외부에 노출하는 절차를 정리합니다.

이 문서 기준은 다음과 같습니다.

- 대상 클러스터는 [`RKE2 설치 문서`](../rke2/installation.md) 기준으로
  이미 구축되어 있습니다.
- CNI는 RKE2 기본값인 `canal`을 사용합니다.
- Ingress Controller는 RKE2 기본 포함 `ingress-nginx`를 사용합니다.
- MetalLB는 L2 모드로 구성합니다.
- 외부에 할당할 IP 풀은 `192.168.0.200-192.168.0.220`을 사용합니다.

이 문서의 목표는 설치 직후 바로 `ingress-nginx` 외부 IP를 확보해
이후 `Argo CD`, `Grafana`, `Prometheus`, `Rancher` 같은 서비스를
같은 진입점 구조로 노출할 수 있게 만드는 것입니다.

## 사전 조건

- Kubernetes 클러스터가 정상이며 `kubectl` 접근이 가능합니다.
- 모든 노드가 `Ready` 상태여야 합니다.
- `rke2-ingress-nginx`, `canal`, `coredns`, `metrics-server`가 정상이어야 합니다.
- `192.168.0.200-192.168.0.220` 대역이 다른 DHCP, 정적 IP, 장비에서
  사용되지 않도록 예약되어 있어야 합니다.

사전 확인:

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl -n kube-system get pods | grep -E 'canal|coredns|metrics-server'
kubectl -n kube-system get svc
```

정상 기준:

- 노드 4대가 모두 `Ready`
- 핵심 시스템 파드가 `Running`
- `ingress-nginx-controller` 서비스가 존재

## 배치 원칙

- 네임스페이스: `metallb-system`
- 동작 모드: `Layer2`
- 외부 IP 풀: `192.168.0.200-192.168.0.220`
- 운영 초기에는 단일 풀만 사용합니다.
- 우선 `ingress-nginx-controller` 서비스에 외부 IP를 할당합니다.

운영 메모:

- 이 구조에서는 서비스별로 IP를 따로 늘리기보다
  `ingress-nginx` 한 개의 외부 IP를 공용 진입점으로 쓰는 편이 단순합니다.
- 외부 서비스 구분은 IP가 아니라 호스트명으로 처리합니다.
- 예: `argocd.example.com`, `grafana.example.com`, `prometheus.example.com`

## 설치 절차

### 1. MetalLB 설치

이 문서에서는 공식 native manifest를 사용합니다.

```bash
kubectl apply -f \
  https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml
```

확인:

```bash
kubectl get ns metallb-system
kubectl -n metallb-system get pods
```

정상 기준:

- `metallb-system` 네임스페이스가 생성됨
- `controller` Deployment가 `Running`
- `speaker` DaemonSet 파드가 각 노드에서 `Running`

### 2. IPAddressPool 생성

`192.168.0.200-192.168.0.220` 대역을 MetalLB 관리 IP 풀로 등록합니다.

```bash
cat <<'EOF' > ~/metallb-pool.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.0.200-192.168.0.220
EOF

kubectl apply -f ~/metallb-pool.yaml
```

확인:

```bash
kubectl -n metallb-system get ipaddresspool
kubectl -n metallb-system describe ipaddresspool first-pool
```

### 3. L2Advertisement 생성

L2 모드 광고를 활성화합니다.

```bash
cat <<'EOF' > ~/metallb-l2advertisement.yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  ipAddressPools:
    - first-pool
EOF

kubectl apply -f ~/metallb-l2advertisement.yaml
```

확인:

```bash
kubectl -n metallb-system get l2advertisement
kubectl -n metallb-system describe l2advertisement first-pool
```

### 4. `ingress-nginx` 외부 노출

RKE2 기본 `ingress-nginx` 컨트롤러 서비스를 `LoadBalancer`로 전환합니다.

먼저 현재 서비스를 확인합니다.

```bash
kubectl -n kube-system get svc | grep ingress
```

환경에 따라 서비스 이름은 아래 둘 중 하나일 수 있습니다.

- `rke2-ingress-nginx-controller`
- `ingress-nginx-controller`

예시:

```bash
kubectl -n kube-system patch svc rke2-ingress-nginx-controller \
  -p '{"spec":{"type":"LoadBalancer"}}'
```

확인:

```bash
kubectl -n kube-system get svc rke2-ingress-nginx-controller -o wide
```

정상 기준:

- `TYPE`이 `LoadBalancer`
- `EXTERNAL-IP`가 `192.168.0.200-220` 범위 중 하나로 할당됨

예시:

```text
NAME                            TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)
rke2-ingress-nginx-controller   LoadBalancer   10.43.144.219   192.168.0.200   80:xxxxx/TCP,443:xxxxx/TCP
```

### 5. 외부 접근 확인

먼저 네트워크 레벨에서 IP가 응답하는지 확인합니다.

```bash
ping -c 2 192.168.0.200
```

그다음 서비스 레벨을 확인합니다.

```bash
curl -I http://192.168.0.200
```

운영 기준:

- DNS 또는 내부 DNS에 각 서비스 호스트명을 같은 외부 IP로 연결합니다.

예:

- `argocd.example.internal` -> `192.168.0.200`
- `grafana.example.internal` -> `192.168.0.200`
- `prometheus.example.internal` -> `192.168.0.200`

## 검증 방법

### MetalLB 리소스 확인

```bash
kubectl -n metallb-system get all
kubectl -n metallb-system get ipaddresspool,l2advertisement
```

정상 기준:

- `controller`가 `Running`
- `speaker`가 각 노드에서 `Running`
- `IPAddressPool`, `L2Advertisement`가 존재

### LoadBalancer IP 할당 확인

```bash
kubectl get svc -A | grep LoadBalancer
```

정상 기준:

- `ingress-nginx-controller`에 `EXTERNAL-IP`가 할당됨

### ARP 기반 외부 접근 확인

관리자 단말 또는 같은 네트워크의 다른 장비에서 확인합니다.

```bash
ping -c 2 192.168.0.200
curl -I http://192.168.0.200
```

## 트러블슈팅

### `EXTERNAL-IP`가 `<pending>` 상태로 남음

확인:

```bash
kubectl -n metallb-system get ipaddresspool,l2advertisement
kubectl -n metallb-system get pods
kubectl -n kube-system get svc rke2-ingress-nginx-controller -o yaml
```

조치:

- `IPAddressPool`과 `L2Advertisement`가 모두 생성되었는지 확인합니다.
- 외부 IP 풀이 다른 장비에서 이미 사용 중이지 않은지 확인합니다.
- `speaker` 파드가 각 노드에서 정상인지 확인합니다.

### 외부 IP는 할당됐지만 접속이 안 됨

확인:

```bash
kubectl get svc -A | grep LoadBalancer
kubectl -n metallb-system get pods -o wide
arp -an | grep 192.168.0.200
```

조치:

- 같은 L2 네트워크에 있는지 확인합니다.
- 상위 스위치나 네트워크 장비가 ARP 응답을 막지 않는지 확인합니다.
- 클라이언트에서 ARP 캐시를 갱신한 뒤 다시 확인합니다.

### 잘못된 서비스 이름으로 패치함

증상:

- `NotFound` 오류 발생

확인:

```bash
kubectl -n kube-system get svc
```

조치:

- 실제 서비스 이름이 `rke2-ingress-nginx-controller`인지
  `ingress-nginx-controller`인지 확인한 뒤 다시 패치합니다.

## 참고

- [RKE2 Installation](../rke2/installation.md)
