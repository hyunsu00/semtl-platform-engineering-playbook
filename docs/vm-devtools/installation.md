# VM Devtools Installation

## 개요

이 문서는 `Proxmox VE`에서 `P1000` 패스스루가 포함된 `vm-devtools` VM을 만들고
`Ubuntu 22.04 Server` 기본 설치, SSH, Docker, 기본 관리 도구까지 한 번에
따라갈 수 있게 정리한 문서입니다.

목표:

- VM 이름: `vm-devtools`
- 게스트 OS: `Ubuntu 22.04 Server`
- GPU: `NVIDIA Quadro P1000` PCIe 패스스루
- 운영 계정: `semtl`
- 접속 방식: `semtl` 계정 + `sudo`
- Docker 운영 경로: `~/docker/devtools`
- 기본 관리 도구: `Homepage`, `Uptime Kuma`, `Dozzle`, `Watchtower`

## 사용 시점

- 홈랩 운영용 공통 관리 VM이 필요한 경우
- Docker 기반 관리 도구를 한 VM에 모아 운영하려는 경우
- Proxmox에서 GPU 패스스루가 필요한 Linux 관리 VM을 따로 두려는 경우
- 일반 사용자 + `sudo` 기준으로 표준 관리 노드를 만들려는 경우
- Proxmox 스냅샷과 VM 백업 기준점을 남기며 운영하려는 경우

## 최종 성공 기준

- Proxmox에서 `Ubuntu 22.04 Server` 기반 VM 생성 완료
- `P1000` VGA 패스스루 추가 완료
- `qemu-guest-agent` 설치 및 Proxmox 연동 완료
- 다른 관리 PC에서 `ssh semtl@<VM-IP>` 접속 가능
- `sudo whoami` 결과가 `root`
- 게스트 OS에서 `lspci`로 NVIDIA VGA 장치 확인 가능
- `xrdp`를 통해 GUI 세션 접속 가능
- Docker 서비스 기동 및 `docker ps` 정상 동작
- `docker compose up -d`로 관리 도구 스택 기동 완료

예시 운영값:

- hostname: `vm-devtools`
- Proxmox VM 이름: `vm-devtools`
- IP: `192.168.0.231`

## 사전 조건

- Proxmox VE 설치 및 관리 접속 가능 상태
- Proxmox 노드에 `Ubuntu 22.04 Server` ISO 업로드 완료
- `vmbr0` 등 VM 연결용 브리지 준비 완료
- VM용 스토리지 확보
- BIOS/UEFI에서 `VT-d` 또는 `AMD-Vi(IOMMU)` 활성화 완료
- P1000이 Proxmox 호스트에서 다른 VM이나 LXC에 할당되지 않은 상태
- 가능하면 모니터는 `P1000` 출력 포트에 직접 연결

예시 확인 명령:

```bash
dmesg | grep -e DMAR -e IOMMU
lspci -nn | grep -i nvidia
```

## 1. VM 생성

Proxmox Web UI에서 `Create VM`으로 `vm-devtools` VM을 생성합니다.

권장 기준:

- Name: `vm-devtools`
- OS: `Ubuntu 22.04 Server`
- BIOS: `OVMF (UEFI)`
- Machine Type: `Q35`
- EFI Disk: 추가
- SCSI Controller: `VirtIO SCSI single`
- Display: `Default`
- Disk: `120GB`
- Disk Bus: `VirtIO Block` 또는 `SCSI`
- Network Bridge: `vmbr0`
- Network Model: `VirtIO`
- IPv4: `DHCP`로 먼저 검증
- Boot: `Virtual Disk`
- Agent: `Enabled`
- Auto Start: `No`

권장 리소스:

- vCPU: `4`
- RAM: `16GB`
- Disk: `120GB`

운영 메모:

- Docker 기반 관리 도구와 GPU 패스스루 검증을 함께 둘 계획이면
  `vCPU 4`, `RAM 16GB`, `Disk 120GB` 기준으로 시작하는 편이 안정적입니다.
