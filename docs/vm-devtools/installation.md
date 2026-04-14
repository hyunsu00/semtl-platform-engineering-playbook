# VM Devtools Installation

## 개요

이 문서는 Synology `Virtual Machine Manager`에서 Ubuntu 22.04 기반
`vm-devtools` VM을 만들고,
운영 계정, SSH, Docker, 기본 관리 도구 스택까지 실제로 동작한 기준으로
따라갈 수 있게 정리한 문서입니다.

이 문서의 목표는 아래 상태까지 한 번에 만드는 것입니다.

- VM 이름: `vm-devtools`
- Synology VMM 표시 이름: `VM-DEVTOOLS`
- 운영 계정: `semtl`
- 접속 방식: `semtl` 계정 + `sudo`
- Docker 운영 경로: `~/docker/devtools`
- 기본 관리 도구: `Homepage`, `Uptime Kuma`, `Dozzle`, `Watchtower`

이 문서는 실사용 중 최종적으로 성공한 흐름만 남기고,
중간 시행착오는 제외합니다.

## 사용 시점

- 홈랩 운영용 공통 관리 VM이 필요한 경우
- Docker 기반 관리 도구를 한 VM에 모아 운영하려는 경우
- 일반 사용자 + `sudo` 기준으로 표준 관리 노드를 만들려는 경우
- Synology VMM 스냅샷과 VM 백업 기준점을 남기며 운영하려는 경우

## 최종 성공 기준

이 문서 기준 최종 성공 상태는 아래와 같습니다.

- Synology VMM에서 Ubuntu 22.04 기반 VM 생성 완료
- `qemu-guest-agent` 설치 및 Synology VMM 연동 완료
- 다른 관리 PC에서 `ssh semtl@<VM-IP>` 접속 가능
- `sudo whoami` 결과가 `root`
- Docker 서비스 기동 및 `docker ps` 정상 동작
- `docker compose up -d`로 관리 도구 스택 기동 완료

예시 운영값:

- hostname: `vm-devtools`
- Synology VMM 표시 이름: `VM-DEVTOOLS`
- IP: `192.168.0.51`

## 사전 조건

- Synology NAS에서 `Virtual Machine Manager` 사용 가능 상태
- Ubuntu 22.04 ISO 업로드 완료
- `Default VM Network` 사용 가능 상태
- VM용 스토리지 확보

## 1. VM 생성

Synology `Virtual Machine Manager`에서 Ubuntu 22.04 기반 VM을 생성합니다.

권장 기준:

- Name: `VM-DEVTOOLS`
- OS: `Ubuntu 22.04`
- BIOS/Firmware: `UEFI`
- Machine Type: `Q35`
- Video Card: `vga`
- Disk: `60GB`
- Network: `Default VM Network`
- Network Model: `VirtIO`
- IPv4: `DHCP`로 먼저 검증
- Boot: `Virtual Disk`
- Auto Start: `No`

권장 리소스:

- vCPU: `2`
- RAM: `8GB`
- Disk: `60GB`

운영 메모:

- 관리 도구를 장기 운영할 계획이면 Docker 호환성과 확장성 측면에서 VM 구성이 단순합니다.
- 네트워크는 먼저 `DHCP`로 검증한 뒤 필요 시 고정 IP로 전환하는 편이 안전합니다.
- `RAM 8GB`는 VM이 부팅 직후 항상 `8GB`를 즉시 점유한다는 의미가 아니라,
  게스트 OS에 할당된 메모리 기준입니다.
- `Homepage`, `Uptime Kuma`, `Dozzle`, `Watchtower`를 함께 올릴 계획이면
  `8GB` 구성이 여유롭습니다.

## 2. Ubuntu 기본 설정

VM 콘솔 또는 설치 시 생성한 운영 계정 `semtl`로 접속한 뒤 기본 패키지를 먼저 정리합니다.

