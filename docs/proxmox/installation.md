# Proxmox Installation

## 개요

이 문서는 단일 노드 기준으로 `Proxmox VE`를 베어메탈 서버에 설치하고,
초기 네트워크와 관리 접속까지 검증하는 절차를 정리합니다.

이 저장소의 기준 토폴로지는 아래와 같습니다.

- Proxmox 관리 IP 예시: `192.168.0.254`
- Gateway 예시: `192.168.0.1`
- 내부 DNS 예시: `192.168.0.2`
- 권장 short hostname: `proxmox`
- 권장 FQDN: `proxmox.internal.semtl.synology.me`

운영 기준과 후속 VM 배치 원칙은 [개요](./overview.md),
DNS/hostname 상세 기준은 [DNS/Hostname 가이드](./dns-and-hostname-guide.md)를
함께 참고합니다.

## 사전 조건

- x86_64 서버 1대
- CPU 가상화 지원 활성화(`Intel VT-x` 또는 `AMD-V`)
- 메모리 `16GB` 이상 권장
- OS 디스크 `SSD 240GB` 이상 권장
- 관리망 연결용 NIC 1개 이상
- `Proxmox VE 9.x` ISO 이미지
  (`https://www.proxmox.com/en/downloads/proxmox-virtual-environment`)
- 부팅용 USB 또는 원격 콘솔(iDRAC/iLO/IPMI)
- 고정 IP, Gateway, DNS, hostname/FQDN 사전 확정

설치 전 BIOS/UEFI 권장 확인 항목:

- `Virtualization Technology` 활성화
- 가능하면 `UEFI` 부팅 사용
- RAID HBA 사용 시 디스크 인식 상태 확인
- 설치 대상 디스크 외 불필요한 USB 저장장치 분리

## 설치 전 계획

최소한 아래 값은 설치 전에 확정합니다.

- Hostname: `proxmox`
- FQDN: `proxmox.internal.semtl.synology.me`
- Management IP: `192.168.0.254/24`
- Gateway: `192.168.0.1`
- DNS: `192.168.0.2`
- Bridge uplink NIC: 예) `enp3s0`

주의:

- 설치 화면의 `Hostname (FQDN)`에는 short hostname이 아니라 FQDN을 입력합니다.
- 운영상 `hostname`은 `proxmox`, `hostname -f`는
  `proxmox.semtl.synology.me`가 되도록 맞춥니다.
- DNS를 공유기가 아니라 내부 DNS 서버(`192.168.0.2`)로 직접 지정하는 구성을
  권장합니다.

## 1. 설치 미디어 준비

ISO를 다운로드한 뒤 `balenaEtcher`, `Rufus`, `Ventoy` 등으로 USB를 작성합니다.
원격 콘솔이 있으면 가상 미디어로 바로 마운트해도 됩니다.

부팅 확인 포인트:

- 서버가 작성한 ISO/USB로 정상 부팅되는지 확인
- UEFI 모드 사용 시 부팅 항목이 `UEFI: <device>`로 표시되는지 확인

## 2. Proxmox VE 설치 실행

설치 대상 서버를 ISO로 부팅한 뒤 아래 순서로 진행합니다.

1. 부트 메뉴에서 `Install Proxmox VE (Graphical)` 선택
1. 라이선스 화면 확인 후 진행
1. 설치 대상 디스크 선택
1. 국가/시간대/키보드 설정
1. 관리자 계정과 메일 주소 설정
1. 네트워크 정보 입력
1. 설치 완료 후 재부팅

### 디스크 선택 기준

- 단일 SSD 1개면 기본값으로 시작 가능
- 운영 환경에서 디스크 2개 이상이면 `ZFS RAID1` 검토
- 실습/랩 환경이면 단일 디스크 `ext4`도 가능

권장 예시:

- Lab/소형 환경: 단일 SSD
- 운영 환경: 동일 용량 SSD 2개, 미러 구성

