# Proxmox Intel AMT Watchdog And Alerting

## 개요

Proxmox Host는 정상인데 Intel AMT만 응답하지 않는 상황을 다룹니다.
이 문서는 원인 범위를 정리하고, 재발 방지를 위한 최종 운영 해법을
설명합니다.

대상 환경:

- Proxmox Host: `192.168.0.254`
- Intel AMT Web UI: `http://192.168.0.254:16992/logon.htm`
- 외부 감시 주체: Synology NAS

## 증상

- Proxmox Host SSH/Web UI/VM은 정상
- Intel AMT Web UI만 간헐적으로 접속 불가
- 재부팅 후에는 다시 정상
- Proxmox Host 자기 자신에서 `curl` 또는 `nc`로 AMT 점검 시 오탐 가능

## 원인 분석

### 가장 가능성이 높은 원인

1. CPU deep idle 상태(C-State) 진입
2. PCIe ASPM 또는 NIC 전력 절감 기능과 ME(Management Engine) 충돌
3. Intel ME Firmware/BIOS 버그 또는 저전력 플랫폼 특성

핵심 해석:

- 이 이슈는 OS 전체 장애보다 `Intel ME` 측 응답 불안정에 가깝습니다.
- `performance` governor만으로는 충분하지 않습니다.
- BIOS에서 C-State를 `C1`로 제한했더라도 Linux 커널이 추가로 idle 상태를
  제어할 수 있어 OS 쪽 제한이 필요합니다.

### 우선순위가 낮은 원인

- DHCP 주소 변경 또는 AMT 네트워크 설정 불일치
- NIC EEE(Energy Efficient Ethernet) 개별 이슈

위 항목은 재발 시 추가 점검 대상으로 두되, 1차 해결은 C-State/ASPM 억제에
집중합니다.

## 해결 전략

최종 운영 기준은 아래 2단계입니다.

1. Proxmox Host에서 C-State/ASPM 영향을 줄여 AMT 자체 안정화
2. Synology NAS에서 외부 감시를 수행하고 DSM 로그 및 Telegram 알림 연동

## 1. Proxmox Host 안정화

### BIOS 기준

- Intel AMT: `Enabled`
- BIOS C-State: 가능하면 `C1`까지 제한
- `C1E`: 지원 시 `Disabled`
- `ERP`: 지원 시 `Disabled`

### GRUB 설정

`/etc/default/grub`의 `GRUB_CMDLINE_LINUX_DEFAULT`를 아래와 같이 수정합니다.

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_idle.max_cstate=1 processor.max_cstate=1 pcie_aspm=off"
```

적용 절차:

```bash
grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub
cp /etc/default/grub /etc/default/grub.bak-$(date +%F_%H%M)
vi /etc/default/grub
update-grub
reboot
```

편집 시에는 기존 `GRUB_CMDLINE_LINUX_DEFAULT` 줄을 찾아 위 값으로 교체합니다.

적용 확인:

```bash
cat /sys/module/intel_idle/parameters/max_cstate
```

기대 결과:

- 출력값이 `1`

운영 메모:

- `performance` governor는 클럭 정책일 뿐이며 C-State 문제를 직접 해결하지
  않습니다.
- 위 설정 적용 후 idle 전력은 소폭 증가할 수 있습니다.

## 2. Synology NAS 외부 감시

### 왜 NAS에서 감시해야 하는가

Proxmox Host 자신에서 자기 AMT를 직접 점검하면 오탐이 발생할 수 있습니다.
실제 운영 감시는 반드시 외부 장비에서 수행합니다.

현재 환경에서는 Synology NAS에서 아래 점검이 성공하는 것을 기준으로 합니다.

```bash
nc -zv 192.168.0.254 16992
```

기대 결과:

- `open`

### DSM 작업 스케줄러 구성

경로:

1. `제어판`
2. `작업 스케줄러`
3. `생성`
4. `예약된 작업`
5. `사용자 정의 스크립트`

권장 설정:

- 작업 이름: `AMT Watchdog`
- 사용자: `root`
- 실행 주기: `30분마다`

## 3. DSM 로그 + Telegram 알림 스크립트

아래 스크립트를 작업 스케줄러의 사용자 정의 스크립트에 그대로 사용합니다.
`BOT_TOKEN`과 `CHAT_ID`는 예시 값을 쓰지 말고 실제 운영 환경 값으로 직접 치환합니다.

```bash
IP="192.168.0.254"
PORT="16992"

