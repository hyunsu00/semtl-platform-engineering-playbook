# Proxmox 로컬 설정 백업 및 복구

## 목적

이 문서는 Proxmox 호스트의 설정만 로컬에 수동 백업하고,
복구 시 필요한 메타정보를 함께 보관하는 운영 절차를 정리합니다.

이 문서의 스크립트는 다음 목표를 기준으로 작성합니다.

- 복구가 쉬움
- 설정만 백업
- VM/CT 목록과 스냅샷 메타정보까지 같이 보관
- 압축 파일 하나만 챙기면 됨
- 복구 시 참고용 정보가 충분함

기본 백업 저장 경로:

- `/root/proxmox-config-backups`

주의:

- 이 절차는 Proxmox 호스트 설정 백업입니다.
- VM/CT 디스크 데이터 자체는 포함하지 않습니다.
- VM/CT 설정과 스냅샷 메타정보는 포함됩니다.

## 포함 대상

### 핵심 설정

- `/etc/pve`
- `/etc/network/interfaces`
- `/etc/hosts`
- `/etc/hostname`
- `/etc/apt`
- `/etc/fstab`
- `/etc/cron.d`
- `/etc/cron.daily`
- `/etc/cron.weekly`
- `/etc/systemd/system`
- `/root/.ssh`

### Proxmox/클러스터 참고 파일

- `/var/lib/pve-cluster/config.db`

### 메타정보

- `pveversion -v`
- `qm list`
- `pct list`
- `pvesm status`
- `lsblk`
- `df -h`
- `mount`
- `ip a`
- `ip r`
- `systemctl status pve-cluster pvedaemon pveproxy`
- 각 VM config 전문
- 각 CT config 전문
- 각 VM snapshot 목록

## 백업 스크립트

아래 스크립트는 root 쉘에서 그대로 사용합니다.
스크립트 본문은 운영 기준 원문을 그대로 유지합니다.