### 지역/키보드 권장값

- Country: `Korea, Republic of`
- Time zone: `Asia/Seoul`
- Keyboard Layout: `us` 또는 실제 운영 키보드 레이아웃

### 관리자 계정 입력

- 설치 과정에서 Linux `root` 비밀번호를 설정합니다.
- 알림 메일을 받을 주소를 함께 입력합니다.

주의:

- `root@pam`은 초기 관리 계정이므로 강한 비밀번호를 사용합니다.
- 외부 메일 송신 구성이 없더라도 메일 주소는 운영 담당자 기준으로 입력합니다.

### 네트워크 입력 예시

- Management Interface: `enp3s0`
- Hostname (FQDN): `proxmox.semtl.synology.me`
- IP Address (CIDR): `192.168.0.254/24`
- Gateway: `192.168.0.1`
- DNS Server: `192.168.0.2`

입력 원칙:

- 설치 단계부터 FQDN을 정확히 넣습니다.
- 관리 인터페이스는 이후 `vmbr0` 브리지의 uplink가 될 NIC를 선택합니다.
- NIC가 여러 개면 실제 스위치에 연결된 포트를 미리 식별한 후 진행합니다.

## 3. 첫 부팅 후 접속

설치 완료 후 재부팅되면 콘솔 또는 다른 관리 PC에서 Web UI 접속을 확인합니다.

- Web UI: `https://192.168.0.254:8006`
- 권장 URL: `https://proxmox.semtl.synology.me:8006`
- 사용자: `root@pam`
- 비밀번호: 설치 중 설정한 `root` 비밀번호

TLS 경고는 자체 서명 인증서 때문에 발생할 수 있습니다. 설치 직후에는 경고를
확인 후 접속하고, 이후 내부 PKI 또는 리버스 프록시 정책에 따라 별도 정리합니다.

## 4. 설치 직후 기본 점검

콘솔 또는 SSH로 접속한 뒤 아래 항목을 먼저 확인합니다.

```bash
hostname
hostname -f
ip -br addr
ip route
cat /etc/hosts
cat /etc/network/interfaces
```

정상 기준:

- `hostname` 결과가 `proxmox`
- `hostname -f` 결과가 `proxmox.semtl.synology.me`
- 관리 IP가 `vmbr0`에 설정됨
- default route가 `192.168.0.1`

`/etc/hosts` 예시:

```text
127.0.0.1 localhost.localdomain localhost
192.168.0.254 proxmox.semtl.synology.me proxmox
```

`/etc/network/interfaces` 예시:

```text
auto lo
iface lo inet loopback

iface enp3s0 inet manual

auto vmbr0
iface vmbr0 inet static
    address 192.168.0.254/24
    gateway 192.168.0.1
    bridge-ports enp3s0
    bridge-stp off
    bridge-fd 0
    dns-nameservers 192.168.0.2
```

## 5. DNS/hostname 보정

설치 후 이름 해석이 기대와 다르면 먼저 현재 상태를 점검합니다.

```bash
hostnamectl status
nslookup proxmox.semtl.synology.me
getent hosts proxmox.semtl.synology.me
```

문제가 있으면 아래 순서로 보정합니다.

### 5-1. hostname 보정

```bash
hostnamectl set-hostname proxmox
```

이후 `/etc/hosts`를 아래 형식으로 맞춥니다.

```text
127.0.0.1 localhost.localdomain localhost
192.168.0.254 proxmox.semtl.synology.me proxmox
```

### 5-2. DNS 보정

`/etc/network/interfaces`의 `dns-nameservers`를 내부 DNS 기준으로 맞춥니다.

```text
dns-nameservers 192.168.0.2 1.1.1.1
```

적용 후 검증:

```bash
ifreload -a
hostname
hostname -f
nslookup proxmox.semtl.synology.me
ping -c 3 192.168.0.1
ping -c 3 google.com
```

