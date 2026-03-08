# GitLab Installation

## 개요

이 문서는 VM 기반 GitLab Omnibus 설치 절차를 정의합니다.

## 사전 조건

- OS: Ubuntu 22.04 LTS
- VM 리소스: 최소 `4 vCPU / 12GB RAM`
- 디스크: OS `60GB` (기본 설치)
- 권장 디스크: 운영 환경은 `100GB+` 권장
- 도메인: `gitlab.semtl.synology.me`
- 외부 URL: `https://gitlab.semtl.synology.me`
- Synology Reverse Proxy 경유 노출

### Proxmox VM H/W 참고 이미지

아래 이미지는 Proxmox `Hardware` 탭 기준의 GitLab VM 구성 예시입니다.

![Proxmox VM Hardware - GitLab](../assets/images/gitlab/proxmox-vm-hw-gitlab-v1.png)

캡션: `4 vCPU`, `12GB RAM`, OS Disk `60GB`

## 네트워크 기준

- `net0` 단일 NIC 사용 (`192.168.0.x`)
- 예시 VM IP: `192.168.0.172`

## 설치 절차

### 1. 60GB 기본 설치

#### 1.1 기본 패키지 설치

```bash
# 패키지 목록 갱신
sudo apt update

# 필수 도구 설치
sudo apt install -y curl ca-certificates tzdata openssh-server perl
```

#### 1.2 GitLab 저장소 등록

```bash
# GitLab 패키지 저장소 스크립트 실행
REPO_SCRIPT_URL="https://packages.gitlab.com/install/repositories/"
REPO_SCRIPT_URL="${REPO_SCRIPT_URL}gitlab/gitlab-ee/script.deb.sh"
curl -fsSL "$REPO_SCRIPT_URL" | sudo bash
```

#### 1.3 GitLab Omnibus 기본 설치 (로컬 HTTP)

```bash
# 초기 설치는 로컬 HTTP 엔드포인트로 진행
sudo EXTERNAL_URL="http://192.168.0.172" \
apt install -y gitlab-ee=18.8.4-ee.0
```

#### 1.4 설치 후 Reverse Proxy 정책 반영 및 서비스 확인

기본 설치 완료 후 `/etc/gitlab/gitlab.rb`에 Reverse Proxy 운영 정책을 반영합니다.

```bash
# 기존 파일 백업(UTC 타임스탬프)
sudo cp /etc/gitlab/gitlab.rb /etc/gitlab/gitlab.rb.bak.$(date -u +%Y%m%d%H%M%S)

# 기존 관리 블록이 있으면 제거(멱등 적용)
sudo awk '
  BEGIN {skip=0}
  /^# BEGIN semtl reverse-proxy policy$/ {skip=1; next}
  /^# END semtl reverse-proxy policy$/ {skip=0; next}
  skip==0 {print}
' /etc/gitlab/gitlab.rb | sudo tee /etc/gitlab/gitlab.rb >/dev/null

# 운영 정책 블록 추가
sudo tee -a /etc/gitlab/gitlab.rb >/dev/null <<'EOF'
# BEGIN semtl reverse-proxy policy
external_url 'https://gitlab.semtl.synology.me'
letsencrypt['enable'] = false
nginx['listen_port'] = 80
nginx['listen_https'] = false
registry['enable'] = false
gitlab_rails['registry_enabled'] = false
gitlab_rails['trusted_proxies'] = ['192.168.0.0/24']
nginx['real_ip_trusted_addresses'] = ['192.168.0.0/24']
nginx['real_ip_header'] = 'X-Forwarded-For'
nginx['real_ip_recursive'] = 'on'
# END semtl reverse-proxy policy
EOF
```

```bash
# 관리 블록 적용 여부 확인
sudo sed -n '/# BEGIN semtl reverse-proxy policy/,/# END semtl reverse-proxy policy/p' /etc/gitlab/gitlab.rb

# 핵심 키워드 확인(주석 포함)
sudo grep -nE "external_url|letsencrypt|listen_port|listen_https|registry_enabled|trusted_proxies|real_ip_" /etc/gitlab/gitlab.rb

# 설정 반영
sudo gitlab-ctl reconfigure

# 서비스 상태 확인
sudo gitlab-ctl status
```

## 방화벽/포트 체크

- GitLab VM 입력 포트(내부망): `22`, `80`
- GitLab VM `443`은 기본 비활성 (`nginx['listen_https'] = false`)
- Synology Reverse Proxy 입력 포트(외부/내부 공통): `443`
- Reverse Proxy 경유 시 사용자 접속 URL은 `https://gitlab.semtl.synology.me`만 사용

