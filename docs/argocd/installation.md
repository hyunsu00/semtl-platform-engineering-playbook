# Argocd Installation

## 개요

이 문서는 이 저장소의 Kubernetes 표준 환경에 `Argo CD`를
홈랩 기준 경량 구성으로 설치하는 절차를 정리합니다.

이 문서의 기준은 다음과 같습니다.

- 대상 클러스터는 [`RKE2 설치 문서`](../rke2/installation.md) 기준으로
  이미 구축되어 있습니다.
- Ingress Controller는 `ingress-nginx`를 사용합니다.
- 외부 TLS 종료는 현재 `Synology Reverse Proxy`에서 처리합니다.
- Argo CD는 `argocd` 네임스페이스에 설치합니다.
- 설치 방식은 공식 Helm chart를 사용합니다.

이 문서의 목표는 `HA`보다 단순함을 우선하는 것입니다.
홈랩에서는 Argo CD 자체를 고가용성으로 만드는 것보다,
재부팅 후 쉽게 복구되고 이해하기 쉬운 구성이 더 실용적입니다.

## 홈랩 최적 구성 원칙

현재 클러스터는 worker가 2대이고 control-plane에는 taint가 있으므로,
`HA manifest` 기본값을 그대로 쓰면 `redis-ha`, `repo-server`,
`applicationset-controller` 쪽에서 `Pending`이나 재기동 지연이 생기기 쉽습니다.

이 문서 기준 권장 구성:

- `argocd-server`: `1`
- `argocd-repo-server`: `1`
- `argocd-application-controller`: `1`
- `argocd-applicationset-controller`: `1`
- `argocd-notifications-controller`: `1`
- `argocd-dex-server`: `1`
- `redis`: 단일
- `redis-ha`: 비활성화

이 구성을 쓰는 이유:

- 재부팅 후 복구가 단순합니다.
- `anti-affinity`로 인한 `Pending` 가능성이 줄어듭니다.
- 홈랩에서도 자주 쓰는 기본 기능은 유지하면서 Redis HA만 걷어낼 수 있습니다.
- SSO, 알림, ApplicationSet을 포함해도 단일 Redis 구성이면 충분히 단순합니다.

## 사전 조건

- Kubernetes 클러스터가 정상이며 `kubectl` 접근이 가능합니다.
- `helm` CLI가 설치되어 있습니다.
- `MetalLB`와 `ingress-nginx`가 이미 설치되어 있습니다.
- 운영 도메인 예시: `argocd.semtl.synology.me`
- DNS가 `ingress-nginx` 외부 IP를 가리키도록 준비되어 있습니다.

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

- `argocd.semtl.synology.me` -> 현재 `ingress-nginx-controller`의 `EXTERNAL-IP`

예:

- `argocd.semtl.synology.me` -> `192.168.0.200`

## 배치 원칙

- 설치 네임스페이스: `argocd`
- 배포 방식: 공식 Helm chart
- 외부 노출: `Ingress`
- 내부 서비스 타입: `ClusterIP`
- 초기 관리자 계정: `admin`
- 초기 비밀번호: `argocd-initial-admin-secret`에서 1회 조회 후 즉시 변경

운영 메모:

- 브라우저 접속은 `Ingress` 기준으로 통일합니다.
- CLI 접속은 Ingress 경유 시 `--grpc-web` 옵션을 사용합니다.
- 외부 HTTPS는 `Synology Reverse Proxy`가 종료합니다.
- Argo CD 내부는 `server.insecure: true`로 HTTP 기준으로 동작시킵니다.
- 현재 구조에서는 `Argo CD`, `Prometheus`, `Grafana`, `Rancher`가 같은
  `ingress-nginx` 외부 IP를 공유할 수 있습니다.
- 서비스별 구분은 별도 IP가 아니라
  `argocd.semtl.synology.me` 같은 host 기준으로 처리합니다.

## 설치 절차

### 1. Helm 저장소 등록

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

확인:

```bash
helm search repo argo/argo-cd
```

### 2. 네임스페이스 생성

```bash
kubectl create namespace argocd
```

이미 존재하면 아래와 같이 확인만 수행합니다.

```bash
kubectl get ns argocd
```

### 3. 홈랩용 values 파일 작성

운영 기준 값을 `~/k8s/argocd/values-argocd-homelab.yaml`로 관리합니다.

