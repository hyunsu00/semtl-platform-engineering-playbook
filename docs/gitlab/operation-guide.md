# Gitlab Operation Guide

## 개요

이 문서는 GitLab 18.8.4-ee 운영에서 Kubernetes Runner 연동과
Keycloak OIDC 연동 기준을 정의합니다.

## 운영 기준

- GitLab URL: `https://gitlab.semtl.synology.me`
- 컨테이너 이미지 Registry: Harbor 사용 (GitLab Registry 비활성)
- Runner 실행 위치: Kubernetes (`executor = kubernetes`)

## Runner 운영 절차

### 1. Runner 토큰 발급

권장 우선순위:

1. Group Runner (`devops` 그룹)
2. 불가 시 Instance Runner

그룹 경로:

- `devops` 그룹 -> `Settings` -> `CI/CD` -> `Runners`
- `New group runner` 선택

필수 설정:

- Description: `k8s-runner`
- Tags: `k8s`
- Run untagged jobs: 체크
- Locked to current project: 해제

### 2. Kubernetes Runner 설치 (Helm)

```bash
# Helm 저장소 추가 및 업데이트
helm repo add gitlab https://charts.gitlab.io
helm repo update

# values 파일로 runner 설치
helm install gitlab-runner gitlab/gitlab-runner \
  --namespace gitlab-runner \
  --create-namespace \
  -f values.yaml
```

`values.yaml` 핵심 예시:

```yaml
gitlabUrl: https://gitlab.semtl.synology.me
runnerRegistrationToken: "<glrt-token>"
runners:
  executor: kubernetes
  config: |
    [[runners]]
      [runners.kubernetes]
        namespace = "gitlab-runner"
        image = "ubuntu:22.04"
        privileged = true
```

### 3. Runner 상태 확인

```bash
# Runner 파드 상태 확인
kubectl -n gitlab-runner get pods

# GitLab UI에서 runner online 상태 확인
```

## Keycloak OIDC 연동 운영 기준

- Keycloak realm: `semtl` 사용 권장 (`master` 직접 사용 지양)
- GitLab OIDC callback:
  `https://gitlab.semtl.synology.me/users/auth/openid_connect/callback`
- 변경 후 `gitlab-ctl reconfigure` 필수

검증:

- GitLab 로그인 화면에 OIDC 로그인 버튼 노출
- Keycloak 로그인/콜백 후 GitLab 세션 생성

## 주간 점검

```bash
# GitLab 서비스 상태
sudo gitlab-ctl status

# 최근 에러 로그 확인
sudo gitlab-ctl tail | egrep -i 'error|exception|fail'

# Runner 파드 상태 점검
kubectl -n gitlab-runner get pods -o wide
```

## 운영 시 금지사항

- Runner 토큰을 문서/채팅에 평문 공유
- `privileged=true`를 필요성 검토 없이 상시 사용
- OIDC 콜백 URI 미일치 상태로 설정 반영