```bash
cat <<'EOF' > /root/proxmox-config-backup.sh
#!/usr/bin/env bash
set -Eeuo pipefail

BACKUP_BASE="/root/proxmox-config-backups"
DATE="$(date +%F_%H-%M-%S)"
HOSTNAME_SHORT="$(hostname -s)"
WORKDIR="$(mktemp -d /tmp/proxmox-config-backup.XXXXXX)"
ARCHIVE_NAME="${HOSTNAME_SHORT}-proxmox-config-${DATE}.tar.gz"
ARCHIVE_PATH="${BACKUP_BASE}/${ARCHIVE_NAME}"
LATEST_LINK="${BACKUP_BASE}/latest.tar.gz"
LOG_PATH="${BACKUP_BASE}/backup-${DATE}.log"

cleanup() {
    rm -rf "${WORKDIR}"
}
trap cleanup EXIT

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "${LOG_PATH}"
}

copy_if_exists() {
    local src="$1"
    local dst_root="$2"

    if [ -e "${src}" ]; then
        mkdir -p "${dst_root}$(dirname "${src}")"
        cp -a "${src}" "${dst_root}${src}"
    fi
}

mkdir -p "${BACKUP_BASE}"
: > "${LOG_PATH}"

log "Backup start"
log "Workdir: ${WORKDIR}"
log "Archive: ${ARCHIVE_PATH}"

mkdir -p "${WORKDIR}/backup"
mkdir -p "${WORKDIR}/meta"
mkdir -p "${WORKDIR}/meta/vm-configs"
mkdir -p "${WORKDIR}/meta/ct-configs"
mkdir -p "${WORKDIR}/meta/vm-snapshots"
mkdir -p "${WORKDIR}/meta/services"

########################################
# 1) 핵심 설정 백업
########################################
log "Copying core configuration files"

copy_if_exists /etc/pve "${WORKDIR}/backup"
copy_if_exists /etc/network/interfaces "${WORKDIR}/backup"
copy_if_exists /etc/hosts "${WORKDIR}/backup"
copy_if_exists /etc/hostname "${WORKDIR}/backup"
copy_if_exists /etc/apt "${WORKDIR}/backup"
copy_if_exists /etc/fstab "${WORKDIR}/backup"
copy_if_exists /etc/cron.d "${WORKDIR}/backup"
copy_if_exists /etc/cron.daily "${WORKDIR}/backup"
copy_if_exists /etc/cron.weekly "${WORKDIR}/backup"
copy_if_exists /etc/systemd/system "${WORKDIR}/backup"
copy_if_exists /root/.ssh "${WORKDIR}/backup"
copy_if_exists /var/lib/pve-cluster/config.db "${WORKDIR}/backup"

########################################
# 2) 시스템/스토리지/네트워크 정보
########################################
log "Collecting system metadata"

{
    echo "=== Backup timestamp ==="
    date
    echo

    echo "=== Hostname ==="
    hostname
    echo

    echo "=== Kernel ==="
    uname -a
    echo

    echo "=== Proxmox version ==="
    pveversion -v || true
} > "${WORKDIR}/meta/system-info.txt"

{
    echo "=== lsblk ==="
    lsblk || true
    echo

    echo "=== df -h ==="
    df -h || true
    echo

    echo "=== mount ==="
    mount || true
    echo

    echo "=== pvesm status ==="
    pvesm status || true
} > "${WORKDIR}/meta/storage-info.txt"

{
    echo "=== ip -br a ==="
    ip -br a || true
    echo

    echo "=== ip route ==="
    ip route || true
    echo

    echo "=== bridge link ==="
    bridge link || true
    echo

    echo "=== bridge vlan ==="
    bridge vlan || true
} > "${WORKDIR}/meta/network-info.txt"

{
    echo "=== root crontab ==="
    crontab -l || true
} > "${WORKDIR}/meta/root-crontab.txt"

########################################
# 3) 서비스 상태
########################################
log "Collecting service status"

for svc in pve-cluster pvedaemon pveproxy pvestatd corosync; do
    {
        echo "=== systemctl status ${svc} ==="
        systemctl status "${svc}" --no-pager || true
    } > "${WORKDIR}/meta/services/${svc}.txt"
done

########################################
# 4) VM/CT 목록 및 상세 설정
########################################
log "Collecting VM and CT metadata"

{
    echo "=== qm list ==="
    qm list || true
} > "${WORKDIR}/meta/qm-list.txt"

{
    echo "=== pct list ==="
    pct list || true
} > "${WORKDIR}/meta/pct-list.txt"

# VM 목록 수집
mapfile -t VM_IDS < <(qm list 2>/dev/null | awk 'NR>1 {print $1}' || true)
for vmid in "${VM_IDS[@]:-}"; do
    if [ -n "${vmid}" ]; then
        {
            echo "=== qm config ${vmid} ==="
            qm config "${vmid}" || true
        } > "${WORKDIR}/meta/vm-configs/${vmid}.conf.txt"

        {
            echo "=== qm listsnapshot ${vmid} ==="
            qm listsnapshot "${vmid}" || true
            echo
            echo "=== /etc/pve/qemu-server/${vmid}.conf ==="
            if [ -f "/etc/pve/qemu-server/${vmid}.conf" ]; then
                cat "/etc/pve/qemu-server/${vmid}.conf"
            fi
        } > "${WORKDIR}/meta/vm-snapshots/${vmid}.snapshot.txt"
    fi
done

# CT 목록 수집
mapfile -t CT_IDS < <(pct list 2>/dev/null | awk 'NR>1 {print $1}' || true)
for ctid in "${CT_IDS[@]:-}"; do
    if [ -n "${ctid}" ]; then
        {
            echo "=== pct config ${ctid} ==="
            pct config "${ctid}" || true
        } > "${WORKDIR}/meta/ct-configs/${ctid}.conf.txt"
    fi
done

########################################
# 5) 복구 안내문 포함
########################################
log "Writing restore guide"

cat > "${WORKDIR}/RESTORE-GUIDE.txt" <<'RESTORE'
[Proxmox Config Restore Guide]

1. 새 Proxmox를 가능한 한 원본과 비슷한 버전으로 설치합니다.
2. 백업 파일을 임시 디렉터리에 풉니다.
   tar -xzf <backup-file>.tar.gz -C /root/restore-test

3. 주요 복원 대상:
   - backup/etc/pve
   - backup/etc/network/interfaces
   - backup/etc/hosts
   - backup/etc/hostname
   - backup/etc/apt
   - backup/etc/fstab
   - backup/etc/systemd/system
   - backup/var/lib/pve-cluster/config.db

4. 즉시 전체 덮어쓰기는 주의해서 진행합니다.
   특히 /etc/network/interfaces, storage.cfg, cluster 관련 파일은
   현재 장비명/디스크명/NIC명과 차이가 없는지 먼저 비교 후 복원합니다.

5. 비교 예시:
   diff -ruN /etc/pve /root/restore-test/backup/etc/pve
   diff -u /etc/network/interfaces /root/restore-test/backup/etc/network/interfaces

6. 서비스 재시작 예시:
   systemctl restart networking || true
   systemctl restart pve-cluster
   systemctl restart pvedaemon
   systemctl restart pveproxy

7. 이 백업은 "설정 백업"입니다.
   VM/CT 디스크 데이터 자체는 포함하지 않습니다.
   단, VM/CT 설정 및 snapshot 메타정보는 포함됩니다.
RESTORE

########################################
# 6) 압축 생성
########################################
log "Creating archive"
tar -C "${WORKDIR}" -czf "${ARCHIVE_PATH}" .

ln -sfn "${ARCHIVE_NAME}" "${LATEST_LINK}"

########################################
# 7) 검증
########################################
log "Verifying archive"
tar -tzf "${ARCHIVE_PATH}" > /dev/null

log "Backup completed successfully"
log "Archive file: ${ARCHIVE_PATH}"
log "Latest link : ${LATEST_LINK}"
log "Log file    : ${LOG_PATH}"

echo
echo "[OK] Backup completed"
echo "[OK] Archive : ${ARCHIVE_PATH}"
echo "[OK] Latest  : ${LATEST_LINK}"
echo "[OK] Log     : ${LOG_PATH}"
echo
echo "[INFO] Top-level archive contents:"
tar -tzf "${ARCHIVE_PATH}" | awk -F/ 'NF{print $1}' | sort -u
EOF
```

