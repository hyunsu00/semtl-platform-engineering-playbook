# Grafana Installation

## 개요

이 문서는 이 저장소의 Kubernetes 표준 환경에 `Grafana`를 설치하고,
초기 관리자 계정 확인, `ingress-nginx` 노출, 기본 검증까지 수행하는 절차를 정리합니다.

이 문서의 기준은 다음과 같습니다.

- 대상 클러스터는 [`k8s 설치 문서`](../k8s/installation.md) 기준으로 이미 구축되어 있습니다.
- Ingress Controller는 `ingress-nginx`를 사용합니다.
- 외부 진입점은 `MetalLB`가 할당한 `ingress-nginx` 서비스 IP를 사용합니다.
- Grafana는 `grafana` 네임스페이스에 설치합니다.
- 설치 방식은 `Helm chart`를 사용합니다.

이 문서에서는 브라우저 접속과 운영 편의성을 위해
`Ingress`를 통한 HTTPS 노출을 기본값으로 사용합니다.

Grafana와 Prometheus를 분리 설치하는 이유:

- Grafana는 시각화 계층이라 데이터 수집기인 Prometheus와 역할이 다릅니다.
- Grafana 설정 변경이나 재배포가 Prometheus 수집 안정성에 직접 영향을 주지 않습니다.
- 운영 중 한쪽만 업그레이드하거나 교체하기가 더 쉽습니다.
- 필요하면 Grafana 하나로 여러 Prometheus를 동시에 연결할 수 있습니다.

## 사전 조건

- Kubernetes 클러스터가 정상이며 `kubectl` 접근이 가능합니다.
- `MetalLB`와 `ingress-nginx`가 이미 설치되어 있습니다.
- `helm` CLI가 설치되어 있습니다.
- 운영 도메인 예시: `grafana.semtl.synology.me`
- DNS가 `ingress-nginx` 외부 IP를 가리키도록 준비되어 있습니다.
- Synology Reverse Proxy에서 TLS를 종료할 수 있어야 합니다.

사전 확인 명령:

```bash
kubectl get nodes
kubectl -n ingress-nginx get pods
kubectl -n ingress-nginx get svc ingress-nginx-controller
helm version
```

정상 기준:

- 모든 노드가 `Ready`
- `ingress-nginx-controller` 파드가 `Running`
- `ingress-nginx-controller` 서비스의 `EXTERNAL-IP`가 할당됨
- `helm version`이 정상 응답

운영 기준 예시 DNS:

- `grafana.semtl.synology.me` -> `192.168.0.201`

## 배치 원칙

- 설치 네임스페이스: `grafana`
- 배포 방식: 공식 Helm chart
- 외부 노출: `Ingress`
- 내부 서비스 타입: `ClusterIP`
- 초기 관리자 계정: `admin`
- 관리 UI는 외부 공개 대신 사내망 또는 VPN 경유 노출을 기본으로 합니다.

주의:

- 운영 환경에서는 `NodePort`로 Grafana를 직접 노출하지 않습니다.
- 관리자 비밀번호는 values에 명시해 최초 로그인 값을 고정합니다.
- 대시보드 JSON, 데이터소스 설정, 플러그인 추가 여부는 설치 직후 기준을 문서화합니다.

## 설치 절차

### 1. 네임스페이스 생성

```bash
kubectl create namespace grafana
```

이미 존재하면 아래와 같이 확인만 수행합니다.

```bash
kubectl get ns grafana
```

### 2. Helm 저장소 등록

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

확인:

```bash
helm search repo grafana/grafana
```

### 3. Values 파일 작성

운영 기준 값을 `~/k8s/grafana/values-grafana.yaml`로 관리합니다.

```bash
mkdir -p ~/k8s/grafana

cat <<'EOF' > ~/k8s/grafana/values-grafana.yaml
adminUser: admin
adminPassword: <change-required>

service:
  type: ClusterIP

persistence:
  enabled: true
  size: 10Gi

ingress:
  enabled: true
  ingressClassName: nginx
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
  hosts:
    - grafana.semtl.synology.me

grafana.ini:
  server:
    domain: grafana.semtl.synology.me
    root_url: https://grafana.semtl.synology.me
  security:
    disable_initial_admin_creation: false
  users:
    viewers_can_edit: false

resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        access: proxy
        url: http://prometheus-kube-prometheus-prometheus.prometheus.svc.cluster.local:9090
        isDefault: true
EOF
```

