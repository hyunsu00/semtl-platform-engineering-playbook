# Prometheus Installation

## 개요

이 문서는 이 저장소의 Kubernetes 표준 환경에 `Prometheus`를 설치하고,
초기 접근 경로, `ingress-nginx` 노출, 기본 검증까지 수행하는 절차를 정리합니다.

이 문서의 기준은 다음과 같습니다.

- 대상 클러스터는 [`RKE2 설치 문서`](../rke2/installation.md) 기준으로 이미 구축되어 있습니다.
- Ingress Controller는 `ingress-nginx`를 사용합니다.
- 외부 진입점은 `MetalLB`가 할당한 `ingress-nginx` 서비스 IP를 사용합니다.
- Prometheus는 `prometheus` 네임스페이스에 설치합니다.
- 설치 방식은 `kube-prometheus-stack` Helm chart를 사용합니다.

이 문서에서는 Prometheus 단독 설치보다 운영 편의성이 높은
`Prometheus Operator` 기반 배포를 기본값으로 사용합니다.

이번 문서의 목표는 실패 사례를 배제하고, 최소 설정으로 한 번에 설치가 끝나는
성공 경로를 제공하는 것입니다.

스토리지 기준은 현재 사용하는 StorageClass 정책에 맞춰 함께 검토합니다.
이 문서는 운영 핵심 스택 표준에 맞춰 `Longhorn` 기반 설치를 기준으로 작성합니다.

Prometheus와 Grafana를 분리 설치하는 이유:

- Prometheus는 메트릭 수집과 저장에 집중합니다.
- Grafana는 시각화와 대시보드 구성에 집중합니다.
- 장애 원인 분리와 업그레이드 관리가 쉬워집니다.
- Grafana만 별도 재설치하거나 교체해도 Prometheus 데이터를 계속 사용할 수 있습니다.

## 사전 조건

- Kubernetes 클러스터가 정상이며 `kubectl` 접근이 가능합니다.
- `MetalLB`와 `ingress-nginx`가 이미 설치되어 있습니다.
- `helm` CLI가 설치되어 있습니다.
- `Longhorn`이 이미 설치되어 있고 `longhorn` StorageClass를 사용할 수 있어야 합니다.
- 운영 도메인 예시: `prometheus.semtl.synology.me`
- DNS가 `ingress-nginx` 외부 IP를 가리키도록 준비되어 있습니다.
- Synology Reverse Proxy에서 TLS를 종료할 수 있어야 합니다.

사전 확인 명령:

```bash
kubectl get nodes
kubectl -n ingress-nginx get pods
kubectl -n ingress-nginx get svc ingress-nginx-controller
kubectl get storageclass
helm version
```

정상 기준:

- 모든 노드가 `Ready`
- `ingress-nginx-controller` 파드가 `Running`
- `ingress-nginx-controller` 서비스의 `EXTERNAL-IP`가 할당됨
- `longhorn` StorageClass가 존재
- `helm version`이 정상 응답

운영 기준 예시 DNS:

- `prometheus.semtl.synology.me` -> 현재 `ingress-nginx-controller`의 `EXTERNAL-IP`

예시 확인:

```bash
kubectl -n ingress-nginx get svc ingress-nginx-controller
```

예를 들어 위 명령 결과가 `192.168.0.200`이면 DNS도 아래처럼 맞춥니다.

- `prometheus.semtl.synology.me` -> `192.168.0.200`

## 배치 원칙

- 설치 네임스페이스: `prometheus`
- 배포 방식: `kube-prometheus-stack`
- 외부 노출: `Ingress`
- 내부 서비스 타입: `ClusterIP`
- 운영 접근은 사내망 또는 VPN 경유를 기본으로 합니다.
- Alertmanager, kube-state-metrics, node-exporter는 stack 기본 구성으로 함께 설치합니다.

Prometheus를 외부로 노출하는 이유:

- 클러스터 밖에서도 브라우저로 `Targets`, `Alerts`, PromQL 결과를 바로 확인할 수 있습니다.
- Grafana 없이도 초기 설치 검증과 장애 분석이 가능합니다.
- 원격 대응 시 메트릭 수집 상태와 `DOWN` 타깃을 빠르게 점검할 수 있습니다.
- Reverse Proxy, SSO, 운영 포털과 연결하기가 쉽습니다.

주의:

