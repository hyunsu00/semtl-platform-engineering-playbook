# MinIO Installation

## 개요
Ubuntu 22.04 VM 환경에서 MinIO를 설치하고, 운영 기준에 맞게 디스크를 분리해 초기 구성하는 절차입니다.

## 사전 조건
- OS: `Ubuntu 22.04 LTS`
- MinIO VM 준비
- 데이터 디스크 분리 구성 권장
  - OS: `80~100GB`
  - Data: `400GB+`
- 내부 DNS 또는 고정 IP 확보

## 1. 기본 점검
```bash
hostnamectl
timedatectl
sudo apt update && sudo apt -y upgrade
```

## 2. 데이터 디스크 준비
`/dev/sdb`를 데이터 디스크로 사용하는 예시입니다.

```bash
lsblk -f
df -h
sudo mkfs.ext4 -m 0 /dev/sdb
sudo mkdir -p /data
sudo mount /dev/sdb /data
UUID=$(blkid -s UUID -o value /dev/sdb)
echo "UUID=$UUID /data ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab
sudo mount -a
df -h /data
```

## 3. MinIO 바이너리 설치
```bash
sudo useradd --system --home /var/lib/minio --shell /sbin/nologin minio || true
sudo mkdir -p /usr/local/bin /etc/minio /var/lib/minio /data/minio
sudo chown -R minio:minio /var/lib/minio /data/minio

curl -fsSL -o minio https://dl.min.io/server/minio/release/linux-amd64/minio
chmod +x minio
sudo mv minio /usr/local/bin/minio

curl -fsSL -o mc https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/mc
```

## 4. 환경 변수 설정
`/etc/default/minio`:

```bash
sudo tee /etc/default/minio >/dev/null <<'ENV'
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=replace-with-strong-password
MINIO_VOLUMES="/data/minio"
MINIO_OPTS="--address :9000 --console-address :9001"
ENV
```

## 5. systemd 서비스 등록
```bash
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

sudo systemctl daemon-reload
sudo systemctl enable --now minio
sudo systemctl status minio --no-pager
```

## 6. 초기 접속 확인
```bash
curl -I http://127.0.0.1:9000/minio/health/live
mc alias set local http://127.0.0.1:9000 minioadmin 'replace-with-strong-password'
mc admin info local
```

## 검증 기준
- `minio.service`가 `active (running)` 상태
- `mc admin info local` 응답 정상
- `/data/minio` 경로가 데이터 저장 경로로 사용됨
