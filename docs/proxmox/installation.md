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
- Bridge uplink NIC: 예) `nic0 - 00:2b:67:55:01:fc (e1000e)`

주의:

- 설치 화면의 `Hostname (FQDN)`에는 short hostname이 아니라 FQDN을 입력합니다.
- 운영상 `hostname`은 `proxmox`, `hostname -f`는
  `proxmox.internal.semtl.synology.me`가 되도록 맞춥니다.
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
2. 라이선스 화면 확인 후 진행
3. 설치 대상 디스크 선택
4. 국가/시간대/키보드 설정
5. 관리자 계정과 메일 주소 설정
6. 네트워크 정보 입력
7. 설치 완료 후 재부팅

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

- Management Interface: `nic0 - 00:2b:67:55:01:fc (e1000e)`
- Hostname (FQDN): `proxmox.internal.semtl.synology.me`
- IP Address (CIDR): `192.168.0.254`
- CIDR: `24`
- Gateway: `192.168.0.1`
- DNS Server: `192.168.0.2`

입력 원칙:

- 설치 단계부터 FQDN을 정확히 넣습니다.
- 설치 화면상 NIC 이름은 `nic0`처럼 보일 수 있으며, 설치 후 Linux 내부
  인터페이스 이름은 `enp3s0` 등으로 다르게 보일 수 있습니다.
- 관리 인터페이스는 이후 `vmbr0` 브리지의 uplink가 될 NIC를 선택합니다.
- NIC가 여러 개면 실제 스위치에 연결된 포트를 미리 식별한 후 진행합니다.

## 3. 첫 부팅 후 접속

설치 완료 후 재부팅되면 콘솔 또는 다른 관리 PC에서 Web UI 접속을 확인합니다.

- Web UI: `https://192.168.0.254:8006`
- 권장 URL: `https://proxmox.internal.semtl.synology.me:8006`
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
- `hostname -f` 결과가 `proxmox.internal.semtl.synology.me`
- 관리 IP가 `vmbr0`에 설정됨
- default route가 `192.168.0.1`

`/etc/hosts` 예시:

```text
127.0.0.1 localhost.localdomain localhost
192.168.0.254 proxmox.internal.semtl.synology.me proxmox

# The following lines are desirable for IPv6 capable hosts

::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
ff02::3 ip6-allhosts
```

`/etc/network/interfaces` 예시:

```text
auto lo
iface lo inet loopback

iface nic0 inet manual

auto vmbr0
iface vmbr0 inet static
        address 192.168.0.254/24
        gateway 192.168.0.1
        bridge-ports nic0
        bridge-stp off
        bridge-fd 0


source /etc/network/interfaces.d/*
```

## 5. DNS/hostname 보정

설치 후 이름 해석이 기대와 다르면 먼저 현재 상태를 점검합니다.

```bash
hostnamectl status
nslookup proxmox.internal.semtl.synology.me
getent hosts proxmox.internal.semtl.synology.me
```

현재 설정이 정상이라면 이 단계는 건너뜁니다.
문제가 있을 때만 아래 순서로 보정합니다.

### 5-1. hostname 보정

```bash
hostnamectl set-hostname proxmox
```

이후 `/etc/hosts`를 아래 형식으로 맞춥니다.

```text
127.0.0.1 localhost.localdomain localhost
192.168.0.254 proxmox.internal.semtl.synology.me proxmox
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
nslookup proxmox.internal.semtl.synology.me
ping -c 3 192.168.0.1
ping -c 3 google.com
```

상세 원칙은 [DNS/Hostname 가이드](./dns-and-hostname-guide.md)를 따릅니다.

## 6. 패키지 저장소와 시스템 업데이트

설치 직후 패키지 저장소 설정과 시스템 업데이트는 Proxmox Web UI에서
진행합니다.

Web UI 경로:

1. 노드 선택
1. `Updates`
1. `Repositories`
1. `pve-enterprise` 선택 후 `Disable`
1. `ceph enterprise` 저장소가 있으면 함께 `Disable`
1. `Add` -> `No-Subscription`
1. 필요 시 `Add` -> `Ceph no-subscription`
1. 다시 `Updates` 탭으로 이동
1. `Refresh`
1. `Upgrade`