- 운영 환경에서는 Prometheus를 `NodePort`로 직접 노출하지 않습니다.
- 공인 인터넷에 직접 공개하지 말고 사내망, VPN, SSO 뒤에서만 노출하는 것을 권장합니다.
- 장기 보관이 필요하면 retention과 PVC 크기를 함께 설계합니다.
- Alert 라우팅은 설치 직후 검증하지 않더라도 최소 기본 수신 경로는 빠르게 준비합니다.
- Grafana는 이 stack에 포함하지 않고 별도 설치해 역할을 분리합니다.
- Prometheus는 Grafana와 마찬가지로 같은 `ingress-nginx`의 `EXTERNAL-IP`를 공유할 수 있습니다.
- 서비스별 구분은 별도 IP가 아니라 `prometheus.semtl.synology.me` 같은 host 기준으로 처리합니다.

## 설치 절차

### 1. 네임스페이스 생성

```bash
kubectl create namespace prometheus
```

이미 존재하면 아래와 같이 확인만 수행합니다.

```bash
kubectl get ns prometheus
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

### 3. Longhorn StorageClass 확인

이 문서는 `Longhorn`이 이미 준비되어 있다는 전제로 진행합니다.
Longhorn 설치와 스토리지 역할 구분은 현재 사용하는 StorageClass 정책 기준으로 먼저 확인합니다.

확인 명령:

```bash
kubectl get storageclass
kubectl -n longhorn-system get pods
```

정상 기준:

- `longhorn` StorageClass가 존재
- `longhorn-system` 주요 파드가 `Running`

참고:

- Prometheus는 이 문서 기준으로 `longhorn` PVC를 사용합니다.

### 4. Values 파일 작성

운영 기준 값을 `~/k8s/prometheus/values-prometheus.yaml`로 관리합니다.

```bash
mkdir -p ~/k8s/prometheus

cat <<'EOF' > ~/k8s/prometheus/values-prometheus.yaml
grafana:
  enabled: false

alertmanager:
  enabled: true

prometheus:
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
    hosts:
      - prometheus.semtl.synology.me
  prometheusSpec:
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
EOF
```

기본 구성 설명:

- `grafana.enabled=false`로 Grafana는 별도 문서 기준으로 분리 설치합니다.
- `retention`과 `retentionSize`는 디스크 용량에 맞춰 함께 조정합니다.
- Prometheus UI는 Ingress로 노출하되, 내부 서비스는 `ClusterIP` 기반으로 유지합니다.
- 기본 alert rule은 활성화해 클러스터 기초 이상 징후를 빠르게 확인합니다.
- 이 values 파일은 최소 성공 경로만 남긴 기준값입니다.
- HTTPS 종단은 Kubernetes가 아니라 Synology Reverse Proxy에서 처리합니다.
- `storageClassName: longhorn`으로 운영 핵심 스택용 스토리지를 사용합니다.

### 5. Prometheus stack 설치

```bash
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace prometheus \
  -f ~/k8s/prometheus/values-prometheus.yaml
```

설치 직후 확인:

```bash
helm list -n prometheus
kubectl -n prometheus get pods
kubectl -n prometheus get svc
kubectl -n prometheus get ingress
kubectl -n prometheus get pvc
kubectl get storageclass
```

정상 기준:

- `helm list -n prometheus`에 `prometheus` 릴리스가 조회됨
- `prometheus-*`, `alertmanager-*`, `kube-state-metrics`,
  `node-exporter` 관련 리소스가 생성됨
- Ingress가 생성됨
- Prometheus PVC가 `Bound`

대기 예시:

```bash
kubectl -n prometheus rollout status \
  deploy/prometheus-kube-prometheus-operator --timeout=5m
kubectl -n prometheus rollout status deploy/prometheus-kube-state-metrics --timeout=5m
```

상태 확인 예시:

```bash
kubectl -n prometheus get pods -o wide
```

설치가 `Pending` 상태에서 멈추면 아래 `초기 트러블슈팅`의
`Prometheus 파드가 재시작을 반복함` 항목과 PVC/StorageClass 확인 절차를 먼저 봅니다.

### 6. 내부 서비스 확인

Prometheus 서비스명은 chart 버전에 따라 다를 수 있으므로 먼저 확인합니다.

```bash
kubectl -n prometheus get svc
```

이 문서 기준 예시 서비스:

- `prometheus-kube-prometheus-prometheus`

Alertmanager 예시 서비스:

- `prometheus-kube-prometheus-alertmanager`

참고:

- 이 문서 기준으로 `Service`는 내부용 `ClusterIP`가 정상입니다.
- `kubectl -n prometheus get svc`에서 `EXTERNAL-IP`가 없어도 문제 아닙니다.
- 외부 노출 여부는 `Service`가 아니라 `Ingress`의 `ADDRESS` 기준으로 확인합니다.

### 7. 초기 접속 확인 (`port-forward`)

Ingress를 붙이기 전, 내부 상태를 먼저 확인합니다.

```bash
kubectl -n prometheus port-forward \
  svc/prometheus-kube-prometheus-prometheus 9090:9090
