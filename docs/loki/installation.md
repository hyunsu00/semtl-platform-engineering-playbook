# Loki Installation (작업중)

## 개요

이 문서는 이 저장소의 Kubernetes 표준 환경에 `Loki`를 설치하고,
`MinIO`를 object storage로 연결한 뒤 `Grafana` 데이터소스까지 검증하는 절차를 정리합니다.

이 문서의 기준은 다음과 같습니다.

- 대상 클러스터는 [`RKE2 설치 문서`](../rke2/installation.md) 기준으로 이미 구축되어 있습니다.
- 스토리지 기준은 현재 사용하는 StorageClass 정책에 맞춰 별도 운영 기준으로 관리합니다.
- `Grafana`와 `Prometheus`는 이미 분리 설치되어 있습니다.
- Loki는 작은 메타 모니터링 스택에 적합한 `SingleBinary` 모드로 설치합니다.
- 장기 로그 저장소는 `MinIO`의 S3 호환 API를 사용합니다.

이 문서의 목표는 실패 사례를 배제하고, 최소 설정으로 한 번에 설치가 끝나는
성공 경로를 제공하는 것입니다.

중요:

- Loki 자체는 로그 저장/조회 서버입니다.
- 실제 로그 수집은 `Grafana Alloy` 또는 `Promtail` 같은 별도 에이전트가 필요합니다.
- 따라서 이 문서 설치만으로는 로그가 자동 유입되지 않습니다.

## 사전 조건

- Kubernetes 클러스터가 정상이며 `kubectl` 접근이 가능합니다.
- `helm` CLI가 설치되어 있습니다.
- `MinIO`가 이미 설치되어 있고 S3 API endpoint 접근이 가능합니다.
- `Grafana`가 이미 설치되어 있습니다.
- `ingress-nginx`가 이미 설치되어 있습니다.

사전 확인 명령:

```bash
kubectl get nodes
kubectl -n ingress-nginx get pods
kubectl -n grafana get pods
helm version
mc --version
```

정상 기준:

- 모든 노드가 `Ready`
- `ingress-nginx-controller` 파드가 `Running`
- `grafana` 파드가 `Running`
- `helm version`이 정상 응답
- `mc --version`이 정상 응답

공식 기준 참고:

- Grafana Loki 공식 문서는 작은 메타 모니터링 스택에서는 `monolithic` 설치를 권장합니다.
- Loki Helm chart의 gateway는 Ingress를 사용할 때 기본 진입점 역할을 합니다.
- Loki에는 기본 인증 계층이 포함되어 있지 않습니다.

## 권장 아키텍처

- 설치 네임스페이스: `loki`
- 배포 모드: `SingleBinary`
- object storage: `MinIO`
- 외부 노출: `Ingress`
- 내부 Grafana 데이터소스 URL: `http://loki-gateway.loki.svc.cluster.local/`

운영 메모:

- 이 문서 기준 MinIO bucket은 `loki-chunks`, `loki-ruler`, `loki-admin` 3개를 사용합니다.
- Loki gateway가 Ingress의 실제 backend가 됩니다.
- 외부 노출이 필요하더라도 공인 인터넷 직접 공개는 피하고 사내망, VPN, SSO 뒤에서만 노출합니다.

## 설치 절차

### 1. MinIO bucket과 전용 계정 준비

이 단계는 `MinIO` 관리가 가능한 노드에서 수행합니다.

예시:

```bash
mc alias set local http://192.168.0.171:9000 admin '<change-required>'
mc mb -p local/loki-chunks
mc mb -p local/loki-ruler
mc mb -p local/loki-admin
```

Loki 전용 정책 파일 예시:

```bash
mkdir -p ~/k8s/loki

cat <<'EOF' > ~/k8s/loki/loki-minio-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads"
      ],
      "Resource": [
        "arn:aws:s3:::loki-chunks",
        "arn:aws:s3:::loki-ruler",
        "arn:aws:s3:::loki-admin"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:AbortMultipartUpload",
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:ListMultipartUploadParts",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::loki-chunks/*",
        "arn:aws:s3:::loki-ruler/*",
        "arn:aws:s3:::loki-admin/*"
      ]
    }
  ]
}
EOF
```

정책과 계정 생성:

```bash
mc admin policy create local loki-policy ~/k8s/loki/loki-minio-policy.json
mc admin user add local loki '<change-required>'
mc admin policy attach local loki-policy --user loki
```

확인:

```bash
mc ls local/loki-chunks
mc ls local/loki-ruler
mc ls local/loki-admin
mc admin user info local loki
```

### 2. Helm 저장소 등록

Grafana Loki 공식 문서는 현재 `grafana-community` 저장소 기준 예시를 사용합니다.

```bash
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo update
```

확인:

```bash
helm search repo grafana-community/loki
```

### 3. Values 파일 작성

운영 기준 값을 `~/k8s/loki/values-loki.yaml`로 관리합니다.

