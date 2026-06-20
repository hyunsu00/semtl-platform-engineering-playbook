# Raspberry Pi 2 Backup and Restore

## 개요

Raspberry Pi 2의 microSD 카드 장애에 대비해 운영 설정과 애플리케이션 데이터를
로컬 백업 파일로 묶고, 생성된 백업 파일을 NAS에 보관합니다.

백업 목표:

- Mosquitto 계정과 설정 보존
- Node-RED flow, credential, 설정 보존
- Zigbee2MQTT 설정, 장치 DB, coordinator backup 보존
- systemd 서비스 파일과 설치 상태 메타데이터 보존
- 복구 시 재설치 후 데이터만 되돌릴 수 있는 tarball 생성

주의:

- 백업 파일에는 MQTT 비밀번호, Node-RED credential, Zigbee network key가
  포함될 수 있습니다.
- 백업 파일 권한은 `600`으로 유지합니다.
- NAS로 전송한 백업 파일은 일반 공유 폴더가 아니라 운영자만 접근 가능한 위치에
  저장합니다.

## 1. 백업 스크립트 생성

rpi2에서 실행합니다.

```bash
mkdir -p ~/scripts
nano ~/scripts/backup-rpi2-apps.sh
```

스크립트 내용:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

HOSTNAME_SHORT="$(hostname -s)"
TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/backups}"
WORKDIR="$(mktemp -d)"
BACKUP_FILE="${BACKUP_ROOT}/${TIMESTAMP}-${HOSTNAME_SHORT}-apps-backup.tar.gz"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

print_backup_targets() {
  cat << EOF
Backup targets:
  - meta/
  - /etc/mosquitto
  - /etc/systemd/system/zigbee2mqtt-slzb.service
  - /etc/systemd/system/zigbee2mqtt-zbbridge-pro.service
  - /lib/systemd/system/nodered.service
  - /opt/zigbee2mqtt-slzb/data
  - /opt/zigbee2mqtt-zbbridge-pro/data
  - $HOME/.node-red
Excluded:
  - $HOME/.node-red/node_modules
  - $HOME/.node-red/.npm
  - $HOME/.node-red/.cache
EOF
}

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

log "Create backup workspace: $WORKDIR"
mkdir -p "$BACKUP_ROOT"
mkdir -p "$WORKDIR/meta"

log "Collect system metadata"
hostnamectl > "$WORKDIR/meta/hostnamectl.txt" 2>&1 || true
timedatectl > "$WORKDIR/meta/timedatectl.txt" 2>&1 || true
ip addr show > "$WORKDIR/meta/ip-addr.txt" 2>&1 || true
ip route show > "$WORKDIR/meta/ip-route.txt" 2>&1 || true
systemctl list-unit-files --state=enabled \
  > "$WORKDIR/meta/systemd-enabled.txt" 2>&1 || true
systemctl status mosquitto nodered.service \
  zigbee2mqtt-slzb zigbee2mqtt-zbbridge-pro --no-pager \
  > "$WORKDIR/meta/systemd-status.txt" 2>&1 || true
apt-mark showmanual > "$WORKDIR/meta/apt-mark-showmanual.txt" 2>&1 || true
dpkg-query -W > "$WORKDIR/meta/dpkg-query.txt" 2>&1 || true
node -v > "$WORKDIR/meta/node-version.txt" 2>&1 || true
npm -v > "$WORKDIR/meta/npm-version.txt" 2>&1 || true
pnpm -v > "$WORKDIR/meta/pnpm-version.txt" 2>&1 || true
tailscale status > "$WORKDIR/meta/tailscale-status.txt" 2>&1 || true
tailscale ip -4 > "$WORKDIR/meta/tailscale-ipv4.txt" 2>&1 || true

print_backup_targets
log "Create archive: $BACKUP_FILE"
sudo tar \
  --ignore-failed-read \
  --warning=no-file-changed \
  --exclude="$HOME/.node-red/node_modules" \
  --exclude="$HOME/.node-red/.npm" \
  --exclude="$HOME/.node-red/.cache" \
  -czf "$BACKUP_FILE" \
  -C "$WORKDIR" meta \
  /etc/mosquitto \
  /etc/systemd/system/zigbee2mqtt-slzb.service \
  /etc/systemd/system/zigbee2mqtt-zbbridge-pro.service \
  /lib/systemd/system/nodered.service \
  /opt/zigbee2mqtt-slzb/data \
  /opt/zigbee2mqtt-zbbridge-pro/data \
  "$HOME/.node-red"

