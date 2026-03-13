# Proxmox Backup Server Installation

## 개요

이 문서는 Proxmox VE 환경에서 Proxmox Backup Server(PBS)를 별도 VM으로
설치하고, NAS NFS를 백업 저장소로 연결하는 절차를 정리합니다.

## 아키텍처와 버전 기준

- 권장 구조: `Proxmox VM(PBS)` + `NAS NFS(Datastore)`
- 권장 배치: `PBS`는 `Kubernetes` 밖(독립 VM)에서 운영
- 버전 기준: `Proxmox VE 9.x` 환경은 `PBS 4.x` 사용

## 네이밍 및 DNS 기준

- 내부 전용 이름보다 실제 관리 중인 도메인 우선
- 이 환경에서는 `*.semtl.synology.me` 체계를 사용
- PBS short hostname 권장: `pbs`
- PBS 권장 FQDN: `pbs.semtl.synology.me`
- PBS 관리 IP 예시: `192.168.0.253`
- Synology DNS Server IP 예시: `192.168.0.2`
- Gateway 예시: `192.168.0.1`

참고:

- 설치 자체는 짧은 이름(`vm-pbs`)만으로도 진행될 수 있습니다.
- 다만 내부 DNS, 인증서, 메일 알림, 자기 자신에 대한 이름 해석까지
  고려하면 PBS에는 FQDN을 맞추는 편이 안정적입니다.
- 운영 정합성은 `hostname`은 short hostname, `hostname -f`는 FQDN이
  되도록 맞추는 구성을 우선 권장합니다.
- `.local`은 mDNS 충돌 여지가 있으므로 기본 선택지로 두지 않습니다.

## 사전 조건

- Proxmox VE에서 PBS용 VM 생성 권한
- PBS ISO 이미지 다운로드 (`https://www.proxmox.com/en/downloads`)
- Synology 측 DNS/NFS 사전 준비
  ([시놀로지 설치 가이드](../synology/installation.md) 참고)
- PBS 고정 IP 및 FQDN 계획

예시 NFS Export:
`192.168.0.2:/volume2/lab-data`

예시 PBS IP:
`192.168.0.253`

예시 FQDN:
`pbs.semtl.synology.me`

사전 준비 상세:
[시놀로지 설치 가이드](../synology/installation.md)

## 1) PBS VM 생성 (Proxmox)

Proxmox Web UI에서 `Create VM`을 실행합니다.

### General

- `VM ID`: 예) `900`
- `Name`: 예) `vm-pbs`

### OS

- `ISO Image`: `proxmox-backup-server_4.x-x.iso`
- `Guest OS`: `Linux`

### System

- `Machine`: `q35`
- `BIOS`: `OVMF (UEFI)` 또는 기본값
- `SCSI Controller`: `VirtIO SCSI single`

### Disk (OS 디스크)

- `Bus/Device`: `SCSI`
- `Disk size`: `32GB ~ 64GB`
- `Cache`: `writethrough` (권장)
- `Discard`: `on`
- `SSD emulation`: `on`
- `IO thread`: `on`

### CPU / Memory

- 기본 권장: `2 vCPU`, `4GB RAM`
- 리소스 여유 시: `4 vCPU`, `8GB RAM`까지 확장

### Network

- `Bridge`: `vmbr0`
- `Model`: `VirtIO`

## 2) PBS ISO 설치

VM 콘솔에서 부팅 후 설치를 진행합니다.

1. 부트 메뉴에서 `Install Proxmox Backup Server (Graphical)` 선택
1. 디스크 선택 화면에서 PBS OS 디스크(`/dev/sda`) 선택
1. `Location / Timezone / Keyboard` 설정
1. `root` 비밀번호 및 `email` 설정
1. 네트워크 설정
1. 설치 완료 후 재부팅

권장 Locale:
`Asia/Seoul`, `U.S. English`

예시 네트워크 설정:

- `Hostname`: `pbs.semtl.synology.me`
- `IP`: `192.168.0.253`
- `Gateway`: `192.168.0.1`
- `DNS`: `192.168.0.2`

입력 원칙:

- `Hostname`은 설치 단계부터 FQDN으로 맞추는 것을 권장
- `DNS`는 공유기보다 Synology DNS를 직접 지정
- 짧은 이름을 별칭으로 계속 쓰고 싶다면 설치 후 `/etc/hosts`에서
  `vm-pbs` 같은 alias를 추가

