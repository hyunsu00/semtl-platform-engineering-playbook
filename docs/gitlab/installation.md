# Gitlab Installation

## 개요

이 문서는 VM 기반 GitLab Omnibus 설치 절차를 정의합니다.

## 사전 조건

- OS: Ubuntu 22.04 LTS
- VM 리소스: 최소 `4 vCPU / 12GB RAM`
- 도메인: `gitlab.semtl.synology.me`
- 외부 URL: `https://gitlab.semtl.synology.me`
- Synology Reverse Proxy 경유 노출

## 네트워크 기준

- `net0`: 외부 접근망 (`192.168.0.x`)
- `net1`: 내부 데이터망
- 예시 VM IP: `192.168.0.221`

## 설치 절차

### 1. 기본 패키지 설치

```bash
# 패키지 목록 갱신
sudo apt update

# 필수 도구 설치
sudo apt install -y curl ca-certificates tzdata openssh-server perl
```

### 2. GitLab 저장소 등록

```bash
# GitLab 패키지 저장소 스크립트 실행
REPO_SCRIPT_URL="https://packages.gitlab.com/install/repositories/"
REPO_SCRIPT_URL="${REPO_SCRIPT_URL}gitlab/gitlab-ee/script.deb.sh"
curl -fsSL "$REPO_SCRIPT_URL" | sudo bash
```

### 3. GitLab Omnibus 설치

```bash
# 외부 URL 지정 후 GitLab EE 설치
sudo EXTERNAL_URL="https://gitlab.semtl.synology.me" apt install -y gitlab-ee
```

### 4. Registry 비활성 정책 적용

```bash
# 설정 파일 편집
sudo editor /etc/gitlab/gitlab.rb
```

아래 항목 확인/추가:

```ruby
registry['enable'] = false
gitlab_rails['registry_enabled'] = false
```

적용:

```bash
# 설정 반영
sudo gitlab-ctl reconfigure

# 서비스 상태 확인
sudo gitlab-ctl status
```

## 방화벽/포트 체크

- VM 입력 포트: `22`, `80`, `443`
- Reverse Proxy 경유 시 외부는 `443`만 개방 가능

## 설치 검증

```bash
# GitLab 상태 확인
sudo gitlab-ctl status

# 헬스체크
curl -I https://gitlab.semtl.synology.me
```

검증 기준:

- GitLab 로그인 페이지 응답
- `gitlab-ctl status`에서 주요 서비스가 `run`

## 스냅샷 권장 시점

- 초기 관리자 로그인 확인 직후
- Runner/OIDC 연동 전

권장 이름:

- `BASE-GitLab-Install`

## 참고

- 컨테이너 이미지 저장소는 Harbor를 단일 사용
- GitLab Container Registry는 운영 정책상 비사용