BOT_TOKEN="<telegram-bot-token>"
CHAT_ID="<telegram-chat-id>"

STATE_FILE="/tmp/amt_watchdog_192_168_0_254.state"

send_telegram() {
    MSG="$1"
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
      --data-urlencode "chat_id=$CHAT_ID" \
      --data-urlencode "text=$MSG" >/dev/null 2>&1
}

is_up() {
    nc -z -w 3 "$IP" "$PORT" >/dev/null 2>&1
}

# 초기 상태 파일 없으면 현재 상태로 생성만 하고 알림은 안 보냄
if [ ! -f "$STATE_FILE" ]; then
    if is_up; then
        echo "UP" > "$STATE_FILE"
    else
        echo "DOWN" > "$STATE_FILE"
    fi
    exit 0
fi

PREV_STATE="$(cat "$STATE_FILE" 2>/dev/null)"

if is_up; then
    CUR_STATE="UP"
else
    sleep 5
    if is_up; then
        CUR_STATE="UP"
    else
        CUR_STATE="DOWN"
    fi
fi

if [ "$PREV_STATE" = "UP" ] && [ "$CUR_STATE" = "DOWN" ]; then
    MSG="AMT DOWN on $IP:$PORT"
    /usr/syno/bin/synologset1 sys error 0x11800000 "$MSG"
    send_telegram "$MSG"
    echo "DOWN" > "$STATE_FILE"
elif [ "$PREV_STATE" = "DOWN" ] && [ "$CUR_STATE" = "UP" ]; then
    MSG="AMT UP on $IP:$PORT"
    /usr/syno/bin/synologset1 sys info 0x11800000 "$MSG"
    send_telegram "$MSG"
    echo "UP" > "$STATE_FILE"
fi
```

동작 방식:

- 1차 실패 후 5초 뒤 재확인
- `UP -> DOWN` 전환 시 1회만 장애 알림
- `DOWN -> UP` 전환 시 1회만 복구 알림
- 동일 상태 지속 중에는 중복 알림 없음

## 검증 방법

### Proxmox Host

```bash
cat /sys/module/intel_idle/parameters/max_cstate
```

기대 결과:

- `1`

### Synology NAS

```bash
nc -zv 192.168.0.254 16992
```

기대 결과:

- `open`

### DSM 로그

- `로그 센터 -> 로그`에서 `AMT DOWN` 또는 `AMT UP` 확인

### Telegram

- 장애 시 `AMT DOWN on 192.168.0.254:16992`
- 복구 시 `AMT UP on 192.168.0.254:16992`

## 트러블슈팅

### Proxmox Host에서는 실패하는데 NAS에서는 성공함

- 정상일 수 있습니다.
- Host 자기 자신에서 자기 AMT를 검사하는 방식은 신뢰하지 않습니다.
- 외부 장비인 NAS 결과를 운영 기준으로 사용합니다.

### DSM 로그센터에는 안 보이는데 `/var/log/messages`에는 보임

- `logger` 기반 로그는 DSM UI에 바로 안 보일 수 있습니다.
- DSM UI 표시가 필요하면 `synologset1`을 사용합니다.

### Telegram 전송 시 UTF-8 오류 발생

- `curl -d` 대신 `--data-urlencode`를 사용합니다.
- 한글 또는 특수문자가 포함되면 반드시 URL 인코딩 방식으로 전송합니다.

### 같은 장애가 계속 쌓이는 것이 걱정됨

- 상태 파일 기반(`STATE_FILE`)으로 전환 감지만 수행하므로 반복 알림을
  억제합니다.
- NAS 재부팅 후에는 현재 상태를 다시 학습하며 첫 실행에서는 알림을 보내지
  않습니다.

## 참고

- [Proxmox 운영 가이드](./operation-guide.md)
- [Proxmox 트러블슈팅](./troubleshooting.md)