## 3) 설치 후 초기 업데이트

PBS에 SSH 접속 후 업데이트를 수행합니다.

```bash
apt update
apt dist-upgrade -y
```

## 4) 설치 후 hostname/DNS 확인 및 보정

먼저 현재 설정이 의도한 값과 일치하는지 확인합니다.

```bash
hostname
hostname -f
hostnamectl status
cat /etc/hosts
cat /etc/resolv.conf
```

정상 예시:

- `hostname`: `pbs`
- `hostname -f`: `pbs.semtl.synology.me`
- `/etc/hosts`: `192.168.0.253 pbs.semtl.synology.me pbs`
- `/etc/resolv.conf`: `nameserver 192.168.0.2`

### 4-1. hostname 수정

설치 후 `hostname`이 FQDN 전체를 출력하거나 오입력한 경우,
short hostname으로 정리합니다.

```bash
hostnamectl set-hostname pbs
```

`/etc/hosts` 예시:

```text
127.0.0.1 localhost
192.168.0.253 pbs.semtl.synology.me pbs
```

운영 메모:

- `pbs.semtl.synology.me`는 공식 FQDN
- `pbs`는 short hostname
- 추가 별칭이 필요하면 `pbs` 뒤에 `vm-pbs`를 더 둘 수 있음

### 4-2. DNS 수정

설치 중 DNS를 공유기(`192.168.0.1`)로 넣었다면 PBS에서 직접 보정합니다.

`/etc/network/interfaces` 예시:

```text
iface <NIC> inet static
    address 192.168.0.253/24
    gateway 192.168.0.1
    dns-nameservers 192.168.0.2 1.1.1.1
```

즉시 반영 전 임시 확인이 필요하면 `/etc/resolv.conf`도 함께 점검합니다.

```text
nameserver 192.168.0.2
nameserver 1.1.1.1
```

적용 후 검증:

```bash
hostname
hostname -f
nslookup pbs.semtl.synology.me
nslookup google.com
ping -c 3 google.com
```

권장 기준:

- PBS와 주요 VM은 내부 도메인을 안정적으로 해석하기 위해 Synology DNS를
  직접 바라보도록 설정
- 공유기를 DNS로 둘 수는 있어도, 내부 Zone을 Synology가 관리하는 환경에서는
  직접 지정이 더 단순하고 예측 가능
- DNS/hostname 운영 기준 상세:
  [DNS/Hostname 가이드](./dns-and-hostname-guide.md)

## 5) PBS Web UI 접속 확인

PBS는 설치 후 브라우저에서 관리합니다.

- URL: `https://pbs.semtl.synology.me:8007`
- 또는 `https://192.168.0.253:8007`
- Username: `root@pam`
- Password: 설치 시 설정한 `root` 비밀번호

CLI 점검:

```bash
systemctl status proxmox-backup-proxy
ss -tulpen | rg 8007
```

## 6) PBS 로컬 사용자 ACL 예시

PBS 로컬 사용자에 관리자 권한을 부여할 때는 `--userid`가 아니라
`--auth-id`를 사용합니다.

```bash
proxmox-backup-manager user list
proxmox-backup-manager acl update / Admin --auth-id admin@pbs
proxmox-backup-manager acl list
```

주의:

- `--userid` 옵션은 `acl update` 명령에서 허용되지 않습니다.
- 에러 예시:
  `parameter verification failed - 'userid'`

## 7) NAS NFS 연결

PBS에서 NFS 마운트를 구성합니다.

```bash
apt install -y nfs-common
mkdir -p /mnt/pbs-nfs
mount -t nfs 192.168.0.2:/volume2/lab-data /mnt/pbs-nfs
findmnt /mnt/pbs-nfs
```

영구 마운트를 위해 `/etc/fstab`에 아래 내용을 추가합니다.

```fstab
192.168.0.2:/volume2/lab-data /mnt/pbs-nfs nfs vers=3,tcp,noatime,_netdev 0 0
```

```bash
mount -a
findmnt /mnt/pbs-nfs
```

Synology 측 확인 포인트:

- NFS Export 경로가 PBS IP(`192.168.0.253`)에 허용되어 있는지 확인
- Squash/권한 정책이 PBS 쓰기를 막지 않는지 확인