직접 IP 접속 동작 참고:

- `http://192.168.0.172`로 접속해도 `external_url` 정책에 따라 HTTPS 경로로 리다이렉트될 수 있음
- `https://192.168.0.172` 직접 접속은 인증서/SAN 불일치 또는 VM 443 비활성으로 실패 가능
- 운영 검증은 반드시 도메인 URL(`https://gitlab.semtl.synology.me`) 기준으로 수행

## 설치 검증

```bash
# GitLab 상태 확인
sudo gitlab-ctl status

# 헬스체크
curl -I https://gitlab.semtl.synology.me

# GitLab 내부 상태 점검
sudo gitlab-rake gitlab:check

# 설치 버전 확인
sudo gitlab-rake gitlab:env:info | sed -n '1,120p'

# (선택) 초기 root 비밀번호 확인(파일이 남아있는 경우에만)
sudo cat /etc/gitlab/initial_root_password
```

## 초기 관리자 비밀번호 변경/재설정

초기 로그인 후 `root` 비밀번호는 즉시 변경합니다.

`/etc/gitlab/initial_root_password`가 비어 있거나 파일이 제거된 경우에도
아래 명령으로 `root` 비밀번호를 재설정할 수 있습니다.

```bash
# (선택) 비밀번호 길이 정책 키 확인
sudo gitlab-rails runner "s=ApplicationSetting.current; p s.attributes.keys.grep(/password|length/)"

# (선택) 최소 비밀번호 길이 변경(예: 8)
sudo gitlab-rails runner "s=ApplicationSetting.current; s.update!(minimum_password_length: 8); puts s.minimum_password_length"

# root 비밀번호 재설정(새 비밀번호 2회 입력)
sudo gitlab-rake "gitlab:password:reset[root]"
```

보안 운영 권장:

- 초기 비밀번호는 평문으로 보관하지 않음
- 비밀번호 변경 후 `/etc/gitlab/initial_root_password` 파일은 삭제 여부 확인

검증 기준:

- GitLab 로그인 페이지 응답
- `gitlab-ctl status`에서 주요 서비스가 `run`
- root 계정 로그인 또는 비밀번호 재설정 가능

### 2. 기본 설치 스냅샷

스냅샷 생성 전 아래 정리 작업을 먼저 수행합니다.

```bash
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*
sudo apt autoremove -y
sudo apt clean
sudo journalctl --vacuum-time=1s
cat /dev/null > ~/.bash_history && history -c
```

- 시점: `60GB` 기본 설치 + Reverse Proxy 정책 반영 + `reconfigure`/로그인 검증 완료 후
- Proxmox에서 GitLab VM 선택
- `Snapshots > Take Snapshot` 실행
- 권장 이름: `gitlab-install-clean-v1`
- 설명 예시:
  ```text
  [설치]
  - gitlab-ee : 18.8.4
  - external_url : https://gitlab.semtl.synology.me
  - reverse proxy : synology(443) -> gitlab vm(80)
  - letsencrypt : disabled
  - registry : disabled
  - id : root
  - pw : 패스워드(설치 시 지정값)
  ```
- `Include RAM`은 비활성화(권장)

설치 후 연동 작업은 별도 문서에서 진행합니다.

- [GitLab MinIO 연동](./minio-integration.md)
- [GitLab Harbor 연동](./harbor-integration.md)

## 운영 정책

- 컨테이너 이미지 저장소는 Harbor를 단일 사용
- GitLab Container Registry는 운영 정책상 비사용

### 정책 배경

- GitLab Container Registry 비사용 이유
  - Registry를 Harbor로 단일화해 운영 지점을 줄이고 권한/취약점/백업 정책을 한 곳에서 관리
  - GitLab과 Harbor에 중복 저장되는 이미지/스토리지 비용 방지
  - CI 파이프라인의 이미지 push 대상을 일관되게 유지
- MinIO 사용 이유
  - GitLab Object Storage(artifacts, uploads, lfs 등)를 OS 로컬 디스크가 아닌 외부 스토리지로 분리
  - GitLab VM 용량(기본 `60GB`)을 코드/메타데이터 중심으로 유지하고 대용량 파일은 MinIO로 오프로드
  - 백업/복구 시 GitLab 앱과 대용량 오브젝트를 분리해 운영 유연성 확보