- 네트워크는 먼저 `DHCP`로 검증한 뒤 필요 시 고정 IP로 전환하는 편이 안전합니다.
- `Homepage`, `Uptime Kuma`, `Dozzle`, `Watchtower`를 함께 올릴 계획이면
  `16GB` 구성이 여유롭습니다.

## 2. Ubuntu 22.04 Server 기본 설치

Ubuntu Server 설치 화면에서 일반 사용자 계정 `semtl`을 생성합니다.
설치가 끝나면 VM 콘솔 또는 SSH로 로그인해 hostname, 게스트 에이전트,
기본 패키지를 먼저 정리합니다.

### 2-1. hostname 및 `/etc/hosts` 설정

hostname은 짧은 이름을 사용하고, `/etc/hosts`에는 FQDN과 짧은 이름을 함께
등록합니다.

```bash
sudo hostnamectl set-hostname vm-devtools
```

`/etc/hosts`에 아래 항목을 추가하거나 기존 `127.0.1.1` 라인을 교체합니다.

```text
127.0.1.1 devtools.internal.semtl.synology.me vm-devtools
```

검증:

```bash
hostname
hostname -f
getent hosts vm-devtools
getent hosts devtools.internal.semtl.synology.me
```

기대 결과:

- `hostname`: `vm-devtools`
- `hostname -f`: `devtools.internal.semtl.synology.me`

### 2-2. qemu-guest-agent 및 기본 패키지 설치

```bash
sudo apt update -y
sudo apt install -y qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent
```

검증:

```bash
systemctl status qemu-guest-agent --no-pager
ip -brief address
```

운영 메모:

- Proxmox에서 게스트 IP 확인, 종료, 일부 상태 수집을 안정적으로 하려면
  `qemu-guest-agent`를 먼저 넣는 편이 좋습니다.
- Proxmox VM `Options`에서 `QEMU Guest Agent`가 `Enabled`인지 같이 확인합니다.

### 2-3. SSH, sudo, 시간 확인

다른 관리 PC에서 접속을 확인합니다.

```bash
ssh semtl@192.168.0.231
```

로그인 후 `sudo` 권한과 시간 동기화를 확인합니다.

```bash
sudo whoami
timedatectl
```

기대 결과:

- `sudo whoami`: `root`
- `System clock synchronized`: `yes`
- `NTP service`: `active`

## 3. Ubuntu 기본 설치 직후 스냅샷

### 3-1. 불필요 파일 정리

스냅샷은 불필요 파일을 정리한 뒤 생성합니다.

```bash
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*
sudo apt autoremove -y
sudo apt clean
sudo journalctl --vacuum-time=1s
cat /dev/null > /home/semtl/.bash_history && history -c
```

### 3-2. Proxmox 스냅샷 생성

1. `vm-devtools` VM 선택
1. `Snapshots`
1. `Take Snapshot`
1. 스냅샷 이름과 설명 입력 후 생성

- 권장 이름: `BASELINE`

권장 설명:

```text
- semtl / 패스워드
- hostname / hostname -f 수정 (/etc/hosts)
  `127.0.1.1 devtools.internal.semtl.synology.me vm-devtools`
- qemu-guest-agent 설치 및 활성화
- 불필요한 파일 삭제
```

## 4. P1000 VGA 패스스루 장치 추가

기본 설치 스냅샷을 남긴 뒤 VM에 `P1000` VGA/Audio 장치를 추가합니다.
이 구간은 Proxmox 호스트와 Proxmox Web UI에서 진행합니다.

### 4-1. BIOS 설정 확인

이 문서 기준 확인값:

- `Intel(R) Virtualization Technology`: `Enabled`
- `VT-d Feature`: `Enabled`
- `IOMMU`: `Enabled`
- `Select Active Video`: `Auto`

운영 메모:

- `IGD`로 고정하면 이 문서의 테스트 환경에서는 `P1000`이 보이지 않았습니다.
- `Auto`에서 `P1000` 인식이 확인됐습니다.
- `Auto`에서는 `AMT` 화면이 OS 부팅 이후부터 보일 수 있습니다.

### 4-2. Proxmox 호스트에서 GPU 인식 확인

```bash
lspci -nn | grep -E 'VGA|3D|NVIDIA'
```

기대 결과 예시:

```text
02:00.0 VGA compatible controller [0300]:
NVIDIA Corporation GP107GL [Quadro P1000] [10de:1cb1]
02:00.1 Audio device [0403]:
NVIDIA Corporation GP107GL High Definition Audio Controller [10de:0fb9]
```

같이 확인:

```bash
dmesg | grep -e DMAR -e IOMMU
find /sys/kernel/iommu_groups/ -type l | grep 02:00
```

운영 메모:

- `lspci`에서 `P1000`이 안 보이면 다음 단계로 넘어가지 않습니다.

### 4-3. Proxmox 호스트에 IOMMU/VFIO 설정

1. `/etc/default/grub` 수정

```text
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"
```

1. 적용 후 재부팅

```bash
sudo update-grub
sudo reboot
```

1. 재부팅 후 확인

```bash
cat /proc/cmdline
dmesg | grep -e DMAR -e IOMMU
```

1. `/etc/modules`에 아래 추가

```text
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
```

1. `/etc/modprobe.d/vfio.conf` 생성

```text
options vfio-pci ids=10de:1cb1,10de:0fb9
```

1. initramfs 갱신 후 재부팅

```bash
sudo update-initramfs -u -k all
sudo reboot
```

1. 검증

```bash
lsmod | grep vfio
lspci -nnk -s 02:00.0
lspci -nnk -s 02:00.1
```

기대 결과 예시:

```text
02:00.0 ... Kernel driver in use: vfio-pci
02:00.1 ... Kernel driver in use: vfio-pci
```

운영 메모:

- `Kernel driver in use: vfio-pci`가 보이면 정상입니다.

### 4-4. VM에 P1000 추가

`vm-devtools` VM의 `Hardware` 탭에서 `Add -> PCI Device`를 실행합니다.

중요:

- `매핑한 디바이스`가 비어 있어도 정상입니다.
- 이 문서 기준으로는 `Raw 디바이스`를 사용합니다.
- `Raw 디바이스` 추가는 `root@pam`으로 진행합니다.

오류 예시:

```text
only root can set 'hostpci0' config for non-mapped devices (500)
```

조치:

- `Raw 디바이스`를 직접 추가할 때는 `root@pam`으로 로그인해서 다시 시도합니다.

권장 기준:

- Display: `Default` 유지
- PCI Device: `02:00.0` `NVIDIA Quadro P1000` VGA 장치
- 별도 Audio 함수: `02:00.1`
- `PCI-Express`: 체크
- `All Functions`: 이 문서 기준으로는 체크하지 않음
- `ROM-Bar`: 기본값 유지
- `Primary GPU`: 체크하지 않음

권장 순서:

1. `02:00.0` VGA 장치 추가
1. `PCI-Express` 체크
1. `Primary GPU` 체크하지 않음
1. `All Functions`는 체크하지 않음
1. 저장
1. `02:00.1` Audio 장치 추가
1. `PCI-Express` 체크
1. Audio 장치에는 `Primary GPU`를 체크하지 않음
1. `x-vga=1`은 넣지 않음
1. `Display: Default` 유지

설정 예시:

- VGA 장치(`02:00.0`)
  - `Raw 디바이스`
  - 디바이스: `0000:02:00.0`
  - 설치 초기에는 `Primary GPU`: 체크 안 함
  - `PCI-Express`: 체크
  - `ROM-Bar`: 체크 유지
  - `All Functions`: 체크 안 함