## 8) PBS Datastore 생성

PBS Web UI(`https://<PBS-IP>:8007`)에서 Datastore를 생성합니다.

1. `Datastore` -> `Add`
1. 입력값
1. 생성 후 `Status` 확인

예시 입력값:

- `Name`: `nas-backup`
- `Path`: `/mnt/pbs-nfs`

## 9) Proxmox VE에 PBS 연결

Proxmox Web UI에서 PBS를 Storage로 등록합니다.

1. `Datacenter` -> `Storage` -> `Add` -> `Proxmox Backup Server`
1. 서버/Datastore/계정 입력
1. 등록 후 상태 확인

예시 입력값:

- `ID`: `pbs`
- `Server`: `pbs.semtl.synology.me`
- `Datastore`: `nas-backup`
- `Username`: `root@pam`
- `Password`: PBS `root` 비밀번호

## 10) 백업 작업 생성 및 검증

1. `Datacenter` -> `Backup` -> `Add`
1. 백업 대상 VM/CT 선택
1. 스케줄 설정 후 저장
1. 수동 백업 1회 실행

검증 체크리스트:

- PBS UI 접속 가능 (`https://pbs.semtl.synology.me:8007`)
- `hostname` 결과가 `pbs`
- `hostname -f` 결과가 `pbs.semtl.synology.me`
- `nslookup pbs.semtl.synology.me` 결과가 `192.168.0.253`
- `nslookup google.com` 정상 응답
- NFS 마운트 유지 (`findmnt /mnt/pbs-nfs`)
- Datastore 상태 정상
- Proxmox에서 PBS Storage 접근 가능
- 테스트 백업 성공 및 복구 가능

## 트러블슈팅

### 내부 DNS가 안 풀리거나 외부 조회가 느림

- 확인: PBS의 DNS가 `192.168.0.2`를 우선 참조하는지 확인
- 확인: Synology `DNS Server > 해상도`에서 전달자가 `8.8.8.8`,
  `1.1.1.1`로 설정되었는지 확인
- 확인: 공유기 DHCP가 Synology DNS를 배포하는지 확인
- 조치: Synology 전달자에 공유기 IP(`192.168.0.1`)를 넣지 않음

### PBS 설치 후 DNS를 잘못 입력함

- 증상: `pbs.semtl.synology.me` 조회 실패, GUI 접속은 IP로만 가능
- 원인: 설치 중 `DNS Server`를 공유기로 입력
- 조치: `/etc/network/interfaces`와 `/etc/resolv.conf`를 점검하여
  `192.168.0.2`로 보정 후 재검증

### FQDN/hostname 불일치

- 확인: `hostname`, `hostname -f`, `/etc/hosts`
- 조치: `hostnamectl set-hostname pbs`
- 조치: `/etc/hosts`에 `192.168.0.253 pbs.semtl.synology.me pbs` 반영

### PBS ACL 명령 옵션 오류

- 증상: `parameter verification failed - 'userid'`
- 원인: `proxmox-backup-manager acl update`에 `--userid` 사용
- 조치: `--auth-id`로 변경

```bash
proxmox-backup-manager acl update / Admin --auth-id admin@pbs
```

### NFS 마운트 실패

- 확인: `showmount -e <NAS_IP>`
- 확인: NAS NFS 권한/Export 경로/방화벽
- 조치: `/etc/fstab` 옵션 재검토 (`vers=3,tcp,noatime,_netdev`)

### PBS UI 접속 실패 (`:8007`)

- 확인: 브라우저 주소가 `https://`인지 확인
- 확인: PBS IP/Gateway/DNS
- 확인: `systemctl status proxmox-backup-proxy`
- 확인: `ss -tulpen | rg 8007`
- 조치: 네트워크 경로 및 방화벽 정책 수정

### Proxmox에서 PBS 인증 실패

- 확인: `root@pam` 계정/비밀번호
- 확인: PBS 시간 동기화 상태
- 조치: 계정 정보 재입력 또는 API Token 방식으로 전환

## 참고

- Proxmox 다운로드: `https://www.proxmox.com/en/downloads`
- [시놀로지 설치 가이드](../synology/installation.md)
- [Proxmox 운영 가이드](./operation-guide.md)