```bash
mkdir -p ~/k8s/argocd

cat <<'EOF' > ~/k8s/argocd/values-argocd-homelab.yaml
global:
  domain: argocd.semtl.synology.me

configs:
  params:
    server.insecure: true

server:
  replicas: 1
  autoscaling:
    enabled: false
  service:
    type: ClusterIP
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

repoServer:
  replicas: 1
  autoscaling:
    enabled: false
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

controller:
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 1000m
      memory: 1Gi

applicationSet:
  replicaCount: 1

notifications:
  enabled: true

dex:
  enabled: true

redis:
  enabled: true

redis-ha:
  enabled: false
EOF
```

기본 구성 설명:

- `global.domain`은 실제 접속 도메인과 일치해야 합니다.
- `server.insecure: true`는 현재 구조처럼 외부 TLS 종료형 운영에 맞는 값입니다.
- `server`, `repoServer`, `controller`는 모두 `1` replica 기준으로 단순화합니다.
- `applicationSet`, `notifications`, `dex`는 홈랩 기본값으로 포함합니다.
- `redis`는 단일 인스턴스로 두고 `redis-ha`는 끕니다.
- 리소스 요청/제한을 함께 두어 Rancher 같은 UI에서 자원 표시가 더 명확해집니다.

### 4. Argo CD 설치

```bash
helm upgrade --install argocd argo/argo-cd \
  -n argocd \
  -f ~/k8s/argocd/values-argocd-homelab.yaml
```

설치 직후 확인:

```bash
helm list -n argocd
kubectl -n argocd get pods
kubectl -n argocd get svc
kubectl -n argocd get deployments,statefulsets
```

정상 기준:

- `helm list -n argocd`에 `argocd` 릴리스가 조회됨
- `argocd-server`, `argocd-repo-server`,
  `argocd-application-controller`, `argocd-applicationset-controller`,
  `argocd-notifications-controller`, `argocd-dex-server`,
  `argocd-redis`가 생성됨
- `redis-ha`는 비활성화 상태이므로 없어도 정상

### 5. 기동 대기

```bash
kubectl -n argocd rollout status deploy/argocd-server --timeout=5m
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=5m
kubectl -n argocd rollout status statefulset/argocd-application-controller \
  --timeout=5m
kubectl -n argocd rollout status deploy/argocd-redis --timeout=5m
```

정상 기준:

- 주요 파드가 `Running`
- `Pending` 파드가 남지 않음
- 재부팅 후에도 같은 리소스 수로 수렴함

### 6. 초기 관리자 비밀번호 확인

초기 `admin` 비밀번호는 자동 생성된 시크릿에서 확인합니다.

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

초기 접속 계정:

- Username: `admin`
- Password: 위 명령 결과

주의:

- 초기 비밀번호는 최초 로그인 후 즉시 변경합니다.
- 비밀번호를 별도 비밀관리 시스템에 안전하게 이관한 뒤,
  `argocd-initial-admin-secret` 삭제 여부는 운영 정책에 따라 결정합니다.

### 7. 초기 접속 확인 (`port-forward`)

Ingress를 붙이기 전, 내부 상태를 먼저 확인합니다.

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

그다음 같은 PC에서 `curl`로 먼저 응답을 확인합니다.

```bash
curl -I http://127.0.0.1:8080/
curl -s http://127.0.0.1:8080/ | head -n 20
```

이 단계에서 확인할 항목:

- Argo CD UI 응답이 내려오는지 확인
- 필요하면 이후 브라우저에서 로그인과 대시보드를 추가 확인

### 8. Ingress 생성

Ingress는 파일로 만들어 관리합니다.

```bash
cat <<'EOF' > ~/k8s/argocd/argocd-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
spec:
  ingressClassName: nginx
  rules:
    - host: argocd.semtl.synology.me
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
EOF

kubectl apply -f ~/k8s/argocd/argocd-ingress.yaml
```

현재 구조 기준 설명:

- Synology Reverse Proxy가 TLS를 종료하므로, 이 문서의 기본 경로에서는
  Kubernetes 내부 `argocd-server-tls` 시크릿이 필수가 아닙니다.