- Audio 장치(`02:00.1`)
  - `Raw 디바이스`
  - 디바이스: `0000:02:00.1`
  - `Primary GPU`: 체크 안 함
  - `PCI-Express`: 체크
  - `ROM-Bar`: 체크 유지
  - `All Functions`: 체크 안 함

권장 하드웨어 예시:

```text
PCI 디바이스 (hostpci0)  0000:02:00.0,pcie=1
PCI 디바이스 (hostpci1)  0000:02:00.1,pcie=1
```

운영 메모:

- Server VM에서는 noVNC와 기본 콘솔 접근성을 유지하기 위해 `Primary GPU`와
  `x-vga=1`을 사용하지 않는 구성을 우선합니다.
- 패스스루 후 부팅이 되지 않으면 `Primary GPU` 체크 여부와 EFI/OVMF 조합을
  먼저 다시 확인합니다.

### 4-5. 게스트에서 P1000 인식 확인

VM을 완전히 종료한 뒤 다시 시작하고, 게스트 OS에서 장치가 보이는지 확인합니다.
`lspci` 명령이 없으면 `pciutils`를 먼저 설치합니다.

```bash
sudo apt update
sudo apt install -y pciutils
```

```bash
lspci -nn | grep -i nvidia
```

기대 결과 예시:

<!-- markdownlint-disable MD013 -->
```text
01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP107GL [Quadro P1000] [10de:1cb1] (rev a1)
02:00.0 Audio device [0403]: NVIDIA Corporation GP107GL High Definition Audio Controller [10de:0fb9] (rev a1)
```
<!-- markdownlint-enable MD013 -->

운영 메모:

- 게스트 OS 안에서 보이는 PCI 주소는 Proxmox 호스트의 `02:00.0`, `02:00.1`과
  다를 수 있습니다.
- `Quadro P1000` VGA 장치와 `High Definition Audio Controller`가 함께 보이면
  패스스루 장치 인식 기준은 충족입니다.

## 5. NVIDIA 드라이버 확인

GPU 연산이나 `nvidia-smi` 확인이 필요한 경우에는 Docker 설치 전 스냅샷을
남기기 전에 이 단계를 먼저 진행합니다. 단순 PCI 패스스루 장치 추가 기준점만
필요하면 `lspci` 확인만으로 충분하므로 이 단계는 건너뛸 수 있습니다.

```bash
sudo apt update
sudo apt install -y ubuntu-drivers-common
ubuntu-drivers devices
```

```bash
sudo ubuntu-drivers autoinstall
sudo reboot
```

```bash
nvidia-smi
```

추가 확인:

```bash
lspci -nnk | grep -A3 -i nvidia
lsmod | grep nvidia
```

기대 결과:

- `nvidia-smi`에서 `Quadro P1000`이 보여야 합니다.
- NVIDIA VGA 장치의 `Kernel driver in use`가 `nvidia`로 보여야 합니다.

## 6. XRDP GUI 접속 환경 설치

Ubuntu Server 기준으로는 GUI 세션이 없으므로 `xrdp`와 가벼운 데스크톱 환경을
함께 설치합니다. 이 단계까지 완료한 뒤 스냅샷을 남기면 Docker 설치 전
GUI 접속 가능한 기준점으로 되돌아갈 수 있습니다.

### 6-1. XRDP/XFCE 설치

```bash
sudo apt update
sudo apt install -y xrdp xorgxrdp xfce4 xfce4-goodies dbus-x11 \
  arc-theme papirus-icon-theme fonts-noto-cjk language-pack-ko \
  language-pack-gnome-ko
echo "startxfce4" > ~/.xsession
sudo adduser xrdp ssl-cert
sudo systemctl enable --now xrdp
sudo systemctl restart xrdp
```

### 6-2. XFCE 메뉴 한글화

XFCE 메뉴와 기본 앱 이름을 한글로 보려면 시스템 locale을 `ko_KR.UTF-8`로
생성한 뒤 기본 locale로 설정합니다.

