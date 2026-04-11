# Rancher Installation

## 개요

이 문서는 이 저장소의 Kubernetes 표준 환경에 `Rancher`를 설치하고,
현재 구조에 맞는 외부 TLS 종료 방식까지 포함해 초기 접속 검증을 수행하는 절차를 정리합니다.

이 문서의 기준은 다음과 같습니다.

- 대상 클러스터는 [`RKE2 설치 문서`](../rke2/installation.md) 기준으로 이미 구축되어 있습니다.
- Ingress Controller는 RKE2 기본 포함 `ingress-nginx`를 사용합니다.
- 외부 TLS 종료는 현재 `Synology Reverse Proxy`에서 처리합니다.
- `Rancher`는 `cattle-system` 네임스페이스에 설치합니다.
- 설치 방식은 공식 Helm chart를 사용합니다.

이 문서의 목표는 실패 사례를 배제하고, 최소 설정으로 한 번에 설치가 끝나는
성공 경로를 제공하는 것입니다.

현재 구조 기준 핵심 판단:

- 현재 구성에서는 `cert-manager` 없이 설치 가능합니다.
- 이유는 Rancher Helm chart 옵션에서 `tls=external`을 사용하면
  외부 로드밸런서/Reverse Proxy가 TLS를 종료하는 구성이 가능하기 때문입니다.
- Rancher 공식 설치 문서도 외부 TLS 종료를 사용할 때는
  `cert-manager` 설치 단계를 건너뛰도록 안내합니다.

## Rancher를 어디에 쓰는가

Rancher는 Kubernetes 관리 UI입니다.

대표 사용처:

- 클러스터 상태 확인
- 네임스페이스, 워크로드, 서비스, Ingress 확인
- Helm chart 설치
- YAML 붙여넣기 배포
- 프로젝트/권한/RBAC 관리
- 여러 클러스터 통합 관리

운영 기준:

- 앱 배포 표준은 `Argo CD` 같은 GitOps 도구에 두고
- Rancher는 운영/관리 UI로 사용하는 조합이 자연스럽습니다.

## 사전 조건

- Kubernetes 클러스터가 정상이며 `kubectl` 접근이 가능합니다.
- `helm` CLI가 설치되어 있습니다.
- RKE2 기본 `ingress-nginx`가 정상 기동 중이어야 합니다.
- 외부 TLS 종료를 사용할 경우 `ingress-nginx`에
  `use-forwarded-headers: "true"`가 적용되어 있어야 합니다.
- 운영 도메인 예시: `rancher.semtl.synology.me`
- Rancher를 붙이기 전에 `ingress-nginx`의 실제 노출 방식이 확인되어 있어야 합니다.
- DNS는 위에서 확인한 ingress 진입 주소를 가리키도록 준비되어 있어야 합니다.
- Synology Reverse Proxy에서 TLS를 종료할 수 있어야 합니다.

사전 확인 명령:

```bash
kubectl get nodes
kubectl -n kube-system get pods | grep ingress-nginx
kubectl -n kube-system get svc | grep ingress-nginx
helm version
```

정상 기준:

- 모든 노드가 `Ready`
- `rke2-ingress-nginx` 관련 파드가 `Running`
- ingress 진입에 사용할 서비스 또는 노드 주소가 확인됨
- `helm version`이 정상 응답

공식 기준 참고:

- Rancher Helm chart 옵션에는 `hostname`, `bootstrapPassword`, `tls` 등이 있습니다.
- `tls=external`은 외부 TLS 종료를 뜻합니다.
- 외부 TLS 종료를 사용할 때는 `Host`, `X-Forwarded-Proto`, `X-Forwarded-Port`,
  `X-Forwarded-For` 헤더가 필요합니다.
- RKE2에서는 `use-forwarded-headers: "true"`가 없으면
  external TLS 구성에서 redirect loop가 발생할 수 있습니다.
- Rancher 설치 전에는 사용하려는 Kubernetes 버전이 support matrix에 포함되는지 확인해야 합니다.

## 배치 원칙