- 따라서 위 Ingress 예시는 `tls:` 블록 없이 `HTTP` backend 기준으로 사용합니다.
- Kubernetes 안에서 직접 TLS를 받는 구조로 바꿀 때만 `tls:` 블록과
  `argocd-server-tls` 시크릿을 추가합니다.

적용 후 확인:

```bash
kubectl -n argocd get ingress
kubectl -n argocd describe ingress argocd-server
```

정상 기준:

- `HOSTS`에 `argocd.semtl.synology.me`
- `describe ingress` 기준 `Address`에 현재 `ingress-nginx` 외부 IP가 표시됨
- backend가 `argocd-server:80`으로 연결됨

### 9. 브라우저와 CLI 접속 검증

DNS 반영 후 아래 주소로 접속합니다.

- `https://argocd.semtl.synology.me`

검증 항목:

- 로그인 페이지 응답
- `admin` 계정 로그인 성공
- 좌측 메뉴(`Applications`, `Settings`) 정상 노출
- `Settings > Clusters`에서 `in-cluster` 상태 확인

CLI도 함께 사용할 계획이면 `vm-admin` 같은 운영 노드에 설치합니다.

Ubuntu/Linux 예시:

```bash
VERSION=$(
  curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest \
  | grep '"tag_name"' \
  | cut -d '"' -f 4
)

curl -Lo argocd-linux-amd64 \
  "https://github.com/argoproj/argo-cd/releases/download/${VERSION}/argocd-linux-amd64"

sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

argocd version --client
```

CLI 검증 예시:

```bash
argocd login argocd.semtl.synology.me \
  --username admin \
  --password '<INITIAL_PASSWORD>' \
  --grpc-web
argocd cluster list
argocd app list
```

참고:

- Ingress에서 TLS를 종료하는 구성에서는 `argocd` CLI에 `--grpc-web`이 필요할 수 있습니다.
- CLI를 아직 설치하지 않았다면 브라우저 검증만 먼저 수행해도 됩니다.

### 10. 기존 설치를 당장 유지한 채 임시 경량화할 때

재설치 전 기존 설치를 최대한 유지하면서 단순화하려면 아래처럼 정리합니다.
이 문서 기준 임시 경량화는 `redis-ha`만 끄고 나머지 기본 컨트롤러는 유지합니다.

```bash
kubectl -n argocd scale deploy argocd-server --replicas=1
kubectl -n argocd scale deploy argocd-repo-server --replicas=1
kubectl -n argocd scale deploy argocd-applicationset-controller --replicas=1
kubectl -n argocd scale deploy argocd-notifications-controller --replicas=1
kubectl -n argocd scale deploy argocd-dex-server --replicas=1
kubectl -n argocd scale deploy argocd-redis-ha-haproxy --replicas=0
kubectl -n argocd scale statefulset argocd-redis-ha-server --replicas=0
```

이 방법은 임시 경량화에는 유용하지만, 장기적으로는 Helm values 기준으로
다시 맞추는 편이 더 깔끔합니다.

### 11. 초기 보안 조치

설치 직후 아래 항목을 바로 수행합니다.

1. `admin` 비밀번호 변경
2. 운영용 SSO 연동 전까지 관리자 계정 접근 주체 최소화
3. Git 저장소 등록 시 Personal Access Token 또는 Deploy Key 최소 권한 적용
4. `argocd` 네임스페이스 리소스 상태 스냅샷 저장

스냅샷 예시:

```bash
mkdir -p ~/k8s/argocd/snapshot
SNAPSHOT_DATE=$(date +%F)

kubectl -n argocd get pods -o wide \
  > ~/k8s/argocd/snapshot/${SNAPSHOT_DATE}-argocd-pods.txt
kubectl -n argocd get ingress \
  > ~/k8s/argocd/snapshot/${SNAPSHOT_DATE}-argocd-ingress.txt
kubectl -n argocd get cm,secret \
  > ~/k8s/argocd/snapshot/${SNAPSHOT_DATE}-argocd-config.txt
kubectl -n argocd get deployments,statefulsets \
  > ~/k8s/argocd/snapshot/${SNAPSHOT_DATE}-argocd-workloads.txt
```

주의:

- 스냅샷 파일은 `~/k8s/argocd/snapshot/` 아래에 보관하는 것을 권장합니다.
- `Secret` 전체 YAML을 평문으로 보관할 때는 접근권한을 별도로 통제합니다.

## 설치 검증