```

그다음 `curl`로 먼저 응답을 확인합니다.

```bash
curl -I http://127.0.0.1:9090/-/ready
curl -s http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=up'
```

이 단계에서 확인할 항목:

- `/-/ready` 응답이 `200 OK`
- API 쿼리 응답이 JSON으로 반환됨
- 필요하면 같은 주소를 브라우저에서 열어 UI도 확인 가능

### 8. 브라우저 접속 검증

Synology Reverse Proxy 예시:

- Source: `https://prometheus.semtl.synology.me`
- Destination: `http://<INGRESS_EXTERNAL_IP>:80`

즉 외부에서는 `443`으로 접속하고, Synology가 `ingress-nginx`의
`EXTERNAL-IP`로 프록시합니다.

예:

- `kubectl -n ingress-nginx get svc ingress-nginx-controller` 결과가 `192.168.0.200`
- Synology Reverse Proxy 대상: `http://192.168.0.200:80`

참고:

- Prometheus와 Grafana는 같은 `ingress-nginx` 외부 IP를 함께 사용할 수 있습니다.
- 예를 들어 둘 다 `192.168.0.200`을 공유하고, host 기준으로 라우팅합니다.

DNS 반영 후 아래 주소로 접속합니다.

- `https://prometheus.semtl.synology.me`

검증 항목:

- `curl -I https://prometheus.semtl.synology.me/-/ready` 응답 확인
- `curl -sG https://prometheus.semtl.synology.me/api/v1/query \
  --data-urlencode 'query=up'` 결과 확인
- 필요하면 브라우저에서 `Target health`, `Rule health`, `Graph` 화면 추가 확인

### 9. 주요 타깃 확인

설치 직후 최소 아래 타깃이 수집되는지 확인합니다.

- `kube-apiserver`
- `kube-state-metrics`
- `node-exporter`
- `prometheus-kube-prometheus-operator`

쿼리 예시:

```promql
up
```

```promql
sum by (job) (up)
```

주의:

- 일부 control-plane 메트릭 수집 여부는 클러스터 보안 설정과 chart 버전에 따라 달라질 수 있습니다.
- `DOWN` 타깃이 있으면 서비스명, ServiceMonitor, 네트워크 경로를 함께 확인합니다.

## 설치 직후 바로 사용하는 방법

Prometheus는 UI 없이도 API와 `curl`만으로 기본 확인이 가능합니다.
필요하면 이후 브라우저에서 같은 내용을 다시 확인합니다.

### 1. 타깃 상태 확인

먼저 API로 기본 응답을 확인합니다.

```bash
curl -s http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=up'
```

그다음 UI를 사용할 수 있으면 `Target health`에서 아래 항목이 `UP`인지 확인합니다.

- `kube-state-metrics`
- `node-exporter`
- `prometheus-kube-prometheus-operator`

### 2. 기본 쿼리 실행

API 또는 UI `Graph` 탭에서 아래 쿼리를 순서대로 실행합니다.

```promql
up
```

```promql
sum by (job) (up)
```

```promql
rate(container_cpu_usage_seconds_total[5m])
```

```promql
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100
```

### 3. 기본적으로 자주 보는 화면

- `Target health`: 스크랩 성공 여부 확인
- `Rule health`: 기본 alert/rule 로딩 여부 확인
- `Alerts`: firing/pending 상태 확인
- `Graph`: PromQL 직접 실행

### 4. Grafana 연동에 사용할 Prometheus URL

같은 클러스터 내부에서 Grafana가 접속할 기본 URL은 아래 예시를 사용합니다.

- `http://prometheus-kube-prometheus-prometheus.prometheus.svc.cluster.local:9090`

Grafana 설치 문서의 데이터소스 자동 등록 예시도 이 주소를 기준으로 작성했습니다.

### 10. 초기 보안 조치

설치 직후 아래 항목을 바로 수행합니다.

1. 외부 노출 범위가 사내망/VPN 기준으로 제한되는지 확인
2. Alertmanager 기본 수신 경로 또는 사일런스 정책 초안 준비
3. retention과 PVC 크기가 운영 기준과 맞는지 확인
4. 설치 직후 아래 명령으로 현재 상태를 한 번 확인

```bash
kubectl -n prometheus get pods
kubectl -n prometheus get pvc
kubectl -n prometheus get ingress
```