- 설치 네임스페이스: `cattle-system`
- 배포 방식: 공식 Helm chart
- 외부 노출: `Ingress`
- 내부 서비스 타입: `ClusterIP`
- TLS 종료: `Synology Reverse Proxy`
- Rancher Ingress는 HTTP 기준으로 받고, 외부 HTTPS는 Reverse Proxy가 담당합니다.

운영 메모:

- 현재 구조에서는 `Rancher`, `Prometheus`, `Grafana`, `Argo CD`가 같은
  ingress 진입 주소를 공유할 수 있습니다.
- 서비스별 구분은 별도 IP가 아니라 `rancher.semtl.synology.me` 같은 host 기준으로 처리합니다.
- `MetalLB`가 없으면 별도 `LoadBalancer` IP 대신
  `ingress-nginx`가 떠 있는 `Ready` 노드 IP를 진입점으로 사용합니다.
- 클러스터 안에서 Rancher는 상태 저장 애플리케이션이 아니므로 별도 PVC를 사용하지 않습니다.

## 설치 절차

### 1. Helm 저장소 등록

```bash
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo update
```

확인:

```bash
helm search repo rancher-latest/rancher
```

### 2. 네임스페이스 생성

```bash
kubectl create namespace cattle-system
```

이미 존재하면 아래와 같이 확인만 수행합니다.

```bash
kubectl get ns cattle-system
```

### 3. RKE2 `ingress-nginx` forwarded header 설정 확인

외부 TLS 종료에서는 RKE2 기본 `ingress-nginx`가
proxy header를 신뢰하도록 먼저 맞춰 두는 편이 안전합니다.

먼저 설정 파일 존재 여부를 확인합니다.

```bash
kubectl -n kube-system get helmchartconfig rke2-ingress-nginx
```

없다면 아래 manifest를 적용합니다.

```bash
mkdir -p ~/rke2/rancher

cat <<'EOF' > ~/rke2/rancher/rke2-ingress-nginx-config.yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-ingress-nginx
  namespace: kube-system
spec:
  valuesContent: |-
    controller:
      config:
        use-forwarded-headers: "true"
EOF

kubectl apply -f ~/rke2/rancher/rke2-ingress-nginx-config.yaml
kubectl -n kube-system rollout status ds/rke2-ingress-nginx-controller --timeout=10m
```

주의:

- 이 설정 적용 시 `rke2-ingress-nginx-controller` DaemonSet 롤링 업데이트가 발생할 수 있습니다.
- Proxmox 호스트 네트워크가 불안정한 환경이라면 운영자가 즉시 관찰 가능한 시간에 적용하는 편이 안전합니다.
- 가능하면 Proxmox SSH 또는 AMT 콘솔을 열어 둔 상태에서 진행하고,
  적용 직후 `192.168.0.1`, `192.168.0.2` ping 상태를 함께 확인합니다.

확인:

```bash
kubectl -n kube-system get helmchartconfig rke2-ingress-nginx -o yaml
```

정상 기준:

- `use-forwarded-headers: "true"`가 포함됨

### 4. Values 파일 작성

운영 기준 값을 `~/rke2/rancher/values-rancher.yaml`로 관리합니다.

```bash
mkdir -p ~/rke2/rancher

cat <<'EOF' > ~/rke2/rancher/values-rancher.yaml
hostname: rancher.semtl.synology.me
bootstrapPassword: "Fvkuas4fUUCvoA5Y"

replicas: 1

tls: external

ingress:
  enabled: true
  ingressClassName: nginx
  extraAnnotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"

antiAffinity: preferred

resources:
  requests:
    cpu: 200m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1536Mi
EOF
```

기본 구성 설명:

- `hostname`은 실제 접속 도메인과 일치해야 합니다.
- `bootstrapPassword`를 미리 지정해 최초 로그인 비밀번호를 고정합니다.
- `bootstrapPassword`는 12자 이상 영문/숫자 조합을 권장합니다.
- `bootstrapPassword`에는 `#`, `?`, `&` 같은 URL 특수문자를 가능한 한 피합니다.
- 이유는 최초 `setup` URL에 비밀번호를 붙여 진입할 때 특수문자 인코딩 문제를 만들 수 있기 때문입니다.
- 현재 클러스터 기준 기본값은 `replicas: 1`입니다.
- worker 2대 환경에서는 먼저 `1`로 안정화한 뒤, 필요할 때만 `2` 이상으로 늘리는 편이 단순합니다.
- `tls: external`로 현재 구조처럼 Synology Reverse Proxy가 TLS를 종료하도록 맞춥니다.
- `ingressClassName: nginx`로 Rancher Ingress가 `ingress-nginx`를 명확히 사용하도록 맞춥니다.
- `nginx.ingress.kubernetes.io/ssl-redirect: "false"`로
  Ingress 단계의 강제 HTTPS 리다이렉트를 끕니다.
- 현재 구조에서는 외부 HTTPS를 Synology Reverse Proxy가 종료하므로 이 설정이 더 단순합니다.
- `resources.requests`와 `resources.limits`를 함께 두어 Rancher 파드의 자원 사용 기준을 명확히 잡습니다.
- 이 문서 기준으로 `cert-manager`는 사용하지 않습니다.

비밀번호 생성 예시:

```bash
openssl rand -base64 24 | tr -d '=+/' | cut -c1-16
```

### 5. Rancher 설치

```bash
helm upgrade --install rancher rancher-latest/rancher \
  --namespace cattle-system \
  -f ~/rke2/rancher/values-rancher.yaml
```

설치 직후 확인:

```bash
helm list -n cattle-system
kubectl -n cattle-system get pods
kubectl -n cattle-system get svc
kubectl -n cattle-system get ingress
```

정상 기준:

- `helm list -n cattle-system`에 `rancher` 릴리스가 조회됨
- `rancher` 관련 파드가 생성됨
- `rancher` 서비스와 Ingress가 생성됨
- `kubectl -n cattle-system get ingress` 기준 `CLASS`가 `nginx`

### 6. 기동 대기

```bash
kubectl -n cattle-system rollout status deploy/rancher --timeout=10m
kubectl -n cattle-system get pods -o wide
```

정상 기준:

- `rancher` Deployment rollout 완료
- 주요 파드가 `Running`

### 7. 내부 서비스 확인

```bash
kubectl -n cattle-system get svc
kubectl -n cattle-system get ingress
```

참고:

- 이 문서 기준으로 `Service`는 내부용 `ClusterIP`가 정상입니다.
- 외부 노출 여부는 `Service`가 아니라 `Ingress`의 `ADDRESS` 기준으로 확인합니다.

### 8. 초기 접속 확인 (`port-forward`)

Ingress를 붙이기 전, 내부 상태를 먼저 확인합니다.

```bash
kubectl -n cattle-system port-forward svc/rancher 8080:80
```

그다음 같은 PC에서 `curl`로 먼저 응답을 확인합니다.

```bash
curl -I http://127.0.0.1:8080/healthz
curl -s http://127.0.0.1:8080/healthz
```

이 단계에서 확인할 항목:

- `/healthz` 응답이 `200 OK`
- 필요하면 이후 브라우저에서 UI를 추가 확인

### 9. 브라우저 접속 검증

운영 기준 예시 DNS:

- `rancher.semtl.synology.me` -> 현재 ingress 진입 주소

예시 확인:

```bash
kubectl -n kube-system get svc | grep ingress-nginx
kubectl -n kube-system get ds rke2-ingress-nginx-controller -o wide
```

현재 환경처럼 `MetalLB`가 없고 `LoadBalancer` 서비스도 없다면,
`rke2-ingress-nginx-controller`가 떠 있는 `Ready` 노드 IP 중 하나를
ingress 진입 주소로 사용합니다.

예:

- `vm-rke2-cp1` -> `192.168.0.181`
- `vm-rke2-w1` -> `192.168.0.191`
- `vm-rke2-w2` -> `192.168.0.192`
- `vm-rke2-w3` -> `192.168.0.193`

예를 들어 Synology Reverse Proxy 대상을 `vm-rke2-cp1`로 정했다면 DNS는 아래처럼 맞춥니다.

- `rancher.semtl.synology.me` -> `192.168.0.181`