## 스크립트 설치 및 수동 실행

실행 권한 부여:

```bash
chmod +x /root/proxmox-config-backup.sh
```

수동 실행:

```bash
/root/proxmox-config-backup.sh
```

결과 확인:

```bash
ls -lh /root/proxmox-config-backups
```

압축 내부 확인:

```bash
tar -tzf /root/proxmox-config-backups/latest.tar.gz | less
```

## 이 스크립트의 장점

### 1) 복구가 쉬움

백업 안에 `RESTORE-GUIDE.txt`가 포함되어 있어
나중에 압축 파일만 확보해도 복원 절차를 바로 따라갈 수 있습니다.

### 2) 스냅샷 정보 포함

VM 디스크 스냅샷 데이터 자체는 포함되지 않지만,
다음 정보가 함께 보관됩니다.

- `/etc/pve/qemu-server/<VMID>.conf`
- `qm listsnapshot <VMID>` 결과 저장본

### 3) 운영 정보가 충분함

복구 시 필요한 버전, 스토리지, 네트워크, 서비스 상태가 함께 남습니다.

### 4) 단일 파일 관리

최종 결과물은 `tar.gz` 하나로 관리할 수 있습니다.

## 스냅샷 관련 정확한 의미

중요한 구분은 아래와 같습니다.