```bash
sudo locale-gen ko_KR.UTF-8
sudo update-locale LANG=ko_KR.UTF-8
cat /etc/default/locale
```

재접속 후 확인:

```bash
locale
```

### 6-3. XRDP 속도 튜닝

XRDP가 다소 느리게 느껴지면 서버 설정 파일을 직접 바꾸기보다 RDP 클라이언트와
XFCE 효과를 먼저 조정합니다.

- Color depth: `True color (24 bit)` 또는 느리면 `High color (16 bit)`
- 화면 크기: 필요한 해상도만 사용
- 배경화면, 애니메이션, 창 내용 표시 옵션은 끄기
- 내부망에서는 `LAN` 또는 최고 품질보다 한 단계 낮은 성능 프리셋 사용

### 6-4. XFCE UI 정리

첫 XRDP 로그인 후 `Settings`에서 아래처럼 정리합니다.

- `Appearance > Style`: `Arc-Dark` 또는 `Arc`
- `Appearance > Icons`: `Papirus`
- `Window Manager > Style`: `Arc-Dark` 또는 `Arc`
- `Window Manager Tweaks > Compositor`: 비활성화
- `Session and Startup > Application Autostart`: 불필요한 자동 시작 항목 비활성화

운영 메모:

- XFCE compositor를 끄면 투명 효과는 줄어들지만 XRDP 반응성이 좋아집니다.
- 한글 UI나 한글 파일명을 볼 계획이면 `fonts-noto-cjk`를 설치해두는 편이
  안전합니다.

방화벽을 사용하는 경우에만 RDP 포트를 허용합니다.

```bash
sudo ufw allow from 192.168.0.0/24 to any port 3389 proto tcp
```

검증:

```bash
systemctl status xrdp --no-pager
ss -lntp | grep 3389
```

다른 관리 PC에서 RDP 클라이언트로 접속합니다.

- 접속 주소: `192.168.0.231:3389`
- 계정: `semtl`
- 세션: `Xorg`

운영 메모:

- XRDP 로그인 전 VM 콘솔이나 SSH에서 같은 사용자 GUI 세션을 열어둔 경우
  세션 충돌이 날 수 있으므로 로그아웃 후 접속합니다.
- `3389/tcp`는 내부 관리망에서만 접근 가능하게 제한합니다.

### 6-5. XRDP와 GPU 가속 기준

이 문서의 XRDP 구성은 관리 작업용 원격 GUI 기준입니다. P1000 패스스루와
NVIDIA 드라이버가 정상이어도 XRDP/XFCE 정보 창에서는 GPU가 `llvmpipe`로
보일 수 있습니다.

운영 기준:

- P1000 패스스루와 드라이버 확인: `nvidia-smi`, `lspci -nnk`
- XRDP 관리 GUI 확인: RDP 로그인, XFCE 동작, 관리 앱 실행
- XRDP 세션의 3D 렌더링 확인: `glxinfo -B`의 `OpenGL renderer`

```bash
sudo apt install -y mesa-utils
glxinfo -B
```

운영 메모:

- `nvidia-smi`가 정상이고 `glxinfo -B`에서 `llvmpipe`가 보여도 GPU 연산용
  드라이버는 정상일 수 있습니다.
- XRDP 기본 Xorg 세션을 NVIDIA 렌더러로 직접 가속하는 구성은 배포판,
  `xrdp`, `xorgxrdp`, NVIDIA 드라이버 버전에 민감합니다. 이 문서의 기본
  설치 기준에는 포함하지 않습니다.
- GPU 가속 GUI가 반드시 필요하면 XRDP 기본 세션보다 P1000에 연결된 물리
  화면의 로컬 Xorg 세션을 원격으로 보는 방식이나, VirtualGL/TurboVNC,
  NoMachine 같은 별도 원격 데스크톱 구성을 우선 검토합니다.