log "Set archive ownership and permissions"
sudo chown "$USER:$USER" "$BACKUP_FILE"
chmod 600 "$BACKUP_FILE"

log "Create checksum"
BACKUP_BASENAME="$(basename "$BACKUP_FILE")"
(
  cd "$BACKUP_ROOT"
  sha256sum "$BACKUP_BASENAME" > "${BACKUP_BASENAME}.sha256"
)
chmod 600 "${BACKUP_FILE}.sha256"

log "Verify checksum"
(
  cd "$BACKUP_ROOT"
  sha256sum -c "${BACKUP_BASENAME}.sha256"
)

log "Backup complete"
ls -lh "$BACKUP_FILE" "${BACKUP_FILE}.sha256"
```

권한 부여:

```bash
chmod 700 ~/scripts/backup-rpi2-apps.sh
```

## 2. 로컬 백업 생성

```bash
~/scripts/backup-rpi2-apps.sh
```

정상 기준:

- 단계별 `[YYYY-MM-DD HH:MM:SS]` 로그가 표시됨
- `Backup targets`에 백업 포함/제외 경로가 표시됨
- `~/backups/` 아래에 `.tar.gz` 파일 생성
- 같은 경로에 `.sha256` 파일 생성
- 백업 파일 권한이 `600`
- `sha256sum -c` 결과가 `OK`

확인:

```bash
ls -lh ~/backups
cd ~/backups
sha256sum -c ./*.sha256
```

## 3. NAS로 백업 파일 전송

NAS에 FTP 접속 가능한 계정과 저장 경로를 준비합니다. `NAS_FTP_DIR`는 DSM의
실제 경로(`/volume2/...`)가 아니라 FTP 로그인 후 보이는 경로입니다.

FTP 루트 확인:

```bash
curl --user '<NAS_FTP_USER>:<NAS_FTP_PASSWORD>' ftp://<NAS_FTP_HOST>/
```

예를 들어 FTP 접속 시 `nfs` 공유 폴더가 루트에 보이면
`NAS_FTP_DIR="/nfs/device-backups/rpi2"`를 사용합니다.

전송 스크립트 생성:

```bash
nano ~/scripts/upload-rpi2-backup-to-nas.sh
```

스크립트 내용:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

NAS_FTP_USER="${NAS_FTP_USER:-semtl}"
NAS_FTP_HOST="${NAS_FTP_HOST:-192.168.77.2}"
NAS_FTP_DIR="${NAS_FTP_DIR:-/nfs/device-backups/rpi2}"
NAS_FTP_PASSWORD="${NAS_FTP_PASSWORD:-}"
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/backups}"
NETRC_FILE="$(mktemp)"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

cleanup() {
  rm -f "$NETRC_FILE"
}
trap cleanup EXIT

if [ -z "$NAS_FTP_PASSWORD" ]; then
  read -rs -p "NAS FTP password: " NAS_FTP_PASSWORD
  printf '\n'
fi

chmod 600 "$NETRC_FILE"
cat > "$NETRC_FILE" << EOF
machine $NAS_FTP_HOST
login $NAS_FTP_USER
password $NAS_FTP_PASSWORD
EOF

LATEST_BACKUP="$(find "$BACKUP_ROOT" -maxdepth 1 -type f \
  -name '*-rpi2-apps-backup.tar.gz' | sort | tail -n 1)"

if [ -z "$LATEST_BACKUP" ]; then
  echo "No backup file found in $BACKUP_ROOT" >&2
  exit 1
fi

CHECKSUM_FILE="${LATEST_BACKUP}.sha256"

if [ ! -f "$CHECKSUM_FILE" ]; then
  echo "Checksum file not found: $CHECKSUM_FILE" >&2
  exit 1
fi

log "NAS FTP target: ${NAS_FTP_HOST}${NAS_FTP_DIR}"
log "Backup file: $LATEST_BACKUP"
log "Checksum file: $CHECKSUM_FILE"

log "Verify local checksum"
(
  cd "$BACKUP_ROOT"
  sha256sum -c "$(basename "$CHECKSUM_FILE")"
)

log "Upload backup and checksum"
for FILE in "$LATEST_BACKUP" "$CHECKSUM_FILE"; do
  BASENAME="$(basename "$FILE")"
  curl --fail --show-error --ftp-create-dirs \
    --netrc-file "$NETRC_FILE" \
    --upload-file "$FILE" \
    "ftp://${NAS_FTP_HOST}${NAS_FTP_DIR}/${BASENAME}"
done

log "Uploaded files"
ls -lh "$LATEST_BACKUP" "$CHECKSUM_FILE"

log "Upload complete"
```

권한 부여:

```bash
chmod 700 ~/scripts/upload-rpi2-backup-to-nas.sh
```

실행:

```bash
~/scripts/upload-rpi2-backup-to-nas.sh
```

Tailscale IP나 NAS DNS를 사용할 때는 실행 시 `NAS_FTP_HOST`를 지정합니다.

```bash
NAS_FTP_HOST="<NAS_TAILSCALE_IP>" ~/scripts/upload-rpi2-backup-to-nas.sh
```

비밀번호 프롬프트 없이 실행하려면 환경 변수로 넘깁니다. 셸 히스토리에 남을 수
있으므로 일회성 터미널에서만 사용합니다.

```bash
NAS_FTP_PASSWORD='<NAS_FTP_PASSWORD>' ~/scripts/upload-rpi2-backup-to-nas.sh
```

## 4. 복구 전 준비

새 SD 카드에 기본 설치와 앱 설치를 먼저 완료합니다.

필수 선행 문서:

- [Installation](./installation.md)
- [Apps Installation](./apps-installation.md)

복구 전 서비스 중지:

```bash
sudo systemctl stop nodered.service || true
sudo systemctl stop zigbee2mqtt-slzb || true
sudo systemctl stop zigbee2mqtt-zbbridge-pro || true
sudo systemctl stop mosquitto || true
```

## 5. 백업 파일 다운로드

NAS FTP에서 백업 파일만 내려받습니다. 복구 적용은 다음 단계의 별도 스크립트로
실행합니다.

```bash
mkdir -p ~/restore
nano ~/scripts/download-rpi2-backup-from-nas.sh
```

스크립트 내용:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

NAS_FTP_USER="${NAS_FTP_USER:-semtl}"
NAS_FTP_HOST="${NAS_FTP_HOST:-192.168.77.2}"
NAS_FTP_DIR="${NAS_FTP_DIR:-/nfs/device-backups/rpi2}"
NAS_FTP_PASSWORD="${NAS_FTP_PASSWORD:-}"
RESTORE_DIR="${RESTORE_DIR:-$HOME/restore}"
BACKUP_NAME="${BACKUP_NAME:-}"
NETRC_FILE="$(mktemp)"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

cleanup() {
  rm -f "$NETRC_FILE"
}
trap cleanup EXIT

if [ -z "$NAS_FTP_PASSWORD" ]; then
  read -rs -p "NAS FTP password: " NAS_FTP_PASSWORD
  printf '\n'
fi

chmod 600 "$NETRC_FILE"
cat > "$NETRC_FILE" << EOF
machine $NAS_FTP_HOST
login $NAS_FTP_USER
password $NAS_FTP_PASSWORD
EOF

if [ -z "$BACKUP_NAME" ]; then
  log "Find latest backup from NAS FTP directory"
  BACKUP_NAME="$(curl --fail --silent --show-error \
    --netrc-file "$NETRC_FILE" \
    "ftp://${NAS_FTP_HOST}${NAS_FTP_DIR}/" \
    | awk '{print $NF}' \
    | grep -- '-rpi2-apps-backup\.tar\.gz$' \
    | sort \
    | tail -n 1)"
fi

if [ -z "$BACKUP_NAME" ]; then
  echo "No backup file found in ftp://${NAS_FTP_HOST}${NAS_FTP_DIR}/" >&2
  exit 1
fi

mkdir -p "$RESTORE_DIR"
cd "$RESTORE_DIR"

log "Download backup: $BACKUP_NAME"
curl --fail --show-error \
  --netrc-file "$NETRC_FILE" \
  --remote-name \
  "ftp://${NAS_FTP_HOST}${NAS_FTP_DIR}/${BACKUP_NAME}"

log "Download checksum: ${BACKUP_NAME}.sha256"
curl --fail --show-error \
  --netrc-file "$NETRC_FILE" \
  --remote-name \
  "ftp://${NAS_FTP_HOST}${NAS_FTP_DIR}/${BACKUP_NAME}.sha256"

log "Verify checksum"
sha256sum -c "${BACKUP_NAME}.sha256"

log "Download complete"
ls -lh "$BACKUP_NAME" "${BACKUP_NAME}.sha256"
```

권한 부여:

```bash
chmod 700 ~/scripts/download-rpi2-backup-from-nas.sh
```

실행:

```bash
~/scripts/download-rpi2-backup-from-nas.sh
```

특정 백업 파일을 내려받을 때만 `BACKUP_NAME`을 지정합니다.

```bash
BACKUP_NAME="<BACKUP_FILE_NAME>.tar.gz" ~/scripts/download-rpi2-backup-from-nas.sh
```

## 6. 백업 파일 적용

다운로드한 백업 파일을 현재 rpi2에 적용합니다.

```bash
nano ~/scripts/apply-rpi2-backup.sh
```

스크립트 내용:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

RESTORE_DIR="${RESTORE_DIR:-$HOME/restore}"
BACKUP_NAME="${BACKUP_NAME:-}"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

if [ -z "$BACKUP_NAME" ]; then
  BACKUP_NAME="$(find "$RESTORE_DIR" -maxdepth 1 -type f \
    -name '*-rpi2-apps-backup.tar.gz' | sort | tail -n 1)"
fi

if [ -z "$BACKUP_NAME" ]; then
  echo "No backup file found in $RESTORE_DIR" >&2
  exit 1
fi

if [[ "$BACKUP_NAME" != /* ]]; then
  BACKUP_NAME="${RESTORE_DIR}/${BACKUP_NAME}"
fi

CHECKSUM_FILE="${BACKUP_NAME}.sha256"

if [ ! -f "$BACKUP_NAME" ]; then
  echo "Backup file not found: $BACKUP_NAME" >&2
  exit 1
fi

if [ ! -f "$CHECKSUM_FILE" ]; then
  echo "Checksum file not found: $CHECKSUM_FILE" >&2
  exit 1
fi

log "Backup file: $BACKUP_NAME"
log "Checksum file: $CHECKSUM_FILE"

log "Verify checksum"
(
  cd "$(dirname "$BACKUP_NAME")"
  sha256sum -c "$(basename "$CHECKSUM_FILE")"
)

log "Stop services"
sudo systemctl stop nodered.service || true
sudo systemctl stop zigbee2mqtt-slzb || true
sudo systemctl stop zigbee2mqtt-zbbridge-pro || true
sudo systemctl stop mosquitto || true

log "Extract backup"
sudo tar -xzf "$BACKUP_NAME" -C /

log "Fix ownership"
sudo chown -R semtl:semtl /home/semtl/.node-red
sudo chown -R semtl:semtl /opt/zigbee2mqtt-slzb/data
sudo chown -R semtl:semtl /opt/zigbee2mqtt-zbbridge-pro/data

log "Reload systemd"
sudo systemctl daemon-reload

log "Start services"
sudo systemctl start mosquitto
sudo systemctl start nodered.service
sudo systemctl start zigbee2mqtt-slzb
sudo systemctl start zigbee2mqtt-zbbridge-pro

log "Service status"
systemctl is-active mosquitto
systemctl is-active nodered.service
systemctl is-active zigbee2mqtt-slzb
systemctl is-active zigbee2mqtt-zbbridge-pro

log "Restore apply complete"
```

권한 부여:

```bash
chmod 700 ~/scripts/apply-rpi2-backup.sh
```

최신 다운로드 백업을 적용:

```bash
~/scripts/apply-rpi2-backup.sh
```

특정 백업 파일을 적용:

```bash
BACKUP_NAME="<BACKUP_FILE_NAME>.tar.gz" ~/scripts/apply-rpi2-backup.sh
```

## 7. 복구 검증

```bash
systemctl is-active mosquitto
systemctl is-active nodered.service
systemctl is-active zigbee2mqtt-slzb
systemctl is-active zigbee2mqtt-zbbridge-pro
sudo ss -lntp | grep -E ':1883|:1880|:8099|:8100'
```

브라우저에서 확인합니다.

```text
http://192.168.32.11:1880
http://192.168.32.11:8099
http://192.168.32.11:8100
http://100.126.244.46:1880
http://100.126.244.46:8099
http://100.126.244.46:8100
```

정상 기준:

- Mosquitto가 `active`
- Node-RED 에디터와 Dashboard 접속 가능
- 두 Zigbee2MQTT frontend 접속 가능
- 기존 Zigbee 장치 목록이 유지됨
- `bridge/state`가 `online`

MQTT 확인:

```bash
mosquitto_sub -h localhost -u zigbee2mqtt-slzb \
  -P '<SLZB_PASSWORD>' -t 'zigbee2mqtt-slzb/bridge/state' -C 1 -v

mosquitto_sub -h localhost -u zigbee2mqtt-zbbridge-pro \
  -P '<ZBBRIDGE_PASSWORD>' -t 'zigbee2mqtt-zbbridge-pro/bridge/state' -C 1 -v
```

## 8. 운영 주기

권장 주기:

- Zigbee 장치 페어링 직후 백업
- Node-RED flow 변경 직후 백업
- Mosquitto 계정 추가 또는 비밀번호 변경 직후 백업
- 최소 월 1회 정기 백업

보관 기준:

- NAS에 최근 5개 이상 보관
- SD 카드 재설치 직후 최신 백업으로 복구 테스트 1회 수행
- 오래된 백업은 NAS 보관 정책에 따라 삭제

## 9. 주간 자동 백업

`systemd timer`로 매주 1회 로컬 백업을 만들고 NAS FTP로 업로드합니다.

### 9.1. 환경 파일 생성

FTP 접속 정보는 서비스 파일에 직접 쓰지 않고 root만 읽을 수 있는 환경 파일로
분리합니다.

```bash
sudo nano /etc/rpi2-backup.env
```

내용:

```bash
NAS_FTP_USER=semtl
NAS_FTP_HOST=192.168.77.2
NAS_FTP_DIR=/nfs/device-backups/rpi2
NAS_FTP_PASSWORD=<NAS_FTP_PASSWORD>
BACKUP_ROOT=/home/semtl/backups
```

권한 설정:

```bash
sudo chown root:root /etc/rpi2-backup.env
sudo chmod 600 /etc/rpi2-backup.env
```

### 9.2. 실행 스크립트 생성

```bash
sudo nano /usr/local/sbin/rpi2-weekly-backup.sh
```

스크립트 내용:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

echo "[rpi2-backup] start weekly backup"

set -a
source /etc/rpi2-backup.env
set +a

runuser -u semtl -- /home/semtl/scripts/backup-rpi2-apps.sh
runuser -u semtl -- /home/semtl/scripts/upload-rpi2-backup-to-nas.sh

echo "[rpi2-backup] weekly backup complete"
```

권한 설정:

```bash
sudo chown root:root /usr/local/sbin/rpi2-weekly-backup.sh
sudo chmod 700 /usr/local/sbin/rpi2-weekly-backup.sh
```

### 9.3. systemd 서비스 생성

```bash
sudo nano /etc/systemd/system/rpi2-weekly-backup.service
```

서비스 파일:

```ini
[Unit]
Description=Raspberry Pi 2 weekly app backup
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/rpi2-weekly-backup.sh
```

### 9.4. systemd 타이머 생성

```bash
sudo nano /etc/systemd/system/rpi2-weekly-backup.timer
```

타이머 파일:

```ini
[Unit]
Description=Run Raspberry Pi 2 weekly app backup

[Timer]
OnCalendar=Sun 03:30
Persistent=true
Unit=rpi2-weekly-backup.service

[Install]
WantedBy=timers.target
```

### 9.5. 타이머 활성화

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now rpi2-weekly-backup.timer
systemctl list-timers rpi2-weekly-backup.timer
```

### 9.6. 수동 실행과 로그 확인

수동 실행:

```bash
sudo systemctl start rpi2-weekly-backup.service
```

상태 확인:

```bash
systemctl status rpi2-weekly-backup.service --no-pager
journalctl -u rpi2-weekly-backup.service -n 120 --no-pager
```

정상 기준:

- `~/backups/`에 새 `.tar.gz`, `.sha256` 파일 생성
- NAS FTP 경로에 같은 파일 2개 업로드
- `journalctl`에 `weekly backup complete` 표시