- 포함됨: 스냅샷 이름, 계층, 설명, 시점 등 메타정보
- 포함 안 됨: 실제 스냅샷 디스크 데이터

즉 이 스크립트는 설정 백업이며, VM 전체 백업은 아닙니다.

## 백업 파일 내용 확인 방법

### 1) 압축 안의 파일 목록 보기

가장 자주 쓰는 방법입니다.

```bash
tar -tzf /root/proxmox-config-backups/latest.tar.gz
```

많으면 `less`로 확인합니다.

```bash
tar -tzf /root/proxmox-config-backups/latest.tar.gz | less
```

예시:

```text
backup/
backup/etc/
backup/etc/pve/
backup/etc/network/interfaces
meta/
meta/system-info.txt
meta/network-info.txt
RESTORE-GUIDE.txt
```

### 2) 특정 파일 내용 바로 보기

압축을 풀지 않고 내부 파일 내용을 확인할 수 있습니다.

예: `system-info.txt`

```bash
tar -xOf /root/proxmox-config-backups/latest.tar.gz meta/system-info.txt
```

예: 네트워크 정보

```bash
tar -xOf /root/proxmox-config-backups/latest.tar.gz meta/network-info.txt
```

예: VM 목록

```bash
tar -xOf /root/proxmox-config-backups/latest.tar.gz meta/qm-list.txt
```

### 3) 특정 파일만 추출

예: `/etc/pve` 확인

```bash
tar -xzf /root/proxmox-config-backups/latest.tar.gz backup/etc/pve
```

### 4) 전체 압축 풀기

테스트용으로 임시 디렉터리에 풀어서 보는 방법입니다.

```bash
mkdir /root/restore-test
tar -xzf /root/proxmox-config-backups/latest.tar.gz -C /root/restore-test
```

확인:

```bash
tree /root/restore-test
```

또는

```bash
find /root/restore-test
```

### 5) VM 스냅샷 정보 확인

```bash
tar -xOf /root/proxmox-config-backups/latest.tar.gz meta/vm-snapshots/100.snapshot.txt
```

### 6) VM 설정 확인

```bash
tar -xOf /root/proxmox-config-backups/latest.tar.gz meta/vm-configs/100.conf.txt
```

### 7) 가장 자주 쓰는 3개 명령

운영에서는 아래 세 가지를 가장 많이 사용합니다.

목록 보기:

```bash
tar -tzf backup.tar.gz
```

파일 내용 보기:

```bash
tar -xOf backup.tar.gz 파일경로
```

전체 풀기:

```bash
tar -xzf backup.tar.gz
```

### 8) 가장 편한 방법

```bash
mkdir /tmp/test
tar -xzf /root/proxmox-config-backups/latest.tar.gz -C /tmp/test
tree /tmp/test
```

그러면 일반 폴더처럼 탐색 가능합니다.

## 백업 검증 방법

운영에서는 백업 파일이 실제 복구 가능한지 빠르게 확인하는 절차가 중요합니다.

### 1) 백업 파일 존재 확인

```bash
ls -lh /root/proxmox-config-backups
```

예시:

```text
proxmox-config-node1-2026-03-16_21-00-00.tar.gz
latest.tar.gz
backup-2026-03-16.log
```

### 2) 압축 파일 무결성 확인

```bash
tar -tzf /root/proxmox-config-backups/latest.tar.gz > /dev/null
```

오류가 없으면 정상입니다.

깨진 경우 예시:

```text
gzip: stdin: unexpected end of file
tar: Unexpected EOF
```

### 3) 백업 구조 확인

```bash
tar -tzf /root/proxmox-config-backups/latest.tar.gz | head -30
```

정상 구조 예시:

```text
backup/
backup/etc/
backup/etc/pve/
backup/etc/network/interfaces
meta/
meta/system-info.txt
meta/network-info.txt
meta/qm-list.txt
meta/vm-configs/
meta/vm-snapshots/
RESTORE-GUIDE.txt
```