아래 검증을 모두 통과하면 기본 설치 완료로 판단합니다.

### 리소스 상태

```bash
kubectl -n argocd get pods
kubectl -n argocd get svc
kubectl -n argocd get ingress
```

정상 기준:

- 주요 파드가 모두 `Running`
- `argocd-server` 서비스가 존재
- `argocd-server` Ingress가 생성됨
- `argocd-server`, `argocd-repo-server`, `argocd-application-controller`,
  `argocd-applicationset-controller`, `argocd-dex-server`,
  `argocd-notifications-controller`, `argocd-redis`에 `Pending` 파드가 남지 않음
- `argocd-redis-ha-*`가 없어도 정상

### 서버 응답

```bash
kubectl -n argocd logs deploy/argocd-server --tail=100
```

확인 포인트:

- 반복 재시작 오류 없음
- 인증서/포트 충돌 오류 없음
- `insecure` 모드 전환 후 기동 실패 없음
- `argocd-server` rollout이 `Pending` 없이 완료됨

### UI 및 API 접근

- 브라우저 로그인 성공
- `Applications` 화면 정상 진입
- CLI에서 `argocd cluster list` 결과 확인 가능

## 운영 메모

별도 운영 가이드를 두지 않는 대신, 설치 직후부터 아래 기준을
기본 운영 원칙으로 사용합니다.

### 일일/주간 확인 항목

- `kubectl -n argocd get pods`로 주요 파드 재시작 여부 확인
- `kubectl -n argocd top pod` 또는 메트릭 도구로 CPU/메모리 사용량 확인
- `kubectl -n argocd logs deploy/argocd-server --tail=100`로 최근 오류 확인
- 등록한 Git 저장소 인증정보와 토큰 만료 예정 여부 확인

### 변경 관리 기준

- Argo CD 업그레이드는 운영 시간 외에 수행하고,
  적용 전 `kubectl -n argocd get all` 스냅샷을 남깁니다.
- Ingress, TLS, SSO 설정 변경 시에는 UI 로그인과 CLI 로그인 둘 다 재검증합니다.
- `argocd-cm`, `argocd-rbac-cm`, `argocd-cmd-params-cm` 변경 후에는
  관련 파드 재기동 여부를 확인합니다.
- 홈랩 기준 기본값은 주요 컨트롤러를 포함하되 `redis-ha`만
  비활성화하는 구성입니다.

### 백업 및 복구 메모

- 최소 백업 대상은 `argocd` 네임스페이스의 `ConfigMap`, `Secret`,
  `Application`, `AppProject`, `Ingress`입니다.
- 복구 전에는 Git 저장소 측 선언 상태와 실제 클러스터 상태가
  일치하는지 먼저 확인합니다.
- GitOps로 재구성이 가능한 리소스와 수동 복구가 필요한 비밀정보를
  구분해 관리합니다.

## 롤백 절차

이 문서는 Helm chart 기준 설치이므로, 롤백도 Helm 기준으로 수행합니다.

설치를 되돌려야 하면 아래 순서로 정리합니다.

```bash
helm uninstall argocd -n argocd
kubectl get all -n argocd
kubectl delete namespace argocd --ignore-not-found
kubectl wait --for=delete ns/argocd --timeout=5m || true
```

설명:

- `helm uninstall`이 우선입니다.
- Ingress, Service, Deployment, StatefulSet 같은 Helm 관리 리소스는
  `helm uninstall`로 함께 정리됩니다.
- `kubectl delete namespace argocd`는 남은 리소스까지 깨끗하게 비우려는
  후속 정리 단계입니다.
- `kubectl get all -n argocd`는 namespace 삭제 전에 잔여 리소스를
  한 번 더 확인하려는 용도입니다.

확인:

```bash
kubectl get ns argocd
kubectl get ingress -A | grep argocd
```

주의:

- Argo CD에 등록한 Repository credential, Project, Application 리소스도 함께 삭제됩니다.
- 롤백 전에 GitOps 관리 대상으로 이미 연결한 리소스가 있는지 먼저 확인합니다.

## 참고

- Kubernetes 클러스터 기본 설치: [`../rke2/installation.md`](../rke2/installation.md)
- 공식 문서: `https://argo-cd.readthedocs.io/`
- Helm chart 저장소: `https://argoproj.github.io/argo-helm`
