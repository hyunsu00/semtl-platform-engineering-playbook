# CT Devtools Installation

## 개요

이 문서는 Proxmox에서 `ct-devtools` 컨테이너를 만들고,
운영 계정, SSH, Docker, 기본 관리 도구 스택까지 실제로 동작한 기준으로
따라갈 수 있게 정리한 문서입니다.

이 문서의 목표는 아래 상태까지 한 번에 만드는 것입니다.

- CT 이름: `ct-devtools`
- CT ID 예시: `131`
- 운영 계정: `semtl`
- 접속 방식: `semtl` 계정 + `sudo`
- Docker 운영 경로: `~/docker/devtools`
- 기본 관리 도구: `Homepage`, `Uptime Kuma`, `Dozzle`, `Watchtower`
- 외부 관리 UI: 별도 Portainer 서버 사용

이 문서는 실사용 중 최종적으로 성공한 흐름만 남기고,
중간 시행착오는 제외합니다.

## 사용 시점

- 홈랩 운영용 공통 관리 CT가 필요한 경우
- VM보다 가벼운 관리 노드를 만들고 싶은 경우
- Docker 기반 관리 도구를 한 CT에 모아 운영하려는 경우
- `root` 직접 SSH 대신 일반 사용자 + `sudo` 기준으로 정리하려는 경우

## 최종 성공 기준

이 문서 기준 최종 성공 상태는 아래와 같습니다.

- Proxmox에서 Ubuntu 22.04 기반 CT 생성 완료
- CT `Features`에 `nesting=1`, `keyctl=1` 적용 완료
- Windows 또는 다른 관리 PC에서 `ssh semtl@<CT-IP>` 접속 가능
- `sudo whoami` 결과가 `root`
- Docker 서비스 기동 및 `docker ps` 정상 동작
- `docker compose up -d`로 관리 도구 스택 기동 완료

예시 운영값:

- CT ID: `131`
- hostname: `ct-devtools`
- IP: `192.168.0.163`

## 사전 조건

- Proxmox 설치 및 기본 네트워크 구성 완료
- `vmbr0` 브리지 사용 가능
- Ubuntu 22.04 LXC 템플릿 다운로드 가능
- CT용 스토리지 확보

## 1. CT 생성

Proxmox Web UI에서 Ubuntu 22.04 LXC 템플릿으로 CT를 생성합니다.

권장 기준:

- CT ID: `113`
- Hostname: `ct-devtools`
- Template: `ubuntu-22.04-standard`
- Unprivileged CT: 사용
- Password: 임시 root 비밀번호 지정
- Bridge: `vmbr0`
- IPv4: `DHCP`
- IPv6: `None`
- Firewall: 활성화

권장 리소스:

- vCPU: `2`
- RAM: `4GB`
- Swap: `1GB`
- Root Disk: `32GB` 이상

운영 메모:

- 홈랩 관리 도구만 올릴 목적이라면 VM보다 CT가 가볍고 관리가 쉽습니다.
- 네트워크는 먼저 `DHCP`로 검증한 뒤 필요 시 고정 IP로 바꾸는 편이 안전합니다.
- `RAM 4GB`는 CT가 부팅 직후 항상 `4GB`를 즉시 점유한다는 의미가 아니라,
  사용할 수 있는 최대 메모리 한도를 의미합니다.
- Docker 엔진 자체 메모리 요구량은 크지 않지만, `Homepage`, `Uptime Kuma`,
  `Dozzle`, `Watchtower` 같은 관리 도구를 함께 올릴 계획이면
  `4GB`가 `2GB`보다 훨씬 여유롭습니다.
- `2GB RAM + 512MB Swap`으로도 설치와 가벼운 실습은 가능하지만,
  이후 컨테이너 수가 늘어날 가능성을 생각하면 처음부터 `4GB + 1GB Swap`
  구성을 권장합니다.
- Swap은 RAM이 부족할 때 디스크 일부를 임시 메모리처럼 사용하는 공간입니다.
  메모리 부족 시 즉시 장애가 나는 것을 완화하는 데 도움은 되지만,
  디스크 기반이라 RAM보다 훨씬 느리므로 보조 용도로만 봅니다.

## 2. CT Features 설정

Docker를 CT 안에서 안정적으로 사용하려면 아래 옵션을 먼저 켭니다.

Web UI:

1. CT 선택
1. `Options`
1. `Features`
1. `nesting` 활성화
1. `keyctl` 활성화

확인 기준:

```bash
pct config 131
```

기대 결과 예시:

```bash
features: nesting=1,keyctl=1
```

## 3. root 대신 운영 계정 사용

Ubuntu LXC 템플릿에서는 `root` SSH 로그인이 바로 되지 않거나,
비밀번호 인증이 실패하는 경우가 있습니다.

이 문서 기준 운영 방식은 `root` 직접 SSH가 아니라
일반 사용자 `semtl` + `sudo`입니다.

Proxmox 노드에서 CT 내부로 들어갑니다.

```bash
pct enter 131
```

운영 계정을 생성합니다.

```bash
adduser semtl
usermod -aG sudo semtl
groups semtl
```

기대 결과:

- `groups semtl` 출력에 `sudo` 포함

## 4. SSH 접속 확인

먼저 `openssh-server`가 없으면 설치합니다.

```bash
apt update
apt install -y openssh-server sudo ca-certificates curl git
systemctl enable --now ssh
```

다른 PC에서 접속을 확인합니다.

```bash
ssh semtl@192.168.0.163
```

로그인 후 `sudo` 권한을 확인합니다.

```bash
sudo whoami
```

기대 결과:

- `root`

## 5. SSH 보안 기본값 정리

운영 계정 접속이 확인되면 `root` SSH 로그인은 막는 편이 안전합니다.

```bash
sudo vi /etc/ssh/sshd_config
```

아래 값을 확인하거나 수정합니다.

```text
PermitRootLogin no
PasswordAuthentication yes
```

적용:

```bash
sudo systemctl restart ssh
```

운영 메모:

- SSH 공개키 로그인으로 바꿀 계획이 있으면 이후 `PasswordAuthentication no`
  전환을 검토합니다.
- 이 문서 기준 최종 성공 케이스는 비밀번호 기반 `semtl` 로그인까지 확인한 상태입니다.

## 6. 시간/locale 점검

Docker 설치 전에는 시간과 locale을 먼저 확인합니다.

시간 확인:

```bash
timedatectl
```

이 문서에서 확인된 정상 예시는 아래와 같습니다.

```text
Local time: Fri 2026-03-13 18:14:54 UTC
Time zone: Etc/UTC (UTC, +0000)
System clock synchronized: yes
NTP service: inactive
```

운영 메모:

- LXC 환경에서는 `NTP service: inactive`로 보여도
  `System clock synchronized: yes`이면 먼저 진행해도 됩니다.
- 시간이 어긋나면 `apt`, TLS, Docker image pull에서 문제가 날 수 있습니다.

locale 확인:

```bash
locale
```

권장 기준:

- `LANG=en_US.UTF-8` 또는 `LANG=C.UTF-8`

만약 아래처럼 `LANG=C`로 보이면 UTF-8 locale로 바꾸는 것을 권장합니다.

```text
LANG=C
LC_ALL=
```

변경 절차:

```bash
sudo apt update
sudo apt install -y locales
sudo locale-gen en_US.UTF-8
sudo update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
```

적용 후에는 다시 로그인하거나 새 셸을 열고 확인합니다.

```bash
locale
```

기대 결과 예시:

```text
LANG=en_US.UTF-8
LC_ALL=en_US.UTF-8
```

## 7. 기본 패키지 설치

운영용 기본 도구를 먼저 정리합니다.

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y \
  curl \
  wget \
  git \
  vim \
  htop \
  net-tools \
  ca-certificates \
  gnupg \
  lsb-release
```

## 8. Docker 설치

이 문서 기준으로는 Ubuntu 기본 패키지보다
Docker 공식 사이트의 Ubuntu 설치 절차를 따르는 구성을 사용합니다.

```bash
# 기존 비공식/충돌 패키지 제거
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  sudo apt remove -y "$pkg"
done