## 7. P1000 장치 추가 직후 스냅샷

### 7-1. 불필요 파일 정리

스냅샷 전 게스트 OS 안에서 다시 정리합니다.

```bash
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*
sudo apt autoremove -y
sudo apt clean
sudo journalctl --vacuum-time=1s
cat /dev/null > ~/.bash_history && history -c
```

### 7-2. Proxmox 스냅샷 생성

1. `vm-devtools` VM 선택
1. `Snapshots`
1. `Take Snapshot`
1. 스냅샷 이름과 설명 입력 후 생성

- 권장 이름: `p1000-xrdp-clean-v1`

권장 설명:

```text
[설치]
- gpu passthrough : NVIDIA Quadro P1000 VGA/Audio
- gpu driver : NVIDIA 535.288.01
- nvidia-smi : success
- xrdp/xfce : enabled
- xrdp renderer : llvmpipe
```

## 8. Docker 설치 전 최종 확인

```bash
hostname
hostname -f
systemctl is-active qemu-guest-agent
systemctl is-active ssh
systemctl is-active xrdp
timedatectl
lspci -nn | grep -i nvidia
```

확인 기준:

- `hostname -f`가 `devtools.internal.semtl.synology.me`
- `qemu-guest-agent`, `ssh`, `xrdp`가 `active`
- `System clock synchronized: yes`
- `lspci`에서 `Quadro P1000`과 Audio 함수 확인

## 9. VM 기준 Docker 설치

```bash
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  sudo apt remove -y "$pkg"
done

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

다시 로그인 후 확인:

```bash
sudo docker run hello-world
docker version
docker ps
```

## 10. Docker 설치 직후 정리 후 스냅샷

### 10-1. 불필요 파일 정리

```bash
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*
sudo apt autoremove -y
sudo apt clean
sudo journalctl --vacuum-time=1s
cat /dev/null > ~/.bash_history && history -c
```

### 10-2. Proxmox 스냅샷 생성

1. `vm-devtools` VM 선택
1. `Snapshots`
1. `Take Snapshot`
1. 스냅샷 이름과 설명 입력 후 생성

- 권장 이름: `vm-devtools-docker-clean-v1`

## 11. 작업 디렉터리 준비

```bash
mkdir -p ~/docker/devtools
cd ~/docker/devtools
mkdir -p homepage/config
mkdir -p uptime-kuma
```

## 12. Devtools 스택 작성

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
      HOMEPAGE_ALLOWED_HOSTS: 192.168.0.231:3000,localhost:3000
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

### 12-1. Homepage 기본 설정

```bash
cd ~/docker/devtools
cat > ~/docker/devtools/homepage/config/docker.yaml <<'EOF'
devtools-docker:
  socket: /var/run/docker.sock
EOF

cat > ~/docker/devtools/homepage/config/services.yaml <<'EOF'
- DevTools:
  - Homepage:
      href: http://192.168.0.231:3000
      description: Main dashboard
  - Uptime Kuma:
      href: http://192.168.0.231:3001
      description: Service monitoring dashboard
      server: devtools-docker
      container: uptime-kuma
  - Dozzle:
      href: http://192.168.0.231:3002
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

적용:

```bash
cd ~/docker/devtools
docker compose up -d homepage
docker compose logs --tail=100 homepage
```

## 13. 스택 기동

```bash
cd ~/docker/devtools
docker compose up -d
docker compose ps
```

```bash
docker compose logs --tail=100
```

## 14. 접속 확인

- Homepage: `http://192.168.0.231:3000`
- Uptime Kuma: `http://192.168.0.231:3001`
- Dozzle: `http://192.168.0.231:3002`

```bash
ss -lntp
docker ps
docker compose logs --tail=100 homepage
```

## 15. 트러블슈팅

### `docker ps`가 permission denied로 실패함

