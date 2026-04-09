# cert-manager Installation (작업중)

## 개요

이 문서는 이 저장소의 Kubernetes 표준 환경에 `cert-manager`를 설치하는 절차와,
현재 구조에서 왜 아직 필수는 아닌지를 함께 정리합니다.

이 문서의 기준은 다음과 같습니다.

- 대상 클러스터는 [`RKE2 설치 문서`](../rke2/installation.md) 기준으로 이미 구축되어 있습니다.
- Ingress Controller는 `ingress-nginx`를 사용합니다.
- 현재 외부 HTTPS 종단은 Kubernetes가 아니라 `Synology Reverse Proxy`에서 처리합니다.
- `Prometheus`, `Grafana`, `Argo CD` 같은 앱은 같은 `ingress-nginx` 외부 IP를 host 기반으로 공유합니다.

이 문서의 목적은 다음과 같습니다.

- `cert-manager`가 언제 필요한지 판단 기준 제공
- 필요할 때 한 번에 설치할 수 있는 성공 경로 제공
- 현재 구조에서는 왜 아직 선택 사항인지 명확히 설명

## 지금 당장 필수가 아닌 이유

현재 이 저장소의 기본 구조에서는 `cert-manager`가 꼭 필요하지 않습니다.

이유:

- 외부 TLS 종료를 `Synology Reverse Proxy`가 이미 담당합니다.
- Kubernetes 안의 `Ingress`는 현재 `HTTP`로만 받고 있습니다.
- 따라서 `Ingress`마다 `tls.secretName`과 인증서 발급/갱신을
  Kubernetes 내부에서 자동화하지 않아도 운영이 가능합니다.

현재 구조 예시:

- 사용자: `https://prometheus.semtl.synology.me`
- TLS 종료: Synology Reverse Proxy
- 내부 전달: `http://<INGRESS_EXTERNAL_IP>:80`
- Kubernetes 내부: `ingress-nginx`가 host 기준으로 앱 라우팅

즉 지금은:

- `cert-manager` 없이도 HTTPS 접속 가능
- 인증서 갱신은 Synology 쪽에서 관리
- Kubernetes 쪽은 애플리케이션 라우팅에 집중

## 언제 도입하는 게 좋은가

아래 조건 중 하나라도 생기면 `cert-manager` 도입 가치가 커집니다.

- `ingress-nginx`가 직접 HTTPS를 받아야 할 때
- 앱 수가 많아져 인증서 수동 관리가 번거로워질 때
- `Ingress` 단위로 인증서를 자동 발급/갱신하고 싶을 때
- `ClusterIssuer`와 `Certificate` 기준으로 인증서 상태를 Kubernetes 안에서 관리하고 싶을 때
- 이후 `Gateway API`, mTLS, 내부 서비스 인증서까지 확장하고 싶을 때

운영적으로 보면:

- 지금: 선택 사항
- 향후 `Synology Reverse Proxy` 의존을 줄이고 싶을 때: 권장

## 사전 조건

- Kubernetes 클러스터가 정상이며 `kubectl` 접근이 가능합니다.
- `helm` CLI가 설치되어 있습니다.
- `ingress-nginx`가 이미 설치되어 있습니다.

사전 확인 명령:

```bash
kubectl get nodes
kubectl -n ingress-nginx get pods
helm version
```

정상 기준:

- 모든 노드가 `Ready`
- `ingress-nginx-controller` 파드가 `Running`
- `helm version`이 정상 응답

공식 기준 참고:

- `cert-manager`는 반드시 클러스터에 한 번만 설치해야 합니다.
- Helm chart를 다른 chart의 sub-chart로 포함하면 안 됩니다.
- 대표 사용 사례는 `Ingress`에 대한 TLS 인증서 자동 발급/갱신입니다.

## 설치 절차

### 1. Helm 저장소 등록

```bash
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo update
```

확인:

```bash
helm search repo jetstack/cert-manager
```

### 2. 네임스페이스 생성

```bash
kubectl create namespace cert-manager
```

이미 존재하면 확인만 수행합니다.

```bash
kubectl get ns cert-manager
```

### 3. cert-manager 설치

이 문서 기준 권장 경로는 Helm으로 설치하면서 CRD도 함께 설치하는 방식입니다.

```bash
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set crds.enabled=true
```

설치 직후 확인:

```bash
helm list -n cert-manager
kubectl -n cert-manager get pods
kubectl get crd | grep cert-manager.io
```

정상 기준:

- `helm list -n cert-manager`에 `cert-manager` 릴리스가 조회됨
- `cert-manager`, `cert-manager-cainjector`, `cert-manager-webhook` 파드가 `Running`
- `certificates.cert-manager.io`, `issuers.cert-manager.io`,
  `clusterissuers.cert-manager.io` 같은 CRD가 생성됨

### 4. 기초 동작 확인

```bash
kubectl -n cert-manager get deployment
kubectl -n cert-manager logs deploy/cert-manager --tail=100
```

확인 포인트:

- webhook 초기화 오류가 반복되지 않음
- leader election 오류가 반복되지 않음
- CRD 미존재 오류가 없음

## 현재 구조에서의 운영 기준

현재 구조에서는 `cert-manager`를 설치하더라도 바로 `Issuer`나 `Certificate`를
적용하지 않아도 됩니다.

운영 기준:

- 현재 HTTPS는 계속 `Synology Reverse Proxy`가 처리
- `cert-manager`는 나중에 Kubernetes 직접 TLS 종료로 전환할 때 사용
- 당장 `Prometheus`, `Grafana`, `Argo CD` 문서의 Ingress에 `tls:` 블록을
  추가하지 않습니다

즉 이 문서는:

- 지금 당장 필수 설치 문서라기보다
- 이후 Kubernetes 내부 TLS 자동화로 넘어갈 때 참고할 기준 문서입니다

## 향후 적용 예시

나중에 Kubernetes가 직접 TLS를 받도록 바꿀 때는 보통 아래 흐름으로 확장합니다.

1. `ClusterIssuer` 생성
2. `Ingress`에 cert-manager annotation 추가
3. `tls.secretName` 지정
4. `Certificate` 생성 확인

공식 문서 기준으로는 `Ingress` annotation을 붙이면 `ingress-shim`이
`Certificate` 리소스를 자동으로 맞춰줍니다.

## 설치 검증

아래 검증을 모두 통과하면 기본 설치 완료로 판단합니다.

```bash
kubectl -n cert-manager get pods
kubectl get crd | grep cert-manager.io
```

정상 기준:

- 주요 파드가 `Running`
- 주요 CRD가 생성됨

## 재설치 전 완전 정리

처음부터 다시 설치하고 싶다면 아래 순서로 정리합니다.

### 1. Helm 릴리스 제거

```bash
helm uninstall cert-manager -n cert-manager
```

확인:

```bash
helm list -n cert-manager
```

### 2. 네임스페이스 삭제

```bash
kubectl delete namespace cert-manager
```

확인:

```bash
kubectl get ns cert-manager
```

주의:

- CRD까지 완전히 지울지는 신중하게 판단합니다.
- 이미 `Certificate`, `Issuer`, `ClusterIssuer`를 쓰기 시작했다면
  CRD 삭제는 운영 리소스 전체에 영향을 줄 수 있습니다.

## 초기 트러블슈팅

### 증상: webhook 관련 오류로 설치가 멈춤

확인 명령:

```bash
kubectl -n cert-manager get pods
kubectl -n cert-manager logs deploy/cert-manager-webhook --tail=100
kubectl -n cert-manager describe pod -l app.kubernetes.io/component=webhook
```

주요 원인:

- webhook 기동 지연
- CRD 설치 누락
- API 서버와 webhook 간 통신 문제

조치:

- 설치 직후 몇 분 더 대기한 뒤 상태를 다시 확인합니다.
- `kubectl get crd | grep cert-manager.io` 결과를 먼저 확인합니다.
- webhook 파드가 `Running`인지 확인합니다.

### 증상: 설치는 됐지만 아직 쓸 일이 없음

이 경우는 이상이 아니라 현재 구조상 정상입니다.

설명:

- 지금은 `Synology Reverse Proxy`가 TLS를 종료합니다.
- 따라서 `cert-manager`는 아직 “즉시 필요한 필수 컴포넌트”가 아니라
  “향후 Kubernetes 내부 TLS 자동화용 준비 컴포넌트”에 가깝습니다.

## 참고

- Kubernetes 기본 설치: [`../rke2/installation.md`](../rke2/installation.md)
- Prometheus 설치: [`../prometheus/installation.md`](../prometheus/installation.md)
- Grafana 설치: [`../grafana/installation.md`](../grafana/installation.md)
- Argo CD 설치: [`../argocd/installation.md`](../argocd/installation.md)
- [cert-manager Installation](https://cert-manager.io/docs/installation/)
- [cert-manager Helm Install](https://cert-manager.io/docs/installation/helm/)
- [cert-manager Ingress Usage](https://cert-manager.io/docs/usage/ingress/)
