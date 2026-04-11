# Monitoring Installation

## 개요

이 문서는 이 저장소의 `RKE2` 표준 클러스터에
`Prometheus`, `Grafana`, `Alertmanager`를 모니터링 스택으로 함께 설치하는 절차를 정리합니다.

이 문서의 기준은 다음과 같습니다.

- 대상 클러스터는 [`../rke2/installation.md`](../rke2/installation.md) 기준으로 이미 구축되어 있습니다.
- 스토리지는
  [`../rke2/longhorn-installation.md`](../rke2/longhorn-installation.md)
  기준의 `longhorn`을 사용합니다.
- Ingress Controller는 RKE2 기본 포함 `ingress-nginx`를 사용합니다.
- 외부 TLS 종료는 현재 `Synology Reverse Proxy`에서 처리합니다.
- 설치 방식은 `kube-prometheus-stack` Helm chart를 사용합니다.
- 홈랩 기준으로 핵심 컴포넌트 replica는 모두 `1`로 유지합니다.

이 문서의 목표는 모니터링 스택을 한 번에 단순하게 올리고,
브라우저에서 `Prometheus`, `Grafana`, `Alertmanager`에 바로 접근할 수 있게 만드는 것입니다.

## 홈랩 최적 구성 원칙

이 문서 기준 권장 구성:

- `prometheus`: `1`
- `grafana`: `1`
- `alertmanager`: `1`
- `prometheusOperator`: `1`
- `kube-state-metrics`: `1`
- `node-exporter`: DaemonSet 기본값 유지

이 구성을 쓰는 이유:

- 설치와 복구 흐름이 단순합니다.
- 홈랩에서도 기본 메트릭 수집, 대시보드, 알림 기능을 한 번에 확보할 수 있습니다.
- `Prometheus`와 `Grafana`를 별도 문서로 나누지 않아도 운영 기준을 이해하기 쉽습니다.

## 사전 조건

- Kubernetes 클러스터가 정상이며 `kubectl` 접근이 가능합니다.
- `helm` CLI가 설치되어 있습니다.
- `longhorn` StorageClass를 사용할 수 있어야 합니다.
- RKE2 기본 `ingress-nginx`가 정상 기동 중이어야 합니다.
- 외부 TLS 종료를 사용할 경우 `ingress-nginx`에
  `use-forwarded-headers: "true"`가 적용되어 있어야 합니다.
- 운영 도메인 예시:
  - `prometheus.semtl.synology.me`
  - `grafana.semtl.synology.me`
  - `alertmanager.semtl.synology.me`
- DNS는 위 도메인들이 ingress 진입 주소를 가리키도록 준비되어 있어야 합니다.

사전 확인 명령:

```bash
kubectl get nodes
kubectl -n kube-system get pods | grep ingress-nginx
kubectl -n kube-system get svc | grep ingress-nginx
kubectl get storageclass
helm version
```

정상 기준:

- 모든 노드가 `Ready`
- `rke2-ingress-nginx` 관련 파드가 `Running`
- ingress 진입에 사용할 서비스 또는 노드 주소가 확인됨
- `longhorn` StorageClass가 존재
- `helm version`이 정상 응답

## 배치 원칙

- 설치 네임스페이스: `monitoring`
- 배포 방식: `kube-prometheus-stack`
- 외부 노출: `Ingress`
- 내부 서비스 타입: `ClusterIP`
- 외부 HTTPS는 `Synology Reverse Proxy`가 종료합니다.
- 현재 구조에서는 `Rancher`, `Argo CD`, 모니터링 스택이 같은 ingress 진입 주소를 공유할 수 있습니다.
- 서비스별 구분은 host 기준으로 처리합니다.
- `MetalLB`가 없으면 별도 `LoadBalancer` IP 대신
  `ingress-nginx`가 떠 있는 `Ready` 노드 IP를 진입점으로 사용합니다.

## 설치 절차

### 1. 네임스페이스 생성