```bash
sudo apt update
sudo apt install -y qemu-guest-agent sudo ca-certificates curl git openssh-server
sudo systemctl enable --now qemu-guest-agent ssh
```

검증:

```bash
systemctl status qemu-guest-agent --no-pager
systemctl status ssh --no-pager
```

운영 메모:

- Synology VMM에서 게스트 IP 확인, 종료, 일부 상태 수집을 안정적으로 하려면
  `qemu-guest-agent`를 먼저 넣는 편이 좋습니다.

## 3. SSH 접속 확인

다른 PC에서 접속을 확인합니다.

```bash
ssh semtl@192.168.0.51
```

로그인 후 `sudo` 권한을 확인합니다.

```bash
sudo whoami
```

기대 결과:

- `root`

## 4. 시간 및 locale 점검

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
NTP service: active
```

운영 메모:

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

## 5. VM 기준 Docker 설치

`vm-devtools` 운영 VM에서는 Ubuntu 기본 패키지 대신
Docker 공식 Ubuntu 저장소 기준으로 Docker Engine을 설치합니다.

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

## 6. Docker 설치 직후 정리 후 스냅샷

Docker 설치와 `docker ps` 확인까지 끝났으면,
관리 도구 스택을 올리기 전에 Synology VMM에서 기준 스냅샷을 먼저 남기는 것을 권장합니다.

이 단계의 목적은 아래와 같습니다.

- Docker 엔진까지 정상 동작하는 최소 기준점 보존
- 이후 `Homepage`, `Uptime Kuma`, `Dozzle` 구성 실패 시 빠른 롤백
- 설치 직후 찌꺼기를 정리한 깨끗한 상태 유지

스냅샷은 반드시 불필요 파일 정리 후 생성합니다.

### 6-1. 불필요 파일 정리

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

- 이 문서에서는 템플릿 변환이 아니라 운영 VM 기준 스냅샷을 남깁니다.
- Docker image나 볼륨 데이터가 아직 크지 않은 초기 상태에서 남기는 것이 가장 효율적입니다.

### 6-2. Synology VMM 스냅샷 생성

권장 시점:

- `semtl` 계정 SSH 접속 확인 완료
- `sudo whoami` 확인 완료
- Docker 공식 저장소 기반 설치 완료
- `docker version`, `docker ps`, `hello-world` 검증 완료
- 아직 관리 도구 스택은 올리기 전

Synology VMM UI 절차:

1. `vm-devtools` VM 선택
1. `작업`
1. `스냅샷`
1. 스냅샷 이름과 설명 입력 후 생성

권장 이름:

- `vm-devtools-docker-clean-v1`

권장 설명 예시:

```text
[설치]
- vm-devtools 초기 VM 생성 완료
- semtl 계정 및 sudo 설정 완료
- SSH 접속 확인 완료
- locale UTF-8 설정 완료
- qemu-guest-agent 설치 완료
- Docker 공식 저장소 기반 설치 완료
- docker hello-world / docker ps 검증 완료
- 관리 도구 스택 설치 전 베이스라인
```

운영 메모:

- 이후 `docker-compose.yml` 작성 전에도 설정이 크게 바뀐다면 별도 사전 스냅샷을 한 번 더 남기는 편이 안전합니다.
- 장기 운영 중 스냅샷을 오래 유지하면 스토리지 사용량이 커질 수 있으므로 기준점 스냅샷만 남기고 정리 정책을 같이 가져가야 합니다.

## 7. 작업 디렉터리 준비

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

## 8. Devtools 스택 작성

이 문서 기준 관리 도구는 `vm-devtools` 내부에서 각 포트를 직접 열어
같은 네트워크 대역에서 바로 접속하는 구조입니다.

아래 `docker-compose.yml`을 기준으로 관리 도구를 한 번에 올립니다.

```yaml
services:
  homepage:
    image: ghcr.io/gethomepage/homepage:latest
    container_name: homepage
    ports:
      - "3000:3000"
    volumes:
      - ./homepage/config:/app/config
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      HOMEPAGE_ALLOWED_HOSTS: 192.168.0.51:3000,localhost:3000
    restart: unless-stopped

  uptime-kuma:
    image: louislam/uptime-kuma:latest
    container_name: uptime-kuma
    ports:
      - "3001:3001"
    volumes:
      - ./uptime-kuma:/app/data
    restart: unless-stopped

  dozzle:
    image: amir20/dozzle:latest
    container_name: dozzle
    ports:
      - "3002:8080"
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

