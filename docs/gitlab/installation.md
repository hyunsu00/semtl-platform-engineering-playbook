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

#### 1.3 GitLab Omnibus 설치 (Reverse Proxy 환경)

```bash
# 초기 설치 실패 방지를 위해 최소 설정만 설치 시점에 임시 주입
OMNIBUS_CFG="letsencrypt['enable'] = false;"
OMNIBUS_CFG="${OMNIBUS_CFG} nginx['listen_port'] = 80;"
OMNIBUS_CFG="${OMNIBUS_CFG} nginx['listen_https'] = false;"
OMNIBUS_CFG="${OMNIBUS_CFG} registry['enable'] = false;"
OMNIBUS_CFG="${OMNIBUS_CFG} gitlab_rails['registry_enabled'] = false;"

# 외부 URL 지정 후 GitLab EE 설치
sudo EXTERNAL_URL="https://gitlab.semtl.synology.me" \
GITLAB_OMNIBUS_CONFIG="$OMNIBUS_CFG" \
apt install -y gitlab-ee
```

#### 1.4 정책 영구 반영 및 서비스 확인

`GITLAB_OMNIBUS_CONFIG`는 설치 시점에만 적용되므로,
운영 정책은 `/etc/gitlab/gitlab.rb`에 영구 반영합니다.

```bash
# 설정 파일 편집
sudo editor /etc/gitlab/gitlab.rb
```

아래 항목 확인/추가(주석 없이):

```ruby
letsencrypt['enable'] = false
nginx['listen_port'] = 80
nginx['listen_https'] = false
registry['enable'] = false
gitlab_rails['registry_enabled'] = false
gitlab_rails['trusted_proxies'] = ['192.168.0.0/24']
nginx['real_ip_trusted_addresses'] = ['192.168.0.0/24']
nginx['real_ip_header'] = 'X-Forwarded-For'
nginx['real_ip_recursive'] = 'on'
```

```bash
# 주석 제외 실제 설정 라인 확인
sudo grep -nE "^[^#].*letsencrypt\\['enable'\\]" /etc/gitlab/gitlab.rb
sudo grep -nE "^[^#].*nginx\\['listen_port'\\]" /etc/gitlab/gitlab.rb
sudo grep -nE "^[^#].*nginx\\['listen_https'\\]" /etc/gitlab/gitlab.rb
sudo grep -nE "^[^#].*registry\\['enable'\\]" /etc/gitlab/gitlab.rb
sudo grep -nE "^[^#].*registry_enabled" /etc/gitlab/gitlab.rb
sudo grep -nE "^[^#].*trusted_proxies" /etc/gitlab/gitlab.rb
sudo grep -nE "^[^#].*real_ip_trusted_addresses" /etc/gitlab/gitlab.rb
sudo grep -nE "^[^#].*real_ip_header" /etc/gitlab/gitlab.rb
sudo grep -nE "^[^#].*real_ip_recursive" /etc/gitlab/gitlab.rb

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

# GitLab 내부 상태 점검
sudo gitlab-rake gitlab:check

# 초기 root 비밀번호 확인(최초 1회)
sudo cat /etc/gitlab/initial_root_password
```

검증 기준:

- GitLab 로그인 페이지 응답
- `gitlab-ctl status`에서 주요 서비스가 `run`
- 초기 root 계정으로 로그인 가능

## 설치 실패 시 복구

아래 에러가 발생한 경우:

- `Validation failed, unable to request certificate`
- `dpkg returned an error code (1)`
- `ruby_block[wait for node-exporter service socket]` 단계에서 장시간 대기

다음 순서로 복구합니다.

```bash
# runit supervisor 상태 확인(node-exporter 대기 이슈 원인 점검)
sudo systemctl status gitlab-runsvdir

# gitlab-runsvdir가 failed면 재기동
sudo systemctl restart gitlab-runsvdir

# 설정 파일 편집
sudo editor /etc/gitlab/gitlab.rb

# 아래 항목 확인/추가
# letsencrypt['enable'] = false
# nginx['listen_port'] = 80
# nginx['listen_https'] = false
# registry['enable'] = false
# gitlab_rails['registry_enabled'] = false
# gitlab_rails['trusted_proxies'] = ['192.168.0.0/24']
# nginx['real_ip_trusted_addresses'] = ['192.168.0.0/24']
# nginx['real_ip_header'] = 'X-Forwarded-For'
# nginx['real_ip_recursive'] = 'on'

# dpkg 미완료 상태 복구
sudo dpkg --configure -a

# 설정 반영
sudo gitlab-ctl reconfigure
```

`gitlab-runsvdir`가 `failed` 상태면 runit 서비스(supervise)가 생성되지 않아
`node-exporter` 소켓 대기 단계에서 멈춘 것처럼 보일 수 있습니다.

### 2. 기본 설치 스냅샷

- 시점: `60GB` 기본 설치 + 초기 로그인 + Registry 비활성 적용 완료 후
- Proxmox: `Snapshots > Take Snapshot`
- 권장 이름: `BASE-GitLab-60G-Install-v1`

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