### 4) Proxmox 핵심 설정 존재 확인

```bash
tar -tzf /root/proxmox-config-backups/latest.tar.gz | grep storage.cfg
tar -tzf /root/proxmox-config-backups/latest.tar.gz | grep datacenter.cfg
```

예시:

```text
backup/etc/pve/storage.cfg
backup/etc/pve/datacenter.cfg
```

이 파일들이 있어야 Proxmox 설정 복구가 쉬워집니다.

### 5) VM 목록 확인

```bash
tar -xOf /root/proxmox-config-backups/latest.tar.gz meta/qm-list.txt
```

### 6) VM 설정 확인

예: VM `100`

```bash
tar -xOf /root/proxmox-config-backups/latest.tar.gz meta/vm-configs/100.conf.txt
```

예시:

```text
boot: order=scsi0
cores: 4
memory: 8192
net0: virtio=...
scsi0: local-lvm:vm-100-disk-0
```

### 7) 스냅샷 정보 확인

```bash
tar -xOf /root/proxmox-config-backups/latest.tar.gz meta/vm-snapshots/100.snapshot.txt
```

예시:

```text
=== qm listsnapshot 100 ===

`-> before-upgrade
    backup-snap
```

### 8) 네트워크 복구 가능 여부 확인

```bash
tar -xOf /root/proxmox-config-backups/latest.tar.gz backup/etc/network/interfaces
```

예시:

```text
auto vmbr0
iface vmbr0 inet static
    address 192.168.0.254/24
    gateway 192.168.0.1
```

### 9) 스토리지 설정 확인

```bash
tar -xOf /root/proxmox-config-backups/latest.tar.gz backup/etc/pve/storage.cfg
```

예시:

```text
dir: local
    path /var/lib/vz
    content iso,vztmpl,backup
```

### 10) 실제 복구 테스트

테스트 폴더 생성:

```bash
mkdir /tmp/restore-test
```

압축 풀기:

```bash
tar -xzf /root/proxmox-config-backups/latest.tar.gz -C /tmp/restore-test
```

구조 확인:

```bash
tree /tmp/restore-test
```

예시:

```text
backup
meta
RESTORE-GUIDE.txt
```

### 11) 운영 검증 체크리스트

| 체크 항목 | 확인 방법 |
| --- | --- |
| 압축 정상 | `tar -tzf backup.tar.gz` |
| Proxmox 설정 | `storage.cfg` 확인 |
| 네트워크 | `interfaces` 확인 |
| VM 목록 | `qm-list.txt` 확인 |
| VM 설정 | `vm-configs` 확인 |
| 스냅샷 정보 | `vm-snapshots` 확인 |

## 복구 시 권장 방식

즉시 덮어쓰기보다 먼저 비교하는 방식이 안전합니다.

```bash
mkdir -p /root/restore-test
tar -xzf /root/proxmox-config-backups/latest.tar.gz -C /root/restore-test
find /root/restore-test | sort | less
```

비교 예시:

```bash
diff -ruN /etc/pve /root/restore-test/backup/etc/pve
diff -u /etc/network/interfaces /root/restore-test/backup/etc/network/interfaces
```

## 운영 기준 결론

현재 기준으로 이 스크립트는 아래 목적에 충분한 수준입니다.

- Proxmox 설정 백업
- VM 설정 백업
- 스냅샷 메타정보 백업
- 네트워크/스토리지 설정 백업

권장 운영 조합:

- 설정 백업: 이 문서의 스크립트
- VM 백업: `vzdump`
- 외부 저장: Synology NAS 또는 PBS

## 관련 문서

- [Proxmox 운영 가이드](./operation-guide.md)
- [Proxmox 설치](./installation.md)
- [PBS 설치](../pbs/installation.md)
