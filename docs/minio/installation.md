# MinIO Installation

## 개요

Ubuntu 22.04 VM에서 OS 설치를 먼저 완료한 뒤, Proxmox에서 `1TB` 데이터 디스크를 추가하고
`/data/minio` 경로를 사용해 MinIO를 설치하는 절차입니다.

## 사전 조건

- OS: `Ubuntu 22.04 LTS`
- MinIO VM 준비 (OS만 설치된 상태)
- 초기 H/W 구성
  - OS Disk: `40GB`
  - Data Disk: 없음
- MinIO 설치 전 확장 H/W 구성
  - Data Disk: `1TB` 추가
- 내부 DNS 또는 고정 IP 확보

### Proxmox VM H/W 참고 이미지

아래 이미지는 Proxmox `Hardware` 탭 기준의 MinIO VM 구성 예시입니다.

![Proxmox VM Hardware - MinIO](../assets/images/minio/proxmox-vm-hw-minio-v1.png)

캡션: OS 설치 후 Proxmox에서 `1TB` 데이터 디스크를 추가하고,
MinIO 데이터 경로를 `/data/minio`로 사용. 기본 VM은 `2 vCPU`, `4GB ~ 6GB RAM`,
`q35`, `OVMF (UEFI)`, OS Disk `40GB`, `vmbr0` 기준

## 네트워크 기준

- `net0` 단일 NIC 사용 (`192.168.0.x`)
- 예시 VM IP: `192.168.0.171`

### DNS/hostname 기준

MinIO VM을 DHCP로 운영하는 경우 `/etc/hosts`의 `127.0.1.1` 패턴을
유지해도 됩니다.

예시:

```text
127.0.0.1 localhost
127.0.1.1 minio.internal.semtl.synology.me vm-minio
```

검증 포인트:

- `hostname` -> `vm-minio`
- `hostname -f` -> `minio.internal.semtl.synology.me`
- `getent hosts minio.internal.semtl.synology.me` -> `127.0.1.1 ...`
- MinIO VM 자신에서 `nslookup minio.internal.semtl.synology.me` -> `127.0.0.1`
- 다른 PC에서 `nslookup minio.internal.semtl.synology.me` -> DHCP로 받은 실제 IP

중요:

- MinIO VM 자신에서 `nslookup` 결과가 `127.0.0.1`로 보이는 것은 의도한 동작입니다.
- 다른 PC에서 `nslookup` 결과가 `127.0.0.1` 또는 `127.0.1.1`이면 비정상입니다.
- OIDC, Reverse Proxy, 외부 endpoint 검증은 반드시 다른 PC 기준 DNS가 반환하는
  실제 IP로 확인합니다.
- 상세 기준은 `../proxmox/dns-and-hostname-guide.md`를 따릅니다.

## 1. OS 설치 후 1TB 디스크 추가

### 1.1 Proxmox에서 1TB 디스크 추가

- MinIO VM 정지
- `Hardware > Add > Hard Disk`에서 `1TB` 디스크 추가
- VM 기동 후 OS에서 새 디스크 인식 확인 (`/dev/sdb` 예시)

### 1.2 OS에서 데이터 디스크 마운트

```bash
# 블록 디바이스와 파일시스템 타입 확인
lsblk -f

# XFS 유틸리티 설치
sudo apt update && sudo apt -y install xfsprogs

# 신규 데이터 디스크(/dev/sdb)를 XFS로 포맷
sudo mkfs.xfs -f /dev/sdb

# 마운트 포인트 생성
sudo mkdir -p /data

# 데이터 디스크를 /data에 1회 마운트
sudo mount /dev/sdb /data

# /dev/sdb의 UUID 조회
UUID=$(sudo blkid -s UUID -o value /dev/sdb)

# UUID 조회 실패 시 중단
[ -n "$UUID" ] || { echo "UUID 조회 실패: /dev/sdb 확인 필요"; exit 1; }

# 재부팅 후에도 자동 마운트되도록 /etc/fstab 등록
echo "UUID=$UUID /data xfs defaults,noatime 0 0" | sudo tee -a /etc/fstab

# /etc/fstab 기준으로 마운트 재검증
sudo mount -a

# /data 마운트 상태/용량 확인
df -h /data
```

## 2. MinIO 설치 (/data/minio 사용)

### 2.1 기본 점검

```bash
# 호스트명/OS 정보 확인
hostnamectl

# 시간 동기화 상태 확인
timedatectl

# 패키지 메타데이터 갱신 및 보안 업데이트 적용
sudo apt update && sudo apt -y upgrade
```

### 2.2 MinIO 바이너리 설치