### 8-1. Homepage 기본 설정

기본 대시보드만 먼저 쓰려면 아래 세 파일만 준비하면 됩니다.

```bash
cd ~/docker/devtools
cat > ~/docker/devtools/homepage/config/docker.yaml <<'EOF'
devtools-docker:
  socket: /var/run/docker.sock
EOF

cat > ~/docker/devtools/homepage/config/services.yaml <<'EOF'
- DevTools:
  - Homepage:
      href: http://192.168.0.51:3000
      description: Main dashboard
  - Uptime Kuma:
      href: http://192.168.0.51:3001
      description: Service monitoring dashboard
      server: devtools-docker
      container: uptime-kuma
  - Dozzle:
      href: http://192.168.0.51:3002
      description: Container log viewer
      server: devtools-docker
      container: dozzle
EOF

cat > ~/docker/devtools/homepage/config/widgets.yaml <<'EOF'
---
- resources:
    label: vm-devtools
    cpu: true
    memory: true
    disk: /
EOF
```

적용 후 `Homepage`를 다시 올립니다.

```bash
cd ~/docker/devtools
docker compose up -d homepage
docker compose logs --tail=100 homepage
```

운영 메모:

- Docker 설치 후 `172.17.0.1`, `172.18.0.1` 같은 추가 IP가 함께 보일 수
  있는데, 이는 Docker 브리지 주소이므로 정상입니다.
- 추가 서비스 연동이 필요하면 `services.yaml`에 카드만 더하는 방식으로 확장합니다.

## 9. 스택 기동

```bash
cd ~/docker/devtools
docker compose up -d
docker compose ps
```

로그 확인:

```bash
docker compose logs --tail=100
```

## 10. 접속 확인

예시 접속 URL은 아래와 같습니다.

- Homepage: `http://192.168.0.51:3000`
- Uptime Kuma: `http://192.168.0.51:3001`
- Dozzle: `http://192.168.0.51:3002`

검증 명령:

```bash
ss -lntp
docker ps
docker compose logs --tail=100 homepage
```

기대 결과:

- 관리 도구 컨테이너가 `Up` 상태
- `3000/tcp`, `3001/tcp`, `3002/tcp`가 LISTEN 상태
- 브라우저에서 첫 화면 접속 가능

## 11. 트러블슈팅

### `docker ps`가 permission denied로 실패함

- `sudo usermod -aG docker "$USER"` 적용 후 재로그인이 필요합니다.
- 재로그인 후 `groups` 출력에 `docker` 그룹이 보이는지 확인합니다.

### `docker compose up -d` 전에 `pull`에서 TLS 오류가 남

- `timedatectl`로 시간 동기화를 먼저 확인합니다.
- `System clock synchronized: yes` 여부를 우선 확인합니다.

### Synology VMM에서 VM IP가 바로 보이지 않음

- `qemu-guest-agent`가 설치되어 있고 실행 중인지 확인합니다.
- Synology VMM `개요` 화면에서 게스트 에이전트 상태가 `실행 중`인지 확인합니다.

## 참고

- [Synology Installation](../synology/installation.md)
- [Synology WireGuard Zigbee2MQTT HA Integration](../synology/wireguard-zigbee2mqtt-ha-integration.md)
- [Proxmox DNS And Hostname Guide](../proxmox/dns-and-hostname-guide.md)