Synology Reverse Proxy 예시:

- Source: `https://rancher.semtl.synology.me`
- Destination: `http://<INGRESS_NODE_IP>:80`

예:

- Reverse Proxy 대상 노드를 `vm-rke2-cp1`로 선택
- Synology Reverse Proxy 대상: `http://192.168.0.181:80`

참고:

- 환경에 따라 `rke2-ingress-nginx-controller` 서비스가 없을 수 있습니다.
- 이 경우에는 `rke2-ingress-nginx-controller`가 떠 있는 `Ready` 노드 IP를
  Synology Reverse Proxy 대상으로 맞추면 됩니다.
- 노드를 바꾸면 Reverse Proxy 대상도 함께 갱신해야 합니다.
- 노드가 `NotReady`이면 ingress 파드가 떠 있어도 Rancher 설치 전 클러스터 상태를 먼저 정상화하는 편이 안전합니다.

주의:

- Reverse Proxy는 `Host`, `X-Forwarded-Proto`, `X-Forwarded-Port`
  헤더를 전달해야 합니다.
- Rancher 공식 문서도 외부 TLS 종료 시 이 헤더들을 요구합니다.
- `X-Forwarded-For`는 필요할 수 있지만, Synology 화면에 고정 문자열로 직접 넣지 않습니다.
- 보통 Reverse Proxy가 원래 접속한 클라이언트 IP를 자동 전달합니다.

Synology Reverse Proxy 사용자 지정 헤더 예시:

- `Host: rancher.semtl.synology.me`
- `X-Forwarded-Proto: https`
- `X-Forwarded-Port: 443`
- ~~`X-Forwarded-For: <client-ip>`~~

설명:

- `X-Forwarded-For`는 Rancher에 접속한 사용자 브라우저 또는 운영 PC의 실제 IP를 담는 헤더입니다.
- 보통 Reverse Proxy가 자동으로 채워 주며, `<client-ip>` 같은 placeholder 문자열을 직접 넣는 값이 아닙니다.
- 따라서 Synology 사용자 지정 헤더 화면에서는
  `Host`, `X-Forwarded-Proto`, `X-Forwarded-Port`만 수동으로 넣고,
  `X-Forwarded-For`는 자동 전달을 사용합니다.
- 추가로 RKE2 `ingress-nginx` 쪽에도 `use-forwarded-headers=true`가 설정되어 있어야 합니다.
- 이 문서의 3단계에서 같은 설정을 먼저 적용합니다.

검증 항목:

```bash
curl -k -I https://rancher.semtl.synology.me/healthz
curl -k -s https://rancher.semtl.synology.me/healthz
curl -k -I https://rancher.semtl.synology.me/
curl -k -L -I https://rancher.semtl.synology.me/
curl -k -s https://rancher.semtl.synology.me/dashboard/ | head -n 20
```

성공 케이스 기준 기대 응답:

- `/healthz`는 `200 OK`
- `/`는 `200`이며 JSON 응답 헤더가 보일 수 있음
- `/dashboard/`는 Rancher HTML이 내려옴

### 10. 최초 로그인

초기 접속 계정:

- Username: `admin`
- Password: `values-rancher.yaml`에 넣은 `bootstrapPassword`

주의:

- 너무 짧은 비밀번호는 초기 로그인 단계에서 거부될 수 있으므로
  `12자 이상`으로 잡는 편이 안전합니다.
- 이후 관리자 화면에서 비밀번호를 바꾸더라도, 현재 적용된
  Rancher 비밀번호 정책보다 짧으면 거부될 수 있습니다.

최초 setup URL 예시:

```bash
echo "https://rancher.semtl.synology.me/dashboard/?setup=$(
  kubectl get secret --namespace cattle-system bootstrap-secret \
    -o go-template='{{.data.bootstrapPassword|base64decode}}'
)"
```

최초 로그인 후 확인할 항목:

- 서버 URL이 `rancher.semtl.synology.me`로 보이는지 확인
- `local` 클러스터가 정상 등록되어 있는지 확인
- 기본 관리자 비밀번호 변경

