# Argocd Installation

## 개요

이 문서는 이 저장소의 Kubernetes 표준 환경에 `Argo CD`를 설치하고,
초기 관리자 계정 확인, `ingress-nginx` 노출, 기본 검증까지 수행하는 절차를 정리합니다.

이 문서의 기준은 다음과 같습니다.

- 대상 클러스터는 [`k8s 설치 문서`](../k8s/installation.md) 기준으로 이미 구축되어 있습니다.
- Ingress Controller는 `ingress-nginx`를 사용합니다.
- 외부 진입점은 `MetalLB`가 할당한 `ingress-nginx` 서비스 IP를 사용합니다.
- Argo CD는 `argocd` 네임스페이스에 설치합니다.
- 운영 기본값은 `HA manifest`를 사용합니다.

이 문서에서는 브라우저 접속과 운영 편의성을 위해
`ingress-nginx`에서 TLS를 종료하고, Argo CD 서버는 내부적으로
`insecure` 모드(HTTP)로 구동하는 방식을 기본값으로 사용합니다.

## 사전 조건

- Kubernetes 클러스터가 정상이며 `kubectl` 접근이 가능합니다.
- `MetalLB`와 `ingress-nginx`가 이미 설치되어 있습니다.
- 운영 도메인 예시: `argocd.semtl.synology.me`
- DNS가 `ingress-nginx` 외부 IP를 가리키도록 준비되어 있습니다.
- TLS 인증서 시크릿을 준비했거나, 초기 검증 단계에서는 `port-forward`로 접속합니다.

사전 확인 명령:

```bash
kubectl get nodes
kubectl -n ingress-nginx get pods
kubectl -n ingress-nginx get svc ingress-nginx-controller
```

정상 기준:

- 모든 노드가 `Ready`
- `ingress-nginx-controller` 파드가 `Running`
- `ingress-nginx-controller` 서비스의 `EXTERNAL-IP`가 할당됨

예시 확인:

```bash
kubectl -n ingress-nginx get svc ingress-nginx-controller
```

예상 출력 형태:

- `EXTERNAL-IP`: `192.168.0.201`

운영 기준 예시 DNS:

- `argocd.semtl.synology.me` -> `192.168.0.201`

## 배치 원칙

- 설치 네임스페이스: `argocd`
- 배포 방식: 공식 `HA manifest`
- 외부 노출: `Ingress`
- 내부 서비스 타입: `ClusterIP`
- 초기 관리자 계정: `admin`
- 초기 비밀번호: `argocd-initial-admin-secret`에서 1회 조회 후 즉시 변경

주의:

- 운영 환경에서는 `NodePort` 또는 `LoadBalancer`로 `argocd-server`를 직접 노출하지 않습니다.
- 브라우저 접속은 `Ingress` 기준으로 통일합니다.
- CLI 접속은 Ingress 경유 시 `--grpc-web` 옵션을 사용합니다.

## 설치 절차

### 1. 네임스페이스 생성

```bash
kubectl create namespace argocd
```

이미 존재하면 아래와 같이 확인만 수행합니다.

```bash
kubectl get ns argocd
```

### 2. Argo CD HA manifest 설치

공식 `HA manifest`를 적용합니다.

```bash
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/ha/install.yaml
```

설치 직후 주요 리소스 확인:

```bash
kubectl -n argocd get pods
kubectl -n argocd get svc
kubectl -n argocd get deployments,statefulsets
```

정상 기준:

- `argocd-server`
- `argocd-repo-server`
- `argocd-application-controller`
- `argocd-applicationset-controller`
- `argocd-dex-server`
- `argocd-redis*`

위 리소스가 생성되고, 잠시 후 `Running` 또는 `Ready` 상태로 수렴해야 합니다.

대기 예시:

```bash
kubectl -n argocd rollout status deploy/argocd-server --timeout=5m
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=5m
kubectl -n argocd rollout status deploy/argocd-applicationset-controller --timeout=5m
kubectl -n argocd rollout status deploy/argocd-dex-server --timeout=5m
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=5m
```

### 3. 초기 관리자 비밀번호 확인

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

### 4. 초기 접속 확인 (`port-forward`)

Ingress를 붙이기 전, 내부 상태를 먼저 확인합니다.

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

그다음 로컬 브라우저에서 아래 주소에 접속합니다.

- `https://127.0.0.1:8080`

자체 서명 인증서 경고는 초기 확인 단계에서 일시적으로 허용할 수 있습니다.