기본 구성 설명:

- `adminPassword`를 미리 지정해 첫 로그인 때 비밀번호 확인 절차를 단순화합니다.
- `persistence.enabled=true`로 대시보드/설정 유실 가능성을 줄입니다.
- `service.type=ClusterIP`로 내부 서비스만 사용합니다.
- `ingress.enabled=true`로 `ingress-nginx`를 통해 외부 노출합니다.
- `root_url`은 실제 접속 도메인과 일치해야 합니다.
- Prometheus 데이터소스는 설치와 동시에 기본값으로 자동 등록됩니다.
- HTTPS 종단은 Kubernetes가 아니라 Synology Reverse Proxy에서 처리합니다.

### 4. Grafana 설치

```bash
helm upgrade --install grafana grafana/grafana \
  --namespace grafana \
  -f ~/k8s/grafana/values-grafana.yaml
```

설치 직후 확인:

```bash
helm list -n grafana
kubectl -n grafana get pods
kubectl -n grafana get svc
kubectl -n grafana get ingress
kubectl -n grafana get pvc
```

정상 기준:

- `helm list -n grafana`에 `grafana` 릴리스가 조회됨
- `grafana` 파드가 생성되고 잠시 후 `Running`
- `grafana` 서비스와 Ingress가 생성됨
- PVC가 `Bound`

대기 예시:

```bash
kubectl -n grafana rollout status deploy/grafana --timeout=5m
```

### 5. 초기 관리자 비밀번호 확인

이 문서의 성공 경로는 values에 지정한 비밀번호로 바로 로그인하는 방식입니다.

초기 접속 계정:

- Username: `admin`
- Password: `values-grafana.yaml`에 넣은 `adminPassword`

검증용으로 Secret 값을 직접 확인할 수도 있습니다.

```bash
kubectl -n grafana get secret grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d && echo
```

주의:

- 초기 비밀번호는 최초 로그인 후 즉시 변경합니다.
- 운영 환경에서는 비밀번호를 별도 비밀관리 시스템에 이관합니다.
- 기존 PVC를 재사용하는 재설치에서는 values의 `adminPassword` 변경만으로
  로그인 비밀번호가 바뀌지 않을 수 있습니다.

### 6. 초기 접속 확인 (`port-forward`)

Ingress를 붙이기 전, 내부 상태를 먼저 확인합니다.

```bash
kubectl -n grafana port-forward svc/grafana 3000:80
```

그다음 로컬 브라우저에서 아래 주소에 접속합니다.

- `http://127.0.0.1:3000`

이 단계에서 확인할 항목:

- 로그인 가능 여부
- 홈 대시보드 진입 가능 여부
- `Administration` 메뉴 노출 여부

### 7. 브라우저 접속 검증

Synology Reverse Proxy 예시:

- Source: `https://grafana.semtl.synology.me`
- Destination: `http://192.168.0.201`

즉 외부에서는 `443`으로 접속하고, Synology가 `ingress-nginx`의
`EXTERNAL-IP`인 `192.168.0.201`으로 프록시합니다.

DNS 반영 후 아래 주소로 접속합니다.

- `https://grafana.semtl.synology.me`

검증 항목:

- 로그인 페이지 응답
- `admin` 계정 로그인 성공
- 좌측 탐색 메뉴(`Dashboards`, `Connections`, `Administration`) 정상 노출
- 브라우저 개발자 도구 기준 정적 자산 로딩 오류 없음

### 8. 설치 직후 바로 사용하는 방법

이 문서 기준 values를 그대로 적용했다면 Prometheus 데이터소스는 자동 등록되어 있습니다.

먼저 아래 항목을 확인합니다.

- `Connections > Data sources`에 `Prometheus`가 보이는지 확인
- `Prometheus` 데이터소스 상세 화면에서 `Save & test` 성공 확인