```bash
cat <<'EOF' > ~/k8s/loki/values-loki.yaml
loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  schemaConfig:
    configs:
      - from: "2024-04-01"
        store: tsdb
        object_store: s3
        schema: v13
        index:
          prefix: loki_index_
          period: 24h
  storage:
    type: s3
    bucketNames:
      chunks: loki-chunks
      ruler: loki-ruler
      admin: loki-admin
    s3:
      endpoint: 192.168.0.171:9000
      region: minio
      accessKeyId: loki
      secretAccessKey: <change-required>
      s3ForcePathStyle: true
      insecure: true
  limits_config:
    allow_structured_metadata: true
    volume_enabled: true
    retention_period: 168h

deploymentMode: SingleBinary

singleBinary:
  replicas: 1

backend:
  replicas: 0
read:
  replicas: 0
write:
  replicas: 0
ingester:
  replicas: 0
querier:
  replicas: 0
queryFrontend:
  replicas: 0
queryScheduler:
  replicas: 0
distributor:
  replicas: 0
compactor:
  replicas: 0
indexGateway:
  replicas: 0
bloomCompactor:
  replicas: 0
bloomGateway:
  replicas: 0

minio:
  enabled: false

lokiCanary:
  enabled: true

gateway:
  enabled: true
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
    hosts:
      - host: loki.semtl.synology.me
        paths:
          - path: /
            pathType: Prefix

monitoring:
  serviceMonitor:
    enabled: true
EOF
```

기본 구성 설명:

- `SingleBinary`는 작은 홈랩/메타 모니터링 환경에 맞는 단순한 배포 방식입니다.
- `replication_factor: 1`은 단일 replica 기준 필수 설정입니다.
- `storage.type: s3`와 `MinIO` endpoint를 함께 써서 object storage를 분리합니다.
- `gateway.enabled: true`여야 Ingress를 통해 Loki API를 노출할 수 있습니다.
- `auth_enabled: false`이므로 외부 접근은 반드시 Reverse Proxy, VPN, SSO 등으로 제한합니다.
- `monitoring.serviceMonitor.enabled: true`로 Prometheus가 Loki 메트릭을 수집할 수 있게 합니다.

### 4. Loki 설치

```bash
helm upgrade --install loki grafana-community/loki \
  --namespace loki \
  --create-namespace \
  -f ~/k8s/loki/values-loki.yaml
```

설치 직후 확인:

```bash
helm list -n loki
kubectl -n loki get pods
kubectl -n loki get svc
kubectl -n loki get ingress
```

정상 기준:

- `helm list -n loki`에 `loki` 릴리스가 조회됨
- `loki`, `loki-gateway`, `loki-canary` 관련 파드가 생성됨
- `loki-gateway` 서비스와 Ingress가 생성됨

### 5. 내부 서비스 확인

```bash
kubectl -n loki get svc
```

이 문서 기준 Grafana 데이터소스 URL:

- `http://loki-gateway.loki.svc.cluster.local/`

참고:

- Loki는 Grafana, Prometheus와 마찬가지로 같은 `ingress-nginx`의 `EXTERNAL-IP`를 공유할 수 있습니다.
- 서비스별 구분은 별도 IP가 아니라 `loki.semtl.synology.me` 같은 host 기준으로 처리합니다.

### 6. 초기 접속 확인 (`port-forward`)

Ingress를 붙이기 전, 내부 상태를 먼저 확인합니다.

```bash
kubectl -n loki port-forward svc/loki-gateway 3100:80
```

그다음 같은 PC에서 `curl`로 먼저 응답을 확인합니다.

```bash
curl -I http://127.0.0.1:3100/ready
curl -s http://127.0.0.1:3100/ready
curl -G -s http://127.0.0.1:3100/loki/api/v1/labels
```

이 단계에서 확인할 항목:

- `/ready` 응답이 `200 OK`
- labels API가 JSON으로 반환됨
- 아직 로그 수집 에이전트를 붙이지 않았다면 label 결과가 비어 있을 수 있음

### 7. 브라우저 접속 검증

Synology Reverse Proxy 예시:

- Source: `https://loki.semtl.synology.me`
- Destination: `http://<INGRESS_EXTERNAL_IP>:80`

예:

- `kubectl -n ingress-nginx get svc ingress-nginx-controller` 결과가 `192.168.0.200`
- Synology Reverse Proxy 대상: `http://192.168.0.200:80`

참고:

- Loki도 Prometheus, Grafana와 같은 `ingress-nginx` 외부 IP를 함께 사용할 수 있습니다.
- 예를 들어 셋 다 `192.168.0.200`을 공유하고, host 기준으로 라우팅합니다.

검증 항목:

```bash
curl -I https://loki.semtl.synology.me/ready
curl -s https://loki.semtl.synology.me/ready
curl -G -s https://loki.semtl.synology.me/loki/api/v1/labels
```

### 8. Grafana 데이터소스 등록

Grafana에서 Loki를 수동으로 추가할 때 내부 URL은 아래 예시를 사용합니다.

- Name: `Loki`
- Type: `Loki`
- URL: `http://loki-gateway.loki.svc.cluster.local/`

검증:

- `Connections > Data sources`에서 `Loki` 추가
- `Save & test` 성공 확인

주의:

- Loki만 설치한 직후에는 아직 수집 에이전트가 없으므로 실제 로그는 없을 수 있습니다.
- 이 경우 데이터소스 연결은 정상이어도 Explore에서 조회 결과가 비어 있을 수 있습니다.

## 설치 직후 바로 사용하는 방법

### 1. Loki API 확인

```bash
curl -s http://127.0.0.1:3100/loki/api/v1/labels
```

### 2. Grafana 데이터소스 확인

- `Connections > Data sources`에서 `Loki`가 보이는지 확인
- `Save & test` 성공 확인

### 3. 로그가 안 보일 때의 기본 해석

- Loki 설치만 완료된 상태: 정상
- 로그 수집 agent 미설치: 조회 결과 비어 있을 수 있음
- 다음 단계: `Alloy` 또는 `Promtail` 설치 후 실제 로그 유입 확인

## 설치 검증

아래 검증을 모두 통과하면 기본 설치 완료로 판단합니다.

### 리소스 상태

```bash
kubectl -n loki get pods
kubectl -n loki get svc
kubectl -n loki get ingress
```

정상 기준:

- 주요 파드가 `Running`
- `loki-gateway` 서비스가 존재
- `loki` Ingress가 생성됨

### 서버 응답

```bash
kubectl -n loki logs deploy/loki --tail=100
kubectl -n loki logs deploy/loki-gateway --tail=100
```

확인 포인트:

- object storage 연결 오류가 반복되지 않음
- schema 관련 오류가 없음
- gateway upstream 오류가 과도하게 반복되지 않음

## 운영 메모

별도 운영 가이드를 두지 않는 대신, 설치 직후부터 아래 기준을 기본 운영 원칙으로 사용합니다.

### 일일/주간 확인 항목

- `kubectl -n loki get pods`로 재시작 여부 확인
- `kubectl -n loki logs deploy/loki --tail=100`로 최근 오류 확인
- MinIO bucket 사용량 증가 여부 확인
- Grafana Loki 데이터소스 `Save & test` 상태 확인

### 변경 관리 기준

- bucket, credentials, retention 변경 전에는 현재 values와 bucket 상태를 먼저 백업합니다.
- `schemaConfig` 변경은 운영 영향이 크므로 신중하게 다룹니다.
- Ingress 또는 도메인 변경 시에는 gateway 응답과 Grafana 데이터소스 연결을 함께 검증합니다.

## 재설치 전 완전 정리

Values를 크게 바꿨거나 처음부터 다시 설치하고 싶다면 아래 순서로 정리합니다.

### 1. Helm 릴리스 제거

```bash
helm uninstall loki -n loki
```

확인:

```bash
helm list -n loki
```

### 2. 네임스페이스 전체 삭제

```bash
kubectl delete namespace loki
```

확인:

```bash
kubectl get ns loki
```

정상 기준:

- `NotFound`가 나오면 삭제 완료

### 3. 주의

- Helm 릴리스를 삭제해도 MinIO bucket 안의 실제 로그 데이터는 남을 수 있습니다.
- 재설치 후 같은 bucket과 credentials를 쓰면 기존 object를 계속 참조할 수 있습니다.
- bucket 자체를 비우는 작업은 운영 데이터 보존 여부를 먼저 확인한 뒤 수행합니다.

## 초기 트러블슈팅

### 증상: `loki` 파드가 재시작을 반복함

확인 명령:

```bash
kubectl -n loki get pods
kubectl -n loki logs deploy/loki --tail=100
kubectl -n loki describe pod -l app.kubernetes.io/name=loki
```

주요 원인:

- MinIO credentials 오류
- bucket 미생성
- `schemaConfig` 또는 object storage 설정 오류

조치:

- bucket 이름과 credentials 값을 다시 확인합니다.
- MinIO endpoint 접근 가능 여부를 확인합니다.
- values의 `schemaConfig`와 `storage` 블록을 다시 점검합니다.

### 증상: Grafana에서는 연결되지만 로그가 비어 있음

이 경우는 Loki 자체 문제보다 로그 수집 agent 부재일 가능성이 큽니다.

확인 항목:

- Loki 데이터소스 `Save & test`
- Loki labels API 응답
- Alloy / Promtail 설치 여부

설명:

- Loki는 저장/조회 서버이고, 로그를 직접 수집하지 않습니다.
- 실제 로그 유입은 `Alloy` 또는 `Promtail`이 담당합니다.

## 참고

- Kubernetes 기본 설치: [`../rke2/installation.md`](../rke2/installation.md)
- MinIO 설치: [`../minio/installation.md`](../minio/installation.md)
- Monitoring 설치: [`../monitoring/installation.md`](../monitoring/installation.md)
- [Install Grafana Loki with Helm](https://grafana.com/docs/loki/latest/setup/install/helm/)
- [Install monolithic Loki](https://grafana.com/docs/loki/latest/setup/install/helm/install-monolithic/)
- [Loki Helm chart concepts](https://grafana.com/docs/loki/latest/setup/install/helm/concepts/)
- [Install Loki](https://grafana.com/docs/loki/latest/setup/install/)