```bash
# 설치 버전 고정(예시: 운영 표준 버전으로 변경해 사용)
MINIO_VERSION="RELEASE.2025-09-07T16-13-09Z"
MC_VERSION="RELEASE.2025-08-13T08-35-41Z"

# minio 서비스 계정 생성(이미 있으면 무시)
sudo useradd --system --home /var/lib/minio --shell /sbin/nologin minio || true

# 실행 경로/설정 경로/데이터 경로 생성
sudo mkdir -p /usr/local/bin /etc/minio /var/lib/minio /data/minio

# 데이터 경로 소유권을 minio 계정으로 설정
sudo chown -R minio:minio /var/lib/minio /data/minio

# MinIO 서버 바이너리 다운로드(버전 고정)
curl -fsSL -o minio \
  "https://dl.min.io/server/minio/release/linux-amd64/archive/minio.${MINIO_VERSION}"
# 실행 권한 부여
chmod +x minio
# 실행 파일 경로로 이동
sudo mv minio /usr/local/bin/minio

# MinIO Client(mc) 다운로드(버전 고정)
curl -fsSL -o mc \
  "https://dl.min.io/client/mc/release/linux-amd64/archive/mc.${MC_VERSION}"
# 실행 권한 부여
chmod +x mc
# 실행 파일 경로로 이동
sudo mv mc /usr/local/bin/mc

# 설치 버전 확인
/usr/local/bin/minio --version
/usr/local/bin/mc --version
```

### 2.3 환경 변수 설정

`/etc/default/minio`:

```bash
# MinIO 환경 변수 파일 생성/덮어쓰기
sudo tee /etc/default/minio >/dev/null <<'ENV'
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=패스워드
MINIO_VOLUMES="/data/minio"
MINIO_OPTS="--address :9000 --console-address :9001"
ENV
```

### 2.4 systemd 서비스 등록

```bash
# systemd 서비스 유닛 파일 생성/덮어쓰기
sudo tee /etc/systemd/system/minio.service >/dev/null <<'SERVICE'
[Unit]
Description=MinIO
Wants=network-online.target
After=network-online.target

[Service]
User=minio
Group=minio
EnvironmentFile=/etc/default/minio
ExecStart=/usr/local/bin/minio server $MINIO_VOLUMES $MINIO_OPTS
Restart=always
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SERVICE

# systemd 유닛 캐시 갱신
sudo systemctl daemon-reload
# 부팅 시 자동 시작 등록 및 즉시 기동
sudo systemctl enable --now minio
# 서비스 상태 확인
sudo systemctl status minio --no-pager
```

### 2.5 초기 접속 확인

```bash
# MinIO liveness 엔드포인트 응답 확인
curl -I http://127.0.0.1:9000/minio/health/live

# 로컬 MinIO 서버를 mc 별칭으로 등록
mc alias set local http://127.0.0.1:9000 admin '패스워드'

# MinIO 서버 정보 조회
mc admin info local
```

## 검증 기준

- `1TB` 디스크가 `/data`로 정상 마운트됨
- `minio.service`가 `active (running)` 상태
- `mc admin info local` 응답 정상
- MinIO 데이터 경로가 `/data/minio`로 설정됨
- `minio --version`, `mc --version`이 의도한 고정 버전과 일치함

## 3. 설치 직후 정리 후 스냅샷

스냅샷은 반드시 불필요 파일(찌꺼기) 정리 후 생성합니다.

### 3.1 불필요 파일 정리

```bash
# /tmp 전체 삭제
sudo rm -rf /tmp/*

# /var/tmp 전체 삭제
sudo rm -rf /var/tmp/*

# 미사용 패키지 정리
sudo apt autoremove -y

# APT 캐시 정리
sudo apt clean

# journal 로그 전체 정리
sudo journalctl --vacuum-time=1s

# 현재 사용자 bash 히스토리 비우기
cat /dev/null > ~/.bash_history && history -c
```

### 3.2 Proxmox 스냅샷 생성

- Proxmox에서 MinIO VM 선택
- `Snapshots > Take Snapshot` 실행
- 이름 예시: `minio-install-clean-v1`
- 설명 예시:

  ```text
  [설치]
  - 1TB disk(xfs) : /data 마운트
  - minio 서비스 계정 생성
  - MINIO_VOLUMES="/data/minio"
  - minio : RELEASE.2025-09-07T16-13-09Z
  - mc : RELEASE.2025-08-13T08-35-41Z
  - id : admin
  - pw : 패스워드(설치 시 지정값)
  ```

- `Include RAM`은 비활성화(권장)