기업 구독이 없는 환경에서는 `pve-enterprise` 저장소를 비활성화하고
`pve-no-subscription` 저장소를 사용합니다. Ceph 관련 저장소가 기본 생성된
환경이면 `enterprise`는 비활성화하고 `no-subscription`으로 맞춥니다.

확인 기준:

- `pve-enterprise`가 비활성화 상태
- `ceph enterprise` 저장소가 있으면 비활성화 상태
- `pve-no-subscription` 저장소가 활성화 상태
- `ceph no-subscription` 저장소가 있으면 활성화 상태
- Debian 기본 저장소(`debian`, `security`)가 활성화 상태
- `Updates` 목록이 정상 조회됨

업데이트 후 조치:

1. 커널 또는 주요 패키지 업데이트가 있으면 재부팅
1. 재부팅 후 다시 Web UI 로그인
1. `Updates` 탭에서 잔여 업데이트 확인
1. 노드 상태와 서비스 정상 여부 확인

주의:

- 운영 정책상 `no-subscription` 저장소 사용 여부는 조직 기준을 따릅니다.
- 커널 업데이트가 포함되면 재부팅까지 완료해야 반영 상태를 정확히 검증할 수
  있습니다.

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

SSH 사용이 필요하면 Web UI에서 서비스가 활성화된 뒤 상태를 다시 확인합니다.

```bash
systemctl status ssh
ss -tulpen | grep ':22'
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

- Web UI 접속 가능: `https://proxmox.internal.semtl.synology.me:8006`
- `vmbr0`에 관리 IP 적용 완료
- DNS/FQDN 해석 정상
- 시스템 업데이트 완료
- 재부팅 후에도 동일 상태 유지

## 9. 운영자 계정 및 Proxmox 관리자 계정 생성

설치 검증이 끝나면 `root`만 계속 사용하지 않도록 Linux 운영자 계정과
Proxmox 관리자 계정을 분리해 생성합니다.

### 9-1. `sudo` 설치 및 `semtl` 계정 생성

기본 설치 환경에 `sudo`가 없을 수 있으므로 먼저 설치합니다.

```bash
apt update
apt install -y sudo
adduser semtl
usermod -aG sudo semtl
id semtl
groups semtl
```

확인 기준:

- `semtl` 계정이 생성됨
- `sudo` 그룹에 `semtl`이 포함됨

필요 시 확인:

```bash
su - semtl
sudo whoami
```

정상 결과는 `root`입니다.

### 9-2. `root` 비밀번호 변경

설치 중 설정한 `root` 비밀번호를 계속 사용하지 않고 초기 검증 후 한 번 더
변경합니다.

```bash
passwd root
```

운영 메모:

- `root`와 `semtl` 계정의 비밀번호를 동일하게 사용하지 않습니다.
- 비밀번호 변경 후 SSH 로그인과 Web UI 로그인 모두 재확인합니다.

### 9-3. Proxmox 관리자 계정 `admin@pve` 생성

Proxmox Web UI 전용 관리자 계정은 Linux 계정과 별도로 `pve` realm에
생성합니다.

```bash
pveum user add admin@pve --password 'StrongPassword123!'
pveum aclmod / -user admin@pve -role Administrator
pveum user list
pveum acl list
```

확인 기준:

- `admin@pve` 사용자가 생성됨
- `/` 경로에 `Administrator` 역할이 부여됨
- Web UI에서 `admin@pve`로 로그인 가능

운영 메모:

- `semtl`은 OS 수준 작업용 계정
- `admin@pve`는 Proxmox Web UI/API 관리용 계정
- 운영 환경에서는 예시 비밀번호 대신 충분히 강한 비밀번호로 교체합니다.

## 다음 작업

- 추가 디스크와 Kubernetes 사설망 구성은
  [스토리지/네트워크 확장 가이드](./storage-and-network-expansion.md) 참고
- 백업 서버가 필요하면 [PBS 설치](../pbs/installation.md) 진행
- 운영 기준 정리는 [운영 가이드](./operation-guide.md) 참고

## 참고

- Proxmox VE Downloads:
  `https://www.proxmox.com/en/downloads/proxmox-virtual-environment`
- Proxmox VE Admin Guide:
  `https://pve.proxmox.com/pve-docs/pve-admin-guide.html`
- Proxmox Package Repositories:
  `https://pve.proxmox.com/wiki/Package_Repositories`