참고:

- 상태 스냅샷을 남기고 싶다면 `values` 파일과 분리해서
  `~/k8s/prometheus/snapshot/` 아래에 저장하는 것을 권장합니다.
- 설치 자체에 필수는 아니지만, 이후 장애 비교나 재설치 전 점검에 도움이 됩니다.

예:

```bash
mkdir -p ~/k8s/prometheus/snapshot
SNAPSHOT_DATE=$(date +%F)

kubectl -n prometheus get pods -o wide \
  > ~/k8s/prometheus/snapshot/${SNAPSHOT_DATE}-prometheus-pods.txt
kubectl -n prometheus get pvc \
  > ~/k8s/prometheus/snapshot/${SNAPSHOT_DATE}-prometheus-pvc.txt
kubectl -n prometheus get ingress \
  > ~/k8s/prometheus/snapshot/${SNAPSHOT_DATE}-prometheus-ingress.txt
kubectl get storageclass \
  > ~/k8s/prometheus/snapshot/${SNAPSHOT_DATE}-storageclass.txt
```

## 설치 검증

아래 검증을 모두 통과하면 기본 설치 완료로 판단합니다.

### 리소스 상태

```bash
kubectl -n prometheus get pods
kubectl -n prometheus get svc
kubectl -n prometheus get ingress
kubectl -n prometheus get pvc
kubectl -n prometheus get prometheus
```

정상 기준:

- 주요 파드가 `Running`
- Prometheus 서비스가 존재
- Prometheus Ingress가 생성됨
- PVC가 `Bound`
- `Prometheus` 커스텀 리소스가 생성됨

### 서버 응답

```bash
kubectl -n prometheus logs \
  deploy/prometheus-kube-prometheus-operator --tail=100
kubectl -n prometheus logs \
  statefulset/prometheus-prometheus-kube-prometheus-prometheus --tail=100
```

확인 포인트:

- Operator reconcile 오류가 반복되지 않음
- TSDB 초기화 오류 없음
- 스토리지 마운트 실패 오류 없음

### UI 및 쿼리 접근

- 브라우저 UI 정상 진입
- `up` 쿼리 정상 실행
- `Target health` 화면에서 핵심 타깃 `UP`
- `Alerts` 또는 `Rule health` 화면 정상 진입

## 재설치 전 완전 정리

설치가 중간에 실패했거나 values를 크게 바꾼 뒤 처음부터 다시 올리고 싶다면,
아래 순서로 기존 리소스를 먼저 정리합니다.

### 1. Helm 릴리스 제거

```bash
helm uninstall prometheus -n prometheus
```

확인:

```bash
helm list -n prometheus
```

### 2. 네임스페이스 리소스 확인

```bash
kubectl get all -n prometheus
kubectl get pvc -n prometheus
kubectl get ingress -n prometheus
kubectl get prometheus -n prometheus
```

### 3. 네임스페이스 전체 삭제 후 재생성

가장 깔끔한 재시작 방법은 네임스페이스를 통째로 다시 만드는 것입니다.

```bash
kubectl delete namespace prometheus
kubectl create namespace prometheus
```

확인:

```bash
kubectl get ns prometheus
```

### 4. PVC/PV 잔여물 확인

네임스페이스를 삭제했더라도 스토리지 정책에 따라 PV가 남아 있을 수 있습니다.

```bash
kubectl get pvc -n prometheus
kubectl get pv | grep prometheus
```

참고:

- `kubectl get pvc -n prometheus`는 새 네임스페이스 직후 비어 있어야 정상입니다.
- `kubectl get pv | grep prometheus` 결과가 남아 있으면 상태를 한 번 더 확인합니다.

### 5. 다시 설치

```bash
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace prometheus \
  -f ~/k8s/prometheus/values-prometheus.yaml
```

재설치 직후 확인:

```bash
kubectl -n prometheus get pods
kubectl -n prometheus get pvc
kubectl -n prometheus get ingress
```

## 운영 메모

별도 운영 가이드를 두지 않는 대신, 설치 직후부터 아래 기준을 기본 운영 원칙으로 사용합니다.

### 일일/주간 확인 항목

- `kubectl -n prometheus get pods`로 재시작 여부 확인
- Prometheus PVC 사용량과 노드 디스크 여유 공간 확인
- `Target health` 화면에서 주요 타깃 `DOWN` 여부 확인
- Alertmanager 알림 경로와 사일런스 상태 확인

### 변경 관리 기준