상세 원칙은 [DNS/Hostname 가이드](./dns-and-hostname-guide.md)를 따릅니다.

## 6. 패키지 저장소와 시스템 업데이트

설치 직후 저장소 상태를 확인하고 업데이트를 적용합니다.

```bash
apt update
apt full-upgrade -y
```

기업 구독이 없는 환경에서는 `pve-enterprise` 저장소를 비활성화하고
`pve-no-subscription` 저장소를 사용합니다.

확인 파일:

- `/etc/apt/sources.list`
- `/etc/apt/sources.list.d/pve-enterprise.list`

예시:

```bash
sed -i 's/^deb/# deb/' /etc/apt/sources.list.d/pve-enterprise.list
```

`/etc/apt/sources.list` 예시:

```text
deb http://download.proxmox.com/debian/pve trixie pve-no-subscription
deb http://deb.debian.org/debian trixie main contrib
deb http://security.debian.org/debian-security trixie-security main contrib
```

변경 후 다시 업데이트합니다.

```bash
apt update
apt full-upgrade -y
reboot
```

주의:

- 운영 정책상 `no-subscription` 저장소 사용 여부는 조직 기준을 따릅니다.
- 커널 업데이트가 포함되면 재부팅까지 완료해야 반영 상태를 정확히 검증할 수 있습니다.

## 7. 브리지와 노드 상태 확인

Proxmox의 기본 관리 브리지는 일반적으로 `vmbr0`입니다.

CLI 점검:

```bash
brctl show
systemctl status pveproxy
systemctl status pvedaemon
systemctl status pvestatd
```

Web UI 점검:

1. `Datacenter` -> 노드 선택
1. `System` -> `Network`
1. `vmbr0`에 관리 IP가 설정되어 있는지 확인
1. 브리지 포트가 실제 uplink NIC와 일치하는지 확인

검증 기준:

- `vmbr0`가 `active`
- `pveproxy`, `pvedaemon`, `pvestatd`가 `running`
- Web UI 로그인과 노드 요약 페이지 접근이 정상

## 8. SSH 접속 및 기본 운영 설정

SSH 사용이 필요하면 설치 후 상태를 확인합니다.

```bash
systemctl status ssh
ss -tulpen | rg ':22'
```

외부 단말에서 접속 확인:

```bash
ssh root@192.168.0.254
```

운영 권장:

- 초기 설정 후에는 비밀번호 로그인보다 SSH 키 기반 접속을 우선
- 필요 시 `root` 직접 사용을 줄이고 운영자 계정을 별도 생성
- 계정/권한 운영은 [운영 가이드](./operation-guide.md)를 따름

## 설치 검증

아래 명령이 모두 기대한 결과를 주면 초기 설치는 완료로 봅니다.

```bash
hostname
hostname -f
ip -br addr show vmbr0
ip route
pveversion -v
systemctl is-active pveproxy pvedaemon pvestatd
```

최종 확인 항목:

- Web UI 접속 가능: `https://proxmox.semtl.synology.me:8006`
- `vmbr0`에 관리 IP 적용 완료
- DNS/FQDN 해석 정상
- 시스템 업데이트 완료
- 재부팅 후에도 동일 상태 유지

## 다음 작업

- 스토리지 추가 전 디스크 인식 및 파일시스템 전략 확정
- VM/CT 생성 전 브리지, VLAN, IP 대역 계획 확정
- 백업 서버가 필요하면 [PBS 설치](../pbs/installation.md) 진행
- 운영 기준 정리는 [운영 가이드](./operation-guide.md) 참고

## 참고

- Proxmox VE Downloads:
  `https://www.proxmox.com/en/downloads/proxmox-virtual-environment`
- Proxmox VE Admin Guide:
  `https://pve.proxmox.com/pve-docs/pve-admin-guide.html`
- Proxmox Package Repositories:
  `https://pve.proxmox.com/wiki/Package_Repositories`