```bash
kubectl create namespace monitoring
```

이미 존재하면 아래와 같이 확인만 수행합니다.

```bash
kubectl get ns monitoring
```

### 2. Helm 저장소 등록

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

확인:

```bash
helm search repo prometheus-community/kube-prometheus-stack
```

### 3. Values 파일 작성

운영 기준 값을 `~/rke2/monitoring/values-monitoring.yaml`로 관리합니다.

```bash
mkdir -p ~/rke2/monitoring

cat <<'EOF' > ~/rke2/monitoring/values-monitoring.yaml
crds:
  enabled: true

prometheusOperator:
  replicas: 1

grafana:
  replicas: 1
  adminUser: admin
  adminPassword: "<GRAFANA_ADMIN_PASSWORD>"
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
    hosts:
      - grafana.semtl.synology.me
  persistence:
    enabled: true
    type: pvc
    storageClassName: longhorn
    accessModes:
      - ReadWriteOnce
    size: 10Gi
  grafana.ini:
    server:
      domain: grafana.semtl.synology.me
      root_url: https://grafana.semtl.synology.me

alertmanager:
  alertmanagerSpec:
    replicas: 1
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          storageClassName: longhorn
          resources:
            requests:
              storage: 10Gi
  ingress:
    enabled: true
    ingressClassName: nginx
    paths:
      - /
    hosts:
      - alertmanager.semtl.synology.me

prometheus:
  ingress:
    enabled: true
    ingressClassName: nginx
    paths:
      - /
    hosts:
      - prometheus.semtl.synology.me
  prometheusSpec:
    replicas: 1
    retention: 15d
    retentionSize: 45GB
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          storageClassName: longhorn
          resources:
            requests:
              storage: 50Gi

defaultRules:
  create: true

kube-state-metrics:
  replicas: 1
EOF
```

기본 구성 설명:

- 핵심 컴포넌트 replica는 모두 `1` 기준으로 유지합니다.
- `Grafana`, `Alertmanager`, `Prometheus`는 각각 Ingress로 노출합니다.
- 저장소는 `longhorn` PVC를 사용합니다.
- HTTPS 종단은 Kubernetes가 아니라 Synology Reverse Proxy에서 처리합니다.
- `Grafana` 초기 관리자 비밀번호는 values에 명시해 최초 로그인 절차를 단순화합니다.

### 4. Monitoring stack 설치

```bash
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f ~/rke2/monitoring/values-monitoring.yaml
```

설치 직후 확인:

```bash
helm list -n monitoring
kubectl -n monitoring get pods
kubectl -n monitoring get svc
kubectl -n monitoring get ingress
kubectl -n monitoring get pvc
```

정상 기준:

- `helm list -n monitoring`에 `monitoring` 릴리스가 조회됨
- `prometheus-*`, `grafana-*`, `alertmanager-*`,
  `kube-state-metrics`, `prometheus-operator` 관련 리소스가 생성됨
- Ingress가 생성됨
- PVC가 `Bound`

### 5. 기동 대기

```bash
kubectl -n monitoring rollout status \
  deploy/monitoring-kube-prometheus-operator --timeout=5m
kubectl -n monitoring rollout status deploy/monitoring-grafana --timeout=5m
kubectl -n monitoring rollout status deploy/monitoring-kube-state-metrics --timeout=5m
kubectl -n monitoring rollout status \
  statefulset/prometheus-monitoring-kube-prometheus-prometheus \
  --timeout=10m
kubectl -n monitoring rollout status \
  statefulset/alertmanager-monitoring-kube-prometheus-alertmanager \
  --timeout=10m
```

정상 기준:

- 주요 파드가 모두 `Running`
- `Pending` 파드가 남지 않음

### 6. 브라우저 접속 검증

현재 환경처럼 `MetalLB`가 없고 `LoadBalancer` 서비스도 없다면,
`rke2-ingress-nginx-controller`가 떠 있는 `Ready` 노드 IP 중 하나를
ingress 진입 주소로 사용합니다.