이 단계에서 확인할 항목:

- 로그인 가능 여부
- 대시보드 진입 가능 여부
- `Settings > Clusters`에서 in-cluster 연결 존재 여부

### 5. Ingress 종료형 운영 모드로 전환

이 저장소의 `k8s` 설치 문서는 기본 `ingress-nginx` 설치만 포함합니다.
이 기준에서는 별도 `ssl-passthrough` 설정 없이 운영할 수 있도록
Argo CD 서버를 `insecure` 모드로 전환합니다.

`argocd-cmd-params-cm` 패치:

```bash
kubectl -n argocd patch configmap argocd-cmd-params-cm \
  --type merge \
  -p '{"data":{"server.insecure":"true"}}'
```

서버 재시작:

```bash
kubectl -n argocd rollout restart deployment argocd-server
kubectl -n argocd rollout status deployment argocd-server --timeout=5m
```

적용 확인:

```bash
kubectl -n argocd get configmap argocd-cmd-params-cm -o yaml
```

정상 기준:

- `data.server.insecure: "true"` 확인

### 6. TLS 시크릿 준비

운영 도메인에 맞는 TLS 시크릿을 `argocd` 네임스페이스에 생성합니다.

예시:

```bash
kubectl -n argocd create secret tls argocd-server-tls \
  --cert=/path/to/tls.crt \
  --key=/path/to/tls.key
```

시크릿 확인:

```bash
kubectl -n argocd get secret argocd-server-tls
```

참고:

- 이미 wildcard 인증서를 보유하고 있다면 같은 방식으로 재사용할 수 있습니다.
- 외부 Reverse Proxy가 TLS를 종료한다면 아래 Ingress 예시에서 `tls:` 블록은 생략할 수 있습니다.

### 7. Ingress 생성

`docs/argocd/argocd-ingress.yaml` 같은 별도 파일로 관리해도 되지만,
초기 설치 시에는 아래 예시를 바로 적용해도 됩니다.

```bash
cat <<'EOF' | kubectl apply -f -
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
  tls:
    - hosts:
        - argocd.semtl.synology.me
      secretName: argocd-server-tls
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
```

적용 후 확인:

```bash
kubectl -n argocd get ingress
kubectl -n argocd describe ingress argocd-server
```

정상 기준:

- `HOSTS`에 `argocd.semtl.synology.me`
- `ADDRESS` 또는 이벤트에 `ingress-nginx` 연동 정보가 표시됨

### 8. 브라우저 접속 검증

DNS 반영 후 아래 주소로 접속합니다.

- `https://argocd.semtl.synology.me`

검증 항목:

- 로그인 페이지 응답
- `admin` 계정 로그인 성공
- 좌측 메뉴(`Applications`, `Settings`) 정상 노출
- `Settings > Clusters`에서 `in-cluster` 상태 정상

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

### 9. 초기 보안 조치

설치 직후 아래 항목을 바로 수행합니다.

1. `admin` 비밀번호 변경
2. 운영용 SSO 연동 전까지 관리자 계정 접근 주체 최소화
3. Git 저장소 등록 시 Personal Access Token 또는 Deploy Key 최소 권한 적용
4. `argocd` 네임스페이스 리소스 상태 스냅샷 저장

스냅샷 예시:

```bash
mkdir -p .local/scratch
kubectl -n argocd get all -o wide \
  > .local/scratch/2026-04-03-argocd-install-status-v1.txt
kubectl -n argocd get cm,secret,ingress \
  > .local/scratch/2026-04-03-argocd-install-config-v1.txt
```

주의:

- `.local/` 산출물은 참고용이며 Git에 커밋하지 않습니다.
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

### 서버 응답

```bash
kubectl -n argocd logs deploy/argocd-server --tail=100
```

확인 포인트:

- 반복 재시작 오류 없음
- 인증서/포트 충돌 오류 없음
- `insecure` 모드 전환 후 기동 실패 없음

### UI 및 API 접근

- 브라우저 로그인 성공
- `Applications` 화면 정상 진입
- CLI에서 `argocd cluster list` 결과 확인 가능

## 운영 메모

별도 운영 가이드를 두지 않는 대신, 설치 직후부터 아래 기준을 기본 운영 원칙으로 사용합니다.

### 일일/주간 확인 항목

- `kubectl -n argocd get pods`로 주요 파드 재시작 여부 확인
- `kubectl -n argocd top pod` 또는 메트릭 도구로 CPU/메모리 사용량 확인
- `kubectl -n argocd logs deploy/argocd-server --tail=100`로 최근 오류 확인
- 등록한 Git 저장소 인증정보와 토큰 만료 예정 여부 확인