- Helm values 변경 전에는 현재 값을 백업하고 변경 후 `helm get values` 결과를 남깁니다.
- retention, storage, rule 변경은 운영 영향이 크므로 시간대와 롤백 절차를 함께 준비합니다.
- ServiceMonitor/PodMonitor 추가 시에는 label selector와 스크랩 경로를 함께 검증합니다.

### 백업 및 복구 메모

- 최소 백업 대상은 `values` 파일, `Prometheus` 관련 커스텀 리소스, `Alertmanager` 설정, PVC 정보입니다.
- TSDB는 용량이 크므로 전체 백업보다 retention 설계와 스냅샷 정책을 먼저 정합니다.
- 복구 전에는 모니터링 공백 허용 시간과 알림 중단 영향을 먼저 검토합니다.

## 초기 트러블슈팅

별도 트러블슈팅 문서를 두지 않는 대신, 설치 직후 자주 만나는 이슈를 아래에 함께 정리합니다.

### 증상: Prometheus 파드가 재시작을 반복함

확인 명령:

```bash
kubectl -n prometheus get pods
kubectl -n prometheus describe pod \
  -l app.kubernetes.io/name=prometheus
kubectl -n prometheus logs \
  statefulset/prometheus-prometheus-kube-prometheus-prometheus --tail=100
```

주요 원인:

- PVC 바인딩 실패
- retention 또는 저장소 크기 설정 부적절
- TSDB 손상 또는 초기화 실패
- 기본 `StorageClass` 부재

조치:

- PVC 상태와 이벤트를 확인합니다.
- `kubectl get storageclass`로 기본 StorageClass 존재 여부를 확인합니다.
- values의 `storageSpec`, `retention`, `retentionSize` 값을 다시 검토합니다.
- 최근 설정 변경이 원인이면 직전 정상 values로 롤백합니다.

### 증상: 브라우저에서 UI 접속이 되지 않음

확인 명령:

```bash
kubectl -n prometheus get ingress
kubectl -n prometheus describe ingress prometheus-kube-prometheus-prometheus
kubectl -n ingress-nginx get svc ingress-nginx-controller
kubectl -n prometheus get svc
```

주요 원인:

- DNS가 `ingress-nginx` 외부 IP를 가리키지 않음
- Ingress host와 실제 접속 도메인 불일치
- 방화벽 또는 Reverse Proxy 경로 미개방

조치:

- 도메인 해석 결과와 `ingress-nginx-controller`의 `EXTERNAL-IP`를 대조합니다.
- 실제 생성된 Ingress 이름과 host 값을 다시 확인합니다.
- Synology Reverse Proxy 대상이 실제 `EXTERNAL-IP`로 향하는지 확인합니다.
- `EXTERNAL-IP`가 보이는데도 `80/443` 연결이 거부되면
  [`RKE2 설치 문서`](../rke2/installation.md)의
  `Ingress EXTERNAL-IP는 보이지만 80/443 연결 거부` 항목을 확인합니다.
- 필요하면 `port-forward` 접속으로 서버 자체 정상 여부를 먼저 분리 진단합니다.

### 증상: 타깃이 `DOWN`으로 표시됨

확인 항목:

- `Target health`
- 관련 `ServiceMonitor`, `PodMonitor`, `Service`
- 대상 워크로드의 포트와 경로

주요 원인:

- ServiceMonitor selector 불일치
- 대상 서비스 포트명 또는 엔드포인트 경로 오류
- 네트워크 정책 또는 서비스 DNS 문제

조치:

- `kubectl -n <namespace> get servicemonitor,podmonitor,svc,endpoints`로 연결 대상을 확인합니다.
- 스크랩 대상의 `port` 이름과 path가 실제 서비스와 일치하는지 검토합니다.
- 최근 배포 변경 이후 발생했다면 직전 선언 상태와 diff를 비교합니다.

## 롤백 절차

설치를 되돌려야 하면 아래 순서로 정리합니다.

```bash
helm uninstall prometheus -n prometheus
kubectl delete namespace prometheus
```

확인:

```bash
helm list -n prometheus
kubectl get ns prometheus
kubectl get ingress -A | grep prometheus
```

주의:

- PVC 삭제 여부에 따라 시계열 데이터 보존 여부가 달라집니다.
- 롤백 전에 보존이 필요한 TSDB 데이터와 Alert 설정이 있는지 먼저 확인합니다.

## 참고

- Kubernetes 클러스터 기본 설치: [`../rke2/installation.md`](../rke2/installation.md)
- 공식 Helm chart 저장소: `https://prometheus-community.github.io/helm-charts`
- 공식 Prometheus 문서: `https://prometheus.io/docs/`