그다음 바로 써볼 수 있는 기본 사용 흐름:

1. `Explore` 메뉴로 이동합니다.
2. 데이터소스로 `Prometheus`를 선택합니다.
3. 아래 쿼리 중 하나를 실행합니다.

```promql
up
```

```promql
sum by (job) (up)
```

```promql
rate(container_cpu_usage_seconds_total[5m])
```

대시보드 기본 사용 흐름:

1. `Dashboards > New > New dashboard`
2. `Add visualization`
3. 데이터소스 `Prometheus` 선택
4. 예시 쿼리 입력 후 시각화 저장

첫 대시보드 예시 쿼리:

```promql
sum(rate(node_cpu_seconds_total{mode!="idle"}[5m])) by (instance)
```

```promql
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100
```

주의:

- `Prometheus` 데이터소스가 자동으로 보이지 않으면 `kubectl -n prometheus get svc`로
  실제 서비스명이 `prometheus-kube-prometheus-prometheus`인지 먼저 확인합니다.
- Prometheus를 아직 설치하지 않았다면 datasources 블록을 제거하거나
  설치 후 다시 Helm upgrade를 수행합니다.

### 9. 초기 보안 조치

설치 직후 아래 항목을 바로 수행합니다.

1. `admin` 비밀번호 변경
2. 외부 인증(예: OIDC/SSO) 도입 전까지 관리자 계정 접근 주체 최소화
3. 익명 접근, 공개 공유 링크, 과도한 편집 권한 여부 확인
4. `grafana` 네임스페이스 리소스 상태 스냅샷 저장

스냅샷 예시:

```bash
mkdir -p .local/scratch
kubectl -n grafana get all -o wide \
  > .local/scratch/2026-04-03-grafana-install-status-v1.txt
kubectl -n grafana get cm,secret,ingress,pvc \
  > .local/scratch/2026-04-03-grafana-install-config-v1.txt
```

주의:

- `.local/` 산출물은 참고용이며 Git에 커밋하지 않습니다.
- `Secret` 전체 YAML을 평문으로 보관할 때는 접근권한을 별도로 통제합니다.

## 설치 검증

아래 검증을 모두 통과하면 기본 설치 완료로 판단합니다.

### 리소스 상태

```bash
kubectl -n grafana get pods
kubectl -n grafana get svc
kubectl -n grafana get ingress
kubectl -n grafana get pvc
```

정상 기준:

- 주요 파드가 `Running`
- `grafana` 서비스가 존재
- `grafana` Ingress가 생성됨
- PVC가 `Bound`

### 서버 응답

```bash
kubectl -n grafana logs deploy/grafana --tail=100
```

확인 포인트:

- 반복 재시작 오류 없음
- 플러그인 초기화 오류 없음
- `root_url` 또는 세션 관련 경고가 과도하게 반복되지 않음

### UI 접근

- 브라우저 로그인 성공
- 기본 홈 대시보드 정상 진입
- `Prometheus` 데이터소스 `Save & test` 정상
- `Explore`에서 기본 PromQL 실행 가능

## 운영 메모

별도 운영 가이드를 두지 않는 대신, 설치 직후부터 아래 기준을 기본 운영 원칙으로 사용합니다.

### 일일/주간 확인 항목

- `kubectl -n grafana get pods`로 재시작 여부 확인
- `kubectl -n grafana logs deploy/grafana --tail=100`로 최근 오류 확인
- PVC 사용량과 노드 디스크 여유 공간 확인
- 관리자 계정, API 토큰, 데이터소스 인증정보 만료 예정 여부 확인
- 데이터소스 `Save & test` 결과와 대시보드 패널 오류 여부 확인

### 변경 관리 기준

- Helm values 변경 전에는 현재 값을 백업하고 변경 후 `helm diff` 또는 `helm get values` 결과를 남깁니다.
- 도메인, TLS, `root_url`, SSO 설정 변경 시에는 로그인과 정적 자산 로딩을 함께 검증합니다.
- 플러그인 추가 시에는 보안 검토와 재기동 시간을 함께 고려합니다.