예:

- `vm-rke2-cp1` -> `192.168.0.181`
- `vm-rke2-w1` -> `192.168.0.191`
- `vm-rke2-w2` -> `192.168.0.192`
- `vm-rke2-w3` -> `192.168.0.193`

예를 들어 Synology Reverse Proxy 대상을 `vm-rke2-cp1`로 정했다면 DNS는 아래처럼 맞춥니다.

- `prometheus.semtl.synology.me` -> `192.168.0.181`
- `grafana.semtl.synology.me` -> `192.168.0.181`
- `alertmanager.semtl.synology.me` -> `192.168.0.181`

Synology Reverse Proxy 예시:

- `https://prometheus.semtl.synology.me` -> `http://192.168.0.181:80`
- `https://grafana.semtl.synology.me` -> `http://192.168.0.181:80`
- `https://alertmanager.semtl.synology.me` -> `http://192.168.0.181:80`

검증 항목:

```bash
curl -k -s -o /dev/null -w "%{http_code}\n" https://prometheus.semtl.synology.me/
curl -k -I https://grafana.semtl.synology.me/login
curl -k -s -o /dev/null -w "%{http_code}\n" https://alertmanager.semtl.synology.me/
```

기대 결과:

- `Prometheus` UI 응답
- `Grafana` 로그인 페이지 응답
- `Alertmanager` UI 응답

참고:

- `Prometheus`, `Alertmanager`는 `HEAD` 요청에 `405 Method Not Allowed`를 반환할 수 있습니다.
- 따라서 `curl -I` 대신 일반 `GET` 요청 기준으로 `200` 응답을 확인하는 편이 더 정확합니다.
- `Prometheus`는 루트 경로에서 UI 경로로 리다이렉트하며 `302`를 반환할 수 있습니다.
- 따라서 `Prometheus`는 `200` 또는 `302`면 정상으로 봐도 됩니다.

### 7. Grafana 초기 로그인

초기 접속 계정:

- Username: `admin`
- Password: values에 지정한 `grafana.adminPassword`

로그인 후 확인:

- `Home` 대시보드 진입
- `Connections > Data sources`에서 Prometheus 기본 데이터소스 존재
- `Dashboards` 접근 가능

## 설치 검증

아래 검증을 모두 통과하면 기본 설치 완료로 판단합니다.

### 리소스 상태

```bash
kubectl -n monitoring get pods
kubectl -n monitoring get svc
kubectl -n monitoring get ingress
kubectl -n monitoring get pvc
```

정상 기준:

- 주요 파드가 모두 `Running`
- Prometheus, Grafana, Alertmanager Ingress가 생성됨
- Prometheus, Grafana, Alertmanager 관련 PVC가 `Bound`

### 서버 응답

```bash
kubectl -n monitoring logs deploy/monitoring-kube-prometheus-operator --tail=100
kubectl -n monitoring logs deploy/monitoring-grafana --tail=100
```

확인 포인트:

- 반복 재시작 오류 없음
- PVC 마운트 오류 없음
- Ingress/포트 충돌 오류 없음

## 운영 메모

- 이 문서는 모니터링 스택을 한 번에 설치하는 성공 경로를 기준으로 유지합니다.
- 홈랩 기준 replica는 `1`이면 충분합니다.
- 장기 보관이 필요하면 Prometheus retention과 PVC 크기를 함께 늘립니다.
- Loki를 함께 사용할 경우 Grafana 데이터소스만 추가로 연결하면 됩니다.

## 참고

- Kubernetes 기본 설치: [`../rke2/installation.md`](../rke2/installation.md)
- Longhorn 설치: [`../rke2/longhorn-installation.md`](../rke2/longhorn-installation.md)
- Loki 설치: [`../loki/installation.md`](../loki/installation.md)
- Helm chart 저장소: `https://prometheus-community.github.io/helm-charts`