- `sudo usermod -aG docker "$USER"` 적용 후 재로그인이 필요합니다.
- 재로그인 후 `groups` 출력에 `docker` 그룹이 보이는지 확인합니다.

### `docker compose up -d` 전에 `pull`에서 TLS 오류가 남

- `timedatectl`로 시간 동기화를 먼저 확인합니다.
- `System clock synchronized: yes` 여부를 우선 확인합니다.

### Proxmox에서 VM IP가 바로 보이지 않음

- `qemu-guest-agent`가 설치되어 있고 실행 중인지 확인합니다.
- Proxmox VM `Summary` 또는 `Agent` 상태를 확인합니다.

### P1000이 게스트에서 보이지 않음

- Proxmox 호스트에서 `lspci -nn | grep -i nvidia` 결과를 먼저 확인합니다.
- VM `Hardware` 탭에 VGA 장치와 오디오 장치가 모두 추가됐는지 확인합니다.
- `Machine: q35`, `BIOS: OVMF (UEFI)` 조합인지 다시 확인합니다.
- 필요 시 VM 전원을 완전히 끄고 다시 시작한 뒤 `lspci -nn | grep -i nvidia`를 재확인합니다.

### GPU 연결 후 noVNC 화면이 검게 보임

- 초기 설치 중이면 `Display: Default`를 유지한 상태에서 설정을 마칩니다.
- GPU 드라이버/출력 검증 후 `Display: none`으로 바꿀지 결정합니다.
- 실제 화면 출력은 P1000에 연결한 모니터 또는 별도 원격 데스크톱 도구 기준으로 확인합니다.

### XRDP의 XFCE 정보 창에서 GPU가 llvmpipe로 보임

- `nvidia-smi`가 `Quadro P1000`을 표시하면 패스스루와 NVIDIA 드라이버 로드는
  성공한 상태로 봅니다.
- XRDP/XFCE 세션은 물리 GPU 출력 세션이 아니라 가상 Xorg 세션이므로
  `llvmpipe` 소프트웨어 렌더러로 표시될 수 있습니다.
- 드라이버 연결 상태는 아래 명령으로 확인합니다.

```bash
nvidia-smi
lspci -nnk | grep -A3 -i nvidia
lsmod | grep nvidia
```

- GUI 앱에서 P1000 가속이 반드시 필요하면 XRDP 기본 세션만으로 판단하지 말고
  물리 모니터 출력, 별도 Xorg 설정, VirtualGL 같은 GPU 오프로딩 구성을 별도로
  검토합니다.

### XRDP에서도 P1000 가속을 쓰고 싶음

- Ubuntu의 기본 `xrdp`/`xorgxrdp` 조합은 관리용 원격 GUI로 쓰고, GPU 연산은
  `nvidia-smi`와 CUDA/컨테이너 작업 기준으로 검증하는 구성을 권장합니다.
- XRDP 세션 자체의 OpenGL 렌더러를 NVIDIA로 바꾸는 구성은 가능 사례가 있지만
  일반 설치 절차로 안정화되어 있지 않습니다. `xorgxrdp`의 GLAMOR/NVIDIA 관련
  빌드, Xorg 권한, 드라이버 버전, 세션 시작 방식이 함께 맞아야 합니다.
- 안정적인 GPU 가속 GUI가 목적이면 아래 대안을 먼저 검토합니다.

```text
권장 1: P1000 물리 출력 + 로컬 Xorg 세션 + 원격 화면 도구
권장 2: VirtualGL/TurboVNC로 GPU 렌더링 앱만 오프로딩
권장 3: NoMachine 같은 GPU 가속 친화 원격 데스크톱 도구
비권장 기본값: 운영 기준 VM에서 xrdp/xorgxrdp를 직접 빌드해 NVIDIA 가속 적용
```

## 참고

- [Proxmox Installation](../proxmox/installation.md)
- [Proxmox DNS And Hostname Guide](../proxmox/dns-and-hostname-guide.md)