## 설치 직후 바로 사용하는 방법

Rancher 설치 직후 아래 정도를 먼저 확인하면 충분합니다.

### 1. local 클러스터 상태 확인

- `Cluster Management`에서 `local` 클러스터가 `Active`인지 확인

### 2. 간단한 UI 작업 확인

- `Workloads` 화면 접근
- `Namespaces` 화면 접근
- `Apps > Charts` 또는 `Cluster Tools` 메뉴 접근

### 3. 배포 관점 이해

- UI에서 YAML 붙여넣기나 Helm chart 배포가 가능
- 장기 운영 기준 앱 배포 표준은 `Argo CD` 같은 GitOps 도구를 우선 권장

## 설치 검증

아래 검증을 모두 통과하면 기본 설치 완료로 판단합니다.

### 리소스 상태

```bash
kubectl -n cattle-system get pods
kubectl -n cattle-system get svc
kubectl -n cattle-system get ingress
```

정상 기준:

- 주요 파드가 `Running`
- `rancher` 서비스가 존재
- `rancher` Ingress가 생성됨

### 서버 응답

```bash
kubectl -n cattle-system logs deploy/rancher --tail=100
```

확인 포인트:

- 반복 재시작 오류 없음
- ingress host 또는 TLS 관련 경고가 과도하게 반복되지 않음
- `local` cluster import 오류가 반복되지 않음

### `API Aggregation not ready` 대응

`/dashboard/`가 `API Aggregation not ready`로 멈추면
`server-url` 값을 먼저 확인합니다.

```bash
kubectl -n cattle-system get settings.management.cattle.io server-url -o yaml
```

정상 기준:

- `value: https://rancher.semtl.synology.me`

비어 있으면 아래 patch 후 Rancher를 재시작합니다.

```bash
kubectl patch settings.management.cattle.io server-url \
  --type merge \
  -p '{"value":"https://rancher.semtl.synology.me"}'
kubectl -n cattle-system rollout restart deploy/rancher
kubectl -n cattle-system rollout status deploy/rancher --timeout=10m
```

## 운영 메모

별도 운영 가이드를 두지 않는 대신, 설치 직후부터 아래 기준을 기본 운영 원칙으로 사용합니다.

### 일일/주간 확인 항목

- `kubectl -n cattle-system get pods`로 재시작 여부 확인
- `kubectl -n cattle-system logs deploy/rancher --tail=100`로 최근 오류 확인
- `local` 클러스터 상태 확인
- 관리자 계정, API 토큰, 프로젝트/권한 변경 여부 확인

### 변경 관리 기준

- Helm values 변경 전에는 현재 값을 백업하고 변경 후 `helm get values` 결과를 남깁니다.
- hostname, TLS, ingress 변경 시에는 로그인과 링크 생성 동작을 함께 검증합니다.
- 이후 `cert-manager` 기반 TLS로 바꿀 경우에는 현재 external TLS 설정과 분리해서 검증합니다.

values 변경 재반영 예시:

```bash
helm upgrade --install rancher rancher-latest/rancher \
  --namespace cattle-system \
  -f ~/rke2/rancher/values-rancher.yaml
```

확인:

```bash
helm list -n cattle-system
kubectl -n cattle-system get pods
kubectl -n cattle-system rollout status deploy/rancher --timeout=10m
helm get values rancher -n cattle-system
```

## Rancher 설치 완료 후 스냅샷 생성

`rke2-storage-clean-v2` 이후 `Rancher`까지 설치하고 기본 검증이 끝났으면
Proxmox에서 각 `RKE2` VM의 세 번째 기준점을 남깁니다.

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
- `kubectl -n cattle-system get pods -o wide` 기준 Rancher 주요 파드가 `Running`
- `kubectl get storageclass` 기준 `longhorn (default)`와 `nfs-client`가 모두 존재
- `kubectl -n cattle-system get ingress` 기준 Rancher Ingress가 생성됨
- `curl -k -I https://rancher.semtl.synology.me/healthz`가 정상 응답

확인 예시:

```bash
kubectl get nodes
kubectl get pods -A
kubectl -n longhorn-system get pods -o wide
kubectl -n nfs-provisioner get pods -o wide
kubectl -n cattle-system get pods -o wide
kubectl get storageclass
kubectl -n cattle-system get ingress
curl -k -I https://rancher.semtl.synology.me/healthz
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

- `Name`: `rke2-rancher-clean-v3`
- 설명은 노드 역할이 드러나도록 VM별로 다르게 기록합니다.

VM별 권장 설명:

- `vm-rke2-cp1`:
  `[rancher]`
  `- rke2 : v1.34.6+rke2r1`
  `- role : control-plane`
  `- hostname : vm-rke2-cp1`
  `- node ip : 192.168.0.181`
  `- longhorn : installed`
  `- nfs storageclass : installed`
  `- rancher : installed`
  `- status : kubectl get nodes 기준 Ready`
- `vm-rke2-w1`:
  `[rancher]`
  `- rke2 : v1.34.6+rke2r1`
  `- role : worker-1`
  `- hostname : vm-rke2-w1`
  `- node ip : 192.168.0.191`
  `- longhorn replica target : enabled`
  `- nfs client : ready`
  `- ingress target : available`
  `- status : kubectl get nodes 기준 Ready`
- `vm-rke2-w2`:
  `[rancher]`
  `- rke2 : v1.34.6+rke2r1`
  `- role : worker-2`
  `- hostname : vm-rke2-w2`
  `- node ip : 192.168.0.192`
  `- longhorn replica target : enabled`
  `- nfs client : ready`
  `- ingress target : available`
  `- status : kubectl get nodes 기준 Ready`
- `vm-rke2-w3`:
  `[rancher]`
  `- rke2 : v1.34.6+rke2r1`
  `- role : worker-3`
  `- hostname : vm-rke2-w3`
  `- node ip : 192.168.0.193`
  `- longhorn replica target : enabled`
  `- nfs client : ready`
  `- ingress target : available`
  `- status : kubectl get nodes 기준 Ready`

운영 메모:

- 이 스냅샷은 `rke2-storage-clean-v2` 이후 `Rancher`까지 완료된 기준점으로 사용합니다.
- 스냅샷 이름은 4대 VM 모두 동일하게 `rke2-rancher-clean-v3`로 맞추는 것을 권장합니다.
- 이후 `Prometheus`, `Grafana`, `Argo CD` 같은 상위 서비스 설치 전 기준점으로 두기 좋습니다.
- 실제 운영 데이터가 본격적으로 쌓이기 시작하면 스냅샷보다는 백업 정책을 우선합니다.

## 재설치 전 완전 정리

Values를 크게 바꿨거나 처음부터 다시 설치하고 싶다면 아래 순서로 정리합니다.

### 1. Helm 릴리스 제거

```bash
helm uninstall rancher -n cattle-system
```

확인:

```bash
helm list -n cattle-system
```

### 2. 네임스페이스 전체 삭제

```bash
kubectl delete namespace cattle-system
kubectl wait --for=delete ns/cattle-system --timeout=5m
```

확인:

```bash
kubectl get ns cattle-system
```

정상 기준:

- `NotFound`가 나오면 삭제 완료

### 3. 잔여 리소스 확인

```bash
kubectl get ingress -A | grep rancher
```

정상 기준:

- 다른 네임스페이스에 `rancher` Ingress가 남아 있지 않음

## 참고

- Kubernetes 기본 설치: [`../rke2/installation.md`](../rke2/installation.md)
- Argo CD 설치: [`../argocd/installation.md`](../argocd/installation.md)
- cert-manager 설치: [`../cert-manager/installation.md`](../cert-manager/installation.md)
- [Rancher Helm Chart Options](https://ranchermanager.docs.rancher.com/getting-started/installation-and-upgrade/installation-references/helm-chart-options)
- [Choosing a Rancher Version](https://ranchermanager.docs.rancher.com/getting-started/installation-and-upgrade/resources/choose-a-rancher-version)
- [Installation Requirements](https://ranchermanager.docs.rancher.com/v2.13/getting-started/installation-and-upgrade/installation-requirements)