### 백업 및 복구 메모

- 최소 백업 대상은 `grafana` 네임스페이스의 `Secret`, `ConfigMap`, `Ingress`, `PVC` 정보입니다.
- 대시보드를 파일로 관리하지 않는 경우 UI에서 만든 대시보드 유실 가능성을 별도로 관리합니다.
- 데이터소스 자격증명과 관리자 비밀번호는 애플리케이션 설정과 분리해 관리합니다.

## 초기 트러블슈팅

별도 트러블슈팅 문서를 두지 않는 대신, 설치 직후 자주 만나는 이슈를 아래에 함께 정리합니다.

### 증상: `grafana` 파드가 재시작을 반복함

확인 명령:

```bash
kubectl -n grafana get pods
kubectl -n grafana describe pod -l app.kubernetes.io/name=grafana
kubectl -n grafana logs deploy/grafana --tail=100
```

주요 원인:

- Values YAML 문법 오류 또는 잘못된 `grafana.ini` 설정
- PVC 마운트 실패
- 플러그인 설치 또는 권한 문제

조치:

- `helm get values grafana -n grafana`로 적용값을 다시 확인합니다.
- PVC 상태와 이벤트를 확인합니다.
- 최근 Values 변경이 원인이면 직전 정상 값으로 롤백합니다.
- 비밀번호 문제라면 Secret 값과 values의 `adminPassword`가 일치하는지 먼저 확인합니다.

### 증상: 브라우저에서 UI 접속이 되지 않음

확인 명령:

```bash
kubectl -n grafana get ingress
kubectl -n grafana describe ingress grafana
kubectl -n ingress-nginx get svc ingress-nginx-controller
kubectl -n grafana get svc grafana
```

주요 원인:

- DNS가 `ingress-nginx` 외부 IP를 가리키지 않음
- `root_url`과 실제 접속 도메인 불일치
- 방화벽 또는 Reverse Proxy 경로 미개방

조치:

- 도메인 해석 결과와 `ingress-nginx-controller`의 `EXTERNAL-IP`를 대조합니다.
- `grafana.ini.server.root_url`이 실제 접속 주소와 일치하는지 확인합니다.
- Synology Reverse Proxy 대상이 `http://192.168.0.201`로 향하는지 확인합니다.
- 필요하면 `port-forward` 접속으로 서버 자체 정상 여부를 먼저 분리 진단합니다.

### 증상: 로그인은 되지만 대시보드 또는 데이터소스가 정상 동작하지 않음

확인 항목:

- `Connections > Data sources`의 연결 상태
- 브라우저 콘솔 오류
- Grafana 서버 로그의 datasource 관련 오류

주요 원인:

- Prometheus 서비스명 또는 URL 오입력
- 데이터소스 인증정보 오류
- 네임스페이스 간 네트워크 정책 또는 서비스 DNS 문제

조치:

- `kubectl -n prometheus get svc`로 실제 서비스명을 다시 확인합니다.
- `Save & test` 기준으로 데이터소스 연결을 재검증합니다.
- 필요한 경우 Grafana 파드 내부에서 대상 서비스 DNS 해석 가능 여부를 확인합니다.
- 자동 등록된 데이터소스 URL이 다르면 values의 datasources 블록을 수정합니다.

## 롤백 절차

설치를 되돌려야 하면 아래 순서로 정리합니다.

```bash
helm uninstall grafana -n grafana
kubectl delete namespace grafana
```

확인:

```bash
helm list -n grafana
kubectl get ns grafana
kubectl get ingress -A | grep grafana
```

주의:

- PVC 삭제 여부에 따라 대시보드와 설정 데이터 보존 여부가 달라집니다.
- 롤백 전에 보존이 필요한 데이터와 Secret이 있는지 먼저 확인합니다.

## 참고

- Kubernetes 클러스터 기본 설치: [`../k8s/installation.md`](../k8s/installation.md)
- 공식 Helm chart 저장소: `https://grafana.github.io/helm-charts`
- 공식 Grafana 문서: `https://grafana.com/docs/`