# Docker 공식 저장소 등록
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker "$USER"
```

적용 후에는 현재 로그인한 운영 계정으로 다시 로그인합니다.

검증:

```bash
sudo docker run hello-world
docker version
docker ps
```

운영 메모:

- `docker` 그룹 반영 전에는 재로그인이 필요합니다.
- 공식 저장소 기준 설치이므로 `docker compose` 플러그인을 사용합니다.
- 설치 기준 원문은 Docker 공식 문서의 Ubuntu 설치 가이드를 따릅니다.

## 9. Docker 설치 직후 정리 후 스냅샷

Docker 설치와 `docker ps` 확인까지 끝났으면,
관리 도구 스택을 올리기 전에 Proxmox에서 기준 스냅샷을 먼저 남기는 것을 권장합니다.

이 단계의 목적은 아래와 같습니다.

- Docker 엔진까지 정상 동작하는 최소 기준점 보존
- 이후 `Homepage`, `Uptime Kuma`, `Dozzle` 구성 실패 시 빠른 롤백
- 설치 직후 찌꺼기를 정리한 깨끗한 상태 유지

스냅샷은 반드시 불필요 파일 정리 후 생성합니다.

### 9-1. 불필요 파일 정리

```bash
# /tmp 전체 삭제
sudo rm -rf /tmp/*

# /var/tmp 전체 삭제
sudo rm -rf /var/tmp/*

# 미사용 패키지 정리
sudo apt autoremove -y

# APT 캐시 정리
sudo apt clean

# journal 로그 정리
sudo journalctl --vacuum-time=1s

# 사용자 bash 히스토리 비우기
cat /dev/null > ~/.bash_history && history -c
```

운영 메모:

- 이 문서에서는 템플릿 변환이 아니라 운영 CT 기준 스냅샷을 남깁니다.
- Docker image나 볼륨 데이터가 아직 크지 않은 초기 상태에서 남기는 것이 가장 효율적입니다.

### 9-2. Proxmox 스냅샷 생성

권장 시점:

- `semtl` 계정 SSH 접속 확인 완료
- `sudo whoami` 확인 완료
- Docker 공식 저장소 기반 설치 완료
- `docker version`, `docker ps`, `hello-world` 검증 완료
- 아직 관리 도구 스택은 올리기 전

Proxmox Web UI 절차:

1. `ct-devtools` CT 선택
1. `스냅샷`
1. `스냅샷 생성`
1. 이름과 설명 입력 후 생성

권장 이름:

- `ct-devtools-docker-clean-v1`

권장 설명 예시:

```text
[설치]
- semtl / <change-required>
- hostname / hostname -f 수정 (/etc/hosts)
  `127.0.1.1 devtools.internal.semtl.synology.me ct-devtools`
- ct-devtools 초기 CT 생성 완료
- semtl 계정 및 sudo 설정 완료
- SSH 접속 확인 완료
- locale UTF-8 설정 완료
- Docker 공식 저장소 기반 설치 완료
- docker hello-world / docker ps 검증 완료
- 관리 도구 스택 설치 전 베이스라인
```

운영 메모:

- 이후 `docker-compose.yml` 작성 전에도 설정이 크게 바뀐다면 별도 사전 스냅샷을 한 번 더 남기는 편이 안전합니다.
- 장기 운영 중 스냅샷을 오래 유지하면 스토리지 사용량이 커질 수 있으므로 기준점 스냅샷만 남기고 정리 정책을 같이 가져가야 합니다.

## 10. 작업 디렉터리 준비

운영 기준 디렉터리를 먼저 만듭니다.

```bash
mkdir -p ~/docker/devtools
cd ~/docker/devtools
mkdir -p homepage/config
mkdir -p uptime-kuma
```

예상 구조:

```text
~/docker/devtools/
├── docker-compose.yml
├── homepage/
│   └── config/
└── uptime-kuma/
```

## 11. Devtools 스택 작성

아래 `docker-compose.yml`을 기준으로 관리 도구를 한 번에 올립니다.

```yaml
services:
  homepage:
    image: ghcr.io/gethomepage/homepage:latest
    container_name: homepage
    ports:
      - "192.168.0.163:3000:3000"
    volumes:
      - ./homepage/config:/app/config
      - /var/run/docker.sock:/var/run/docker.sock:ro
    restart: unless-stopped

  uptime-kuma:
    image: louislam/uptime-kuma:latest
    container_name: uptime-kuma
    ports:
      - "192.168.0.163:3001:3001"
    volumes:
      - ./uptime-kuma:/app/data
    restart: unless-stopped

  dozzle:
    image: amir20/dozzle:latest
    container_name: dozzle
    ports:
      - "192.168.0.163:3002:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped

  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --cleanup --interval 300
    restart: unless-stopped
```

운영 메모:

- `Homepage`는 대시보드
- `Uptime Kuma`는 모니터링
- `Dozzle`은 로그 확인
- `Watchtower`는 자동 이미지 갱신 보조
- Docker 관리 UI는 `ct-devtools` 내부에 설치하지 않고
  별도 Portainer 서버에서 원격 Environment로 등록해 사용합니다.

### 11-1. Homepage 서비스 바로가기 추가

`Homepage`에서 `Uptime Kuma`, `Dozzle` 상태를 Docker 기준으로 자동 연동하고
`Proxmox`를 같이 표시하려면 먼저 `homepage/config/docker.yaml`을 작성합니다.

```bash
cd ~/docker/devtools
cat > ~/docker/devtools/homepage/config/docker.yaml <<'EOF'
devtools-docker:
  socket: /var/run/docker.sock
EOF
```

그다음 `homepage/config/services.yaml`에 아래 내용을 작성합니다.

```bash
cd ~/docker/devtools
cat > ~/docker/devtools/homepage/config/services.yaml <<'EOF'
- Devtools:
  - Uptime Kuma:
      href: http://192.168.0.163:3001
      description: Service monitoring dashboard
      icon: uptime-kuma.png
      server: devtools-docker
      container: uptime-kuma
  - Dozzle:
      href: http://192.168.0.163:3002
      description: Container log viewer
      icon: dozzle.png
      server: devtools-docker
      container: dozzle
- Infra:
  - Proxmox:
      href: https://192.168.0.254:8006
      description: Proxmox VE management
      icon: proxmox.png
      widget:
        type: proxmox
        url: https://192.168.0.254:8006
        username: root@pam!homepage
        password: <change-required>
EOF
```

적용 후 `http://192.168.0.163:3000`에 접속하면
`Devtools` 그룹 아래에 `Uptime Kuma`, `Dozzle` 카드가,
`Infra` 그룹 아래에 `Proxmox` 카드가 보이고 클릭 시 각 서비스로 이동합니다.
`Uptime Kuma`, `Dozzle`는 Docker 컨테이너 상태도 함께 표시할 수 있습니다.

### 11-2. Proxmox API Token 준비

`Homepage`에서 Proxmox 위젯까지 표시하려면 Proxmox API Token이 필요합니다.

Proxmox Web UI 기준 예시 절차:

1. `Datacenter`
1. `Permissions`
1. `API Tokens`
1. 사용자 선택
1. `Add`
1. Token ID 입력
1. Secret 저장

예시:

- Proxmox URL: `https://192.168.0.254:8006`
- 사용자: `root@pam`
- Token ID: `homepage`
- Homepage 입력값: `root@pam!homepage`

운영 메모:

- `services.yaml`의 `username`에는 `root@pam!homepage` 형식 값을 넣습니다.
- `services.yaml`의 `password`에는 API Token secret 값을 넣습니다.
- 운영 환경에서는 `root@pam` 대신 읽기 전용 전용 계정을 따로 만드는 편이 더 안전합니다.
- self-signed 인증서를 쓰는 Proxmox에서는 최초 접속 시 브라우저 경고가 있을 수 있습니다.

운영 메모:

- `href`에는 실제 접속 가능한 서버 IP 또는 도메인을 사용합니다.
- 아이콘이 없어도 링크 동작에는 문제 없습니다.
- `docker.yaml`의 `devtools-docker` 이름은 `services.yaml`의 `server` 값과 같아야 합니다.
- `container`에는 `docker ps`에 보이는 컨테이너 이름을 사용합니다.
- 설정 변경 후 반영이 늦으면 `docker compose restart homepage`로 다시 올립니다.

## 12. 스택 기동

```bash
cd ~/docker/devtools
docker compose up -d
docker compose ps
```

로그 확인:

```bash
docker compose logs --tail=100
```

## 13. 접속 확인

예시 IP가 `192.168.0.163`이면 접속 URL은 아래와 같습니다.

- Homepage: `http://192.168.0.163:3000`
- Uptime Kuma: `http://192.168.0.163:3001`
- Dozzle: `http://192.168.0.163:3002`

검증 명령:

```bash
ss -lntp
docker ps
```

기대 결과:

- 관리 도구 컨테이너가 `Up` 상태
- 각 포트가 LISTEN 상태
- 브라우저에서 첫 화면 접속 가능
- Portainer 관리는 별도 서버 UI에서 수행

## 14. Portainer에서 다른 서버 Docker Engine 등록

다른 서버의 Docker Engine을 Portainer에 등록할 때는
Docker API를 직접 외부에 여는 방식보다 `Portainer Agent` 방식을 권장합니다.

이 방식의 장점은 아래와 같습니다.

- 대상 서버마다 표준 절차로 붙일 수 있음
- Docker 소켓을 원격 TCP로 직접 노출하지 않아도 됨
- Portainer UI에서 여러 Docker 호스트를 일관되게 관리 가능

예시:

- Portainer 서버: `192.168.0.2`
- 등록 대상 Docker 서버: `192.168.0.163`
- Agent 포트: `9001/tcp`

### 14-1. 대상 서버 사전 조건

등록 대상 서버에는 아래 조건이 먼저 충족되어야 합니다.

- Docker 설치 완료
- `docker ps` 정상 동작
- Portainer 서버에서 대상 서버 `9001/tcp`로 접근 가능

방화벽 사용 중이면 `9001/tcp` 허용도 함께 확인합니다.

### 14-2. 대상 서버에 Portainer Agent 실행

대상 서버에서 작업 디렉터리를 만든 뒤 `docker compose`로 실행합니다.

```bash
mkdir -p ~/docker/portainer-agent
cd ~/docker/portainer-agent
```

`docker-compose.yml` 예시:

```yaml
services:
  portainer-agent:
    image: portainer/agent:latest
    container_name: portainer-agent
    restart: unless-stopped
    ports:
      - "192.168.0.163:9001:9001"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
      - portainer_agent_data:/data

volumes:
  portainer_agent_data:
```

기동:

```bash
cd ~/docker/portainer-agent
docker compose up -d
```

검증:

```bash
docker ps
ss -lntp | grep 9001
```

기대 결과:

- `portainer_agent` 컨테이너가 `Up` 상태
- 대상 서버에서 `9001` 포트가 LISTEN 상태

운영 메모:

- Agent는 등록 대상 서버마다 1개씩 실행합니다.
- 대상 서버가 여러 대라면 동일한 방식으로 각 서버에 Agent를 배치합니다.

### 14-3. Portainer UI에서 Environment 추가

Portainer UI에서 아래 순서로 등록합니다.

1. `Environments`
1. `Add environment`
1. `Docker Standalone` 선택
1. `Agent` 선택
1. `Name` 입력
1. `Environment URL` 입력
1. `Connect`

입력 예시:

- Name: `ct-devtools`
- Environment URL: `192.168.0.163:9001`

등록이 성공하면 Portainer 좌측 환경 목록에서
새 Docker 호스트가 별도 Environment로 보입니다.

### 14-4. 연결 실패 시 우선 점검

아래 항목을 순서대로 확인합니다.

- 대상 서버에서 `docker ps`가 정상인지 확인
- 대상 서버에서 `portainer_agent` 컨테이너가 실행 중인지 확인
- 대상 서버에서 `9001/tcp`가 LISTEN 상태인지 확인
- Portainer 서버에서 대상 서버 `9001/tcp`로 라우팅 가능한지 확인
- 중간 방화벽 또는 보안 그룹에서 `9001/tcp`가 차단되지 않았는지 확인

주의:

- `2375/tcp`로 Docker API를 평문 개방하는 방식은 권장하지 않습니다.
- 원격 서버가 인터넷 구간이나 비신뢰 네트워크를 지나면
  Agent 연결 경로를 내부망으로 제한하는 것을 권장합니다.

## 15. 트러블슈팅

### root SSH 로그인은 되는데 비밀번호 인증이 실패함

- Ubuntu LXC 템플릿에서 `root` SSH가 기본적으로 막혀 있을 수 있습니다.
- 이 문서 기준 운영 방식은 `root` 직접 로그인 대신 `semtl` 계정 사용입니다.

### `docker ps`가 permission denied로 실패함

- `sudo usermod -aG docker "$USER"` 적용 후 재로그인이 필요합니다.
- 재로그인 후 `groups` 출력에 `docker` 그룹이 보이는지 확인합니다.

### `docker compose up -d` 전에 `pull`에서 TLS 오류가 남

- `timedatectl`로 시간 동기화를 먼저 확인합니다.
- `System clock synchronized: yes` 여부를 우선 확인합니다.

### CT 안에서 Docker가 이상하게 동작함

- Proxmox CT `Features`에 `nesting=1`, `keyctl=1`이 켜져 있는지 확인합니다.
- `pct config <CT-ID>`에서 실제 반영 여부를 다시 확인합니다.

## 참고

- [Proxmox Overview](../proxmox/overview.md)
- [Proxmox Installation](../proxmox/installation.md)
- [Proxmox CT Template Guide](../proxmox/ct-template-guide.md)
- [Proxmox DNS And Hostname Guide](../proxmox/dns-and-hostname-guide.md)