### 변경 관리 기준

- Argo CD 업그레이드는 운영 시간 외에 수행하고, 적용 전 `kubectl -n argocd get all` 스냅샷을 남깁니다.
- Ingress, TLS, SSO 설정 변경 시에는 UI 로그인과 CLI 로그인 둘 다 재검증합니다.
- `argocd-cm`, `argocd-rbac-cm`, `argocd-cmd-params-cm` 변경 후에는 관련 파드 재기동 여부를 확인합니다.

### 백업 및 복구 메모

- 최소 백업 대상은 `argocd` 네임스페이스의 `ConfigMap`, `Secret`,
  `Application`, `AppProject`, `Ingress`입니다.
- 복구 전에는 Git 저장소 측 선언 상태와 실제 클러스터 상태가 일치하는지 먼저 확인합니다.
- GitOps로 재구성이 가능한 리소스와 수동 복구가 필요한 비밀정보를 구분해 관리합니다.

## 초기 트러블슈팅

별도 트러블슈팅 문서를 두지 않는 대신, 설치 직후 자주 만나는 이슈를 아래에 함께 정리합니다.

### 증상: `argocd-server`가 재시작을 반복함

확인 명령:

```bash
kubectl -n argocd get pods
kubectl -n argocd describe pod -l app.kubernetes.io/name=argocd-server
kubectl -n argocd logs deploy/argocd-server --tail=100
```

주요 원인:

- `argocd-cmd-params-cm` 설정 오타
- 포트/프로토콜 설정 불일치
- TLS 또는 Ingress 연동 방식 변경 후 설정 미반영

조치:

- `argocd-cmd-params-cm`의 `server.insecure` 값을 다시 확인합니다.
- `deployment/argocd-server`를 재시작하고 rollout 완료 여부를 확인합니다.
- 직전 변경이 의심되면 ConfigMap 패치를 되돌린 뒤 다시 적용합니다.

### 증상: 브라우저에서 UI 접속이 되지 않음

확인 명령:

```bash
kubectl -n argocd get ingress
kubectl -n argocd describe ingress argocd-server
kubectl -n ingress-nginx get svc ingress-nginx-controller
kubectl -n argocd get svc argocd-server
```

주요 원인:

- DNS가 `ingress-nginx` 외부 IP를 가리키지 않음
- TLS 시크릿 이름 또는 인증서 내용 불일치
- Ingress backend protocol이 현재 서버 설정과 맞지 않음
- 방화벽 또는 Reverse Proxy 경로 미개방

조치:

- 도메인 해석 결과와 `ingress-nginx-controller`의 `EXTERNAL-IP`를 대조합니다.
- `argocd-server-tls` 시크릿이 올바른 네임스페이스에 존재하는지 확인합니다.
- Ingress annotation이 `nginx.ingress.kubernetes.io/backend-protocol: "HTTP"`인지 확인합니다.
- 필요하면 `port-forward` 접속으로 서버 자체 정상 여부를 먼저 분리 진단합니다.

### 증상: CLI 로그인은 실패하지만 UI 로그인은 됨

확인 예시:

```bash
argocd login argocd.semtl.synology.me --username admin --grpc-web
```

주요 원인:

- Ingress 경유 환경에서 `grpc-web` 옵션 누락
- 자체 인증서 또는 중간 인증서 체인 문제

조치:

- `argocd login` 시 `--grpc-web`을 추가합니다.
- 사설 인증서 환경이면 CLI 실행 호스트의 신뢰 저장소를 점검합니다.

## 롤백 절차

설치를 되돌려야 하면 아래 순서로 정리합니다.

```bash
kubectl delete ingress -n argocd argocd-server
kubectl delete namespace argocd
```

확인:

```bash
kubectl get ns argocd
kubectl get ingress -A | grep argocd
```

주의:

- Argo CD에 등록한 Repository credential, Project, Application 리소스도 함께 삭제됩니다.
- 롤백 전에 GitOps 관리 대상으로 이미 연결한 리소스가 있는지 먼저 확인합니다.

## 참고

- Kubernetes 클러스터 기본 설치: [`../k8s/installation.md`](../k8s/installation.md)
- 공식 설치 문서: `https://argo-cd.readthedocs.io/`
- 공식 HA manifest: `https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/ha/install.yaml`
