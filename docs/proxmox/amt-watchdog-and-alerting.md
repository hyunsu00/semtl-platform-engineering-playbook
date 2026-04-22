# Proxmox Intel AMT Watchdog And Alerting

## 개요

Proxmox Host는 정상인데 Intel AMT만 응답하지 않는 상황을 다룹니다.
이 문서는 실제 원인을 정리하고, 재발 방지를 위한 최종 운영 해법을
설명합니다.

대상 환경:

- Proxmox Host: `192.168.0.253`
- AMT 전용 NIC: `nic0` (`enp0s31f6`, `00:2b:67:55:01:fc`)
- Intel AMT Web UI: `http://192.168.0.254:16992/logon.htm`
- 외부 감시 주체: Synology NAS

## 증상

- Proxmox Host SSH/Web UI/VM은 정상
- Intel AMT Web UI만 간헐적으로 접속 불가
- 재부팅 후에는 다시 정상
- Proxmox Host 자기 자신에서 `curl` 또는 `nc`로 AMT 점검 시 오탐 가능

## 원인 분석

이번 사례에서 실제로 확인된 원인은 `AMT network = dynamic` 설정이었습니다.
다만 운영 관점에서는 이 증상이 항상 하나의 원인으로만 발생하는 것은 아니므로,
아래처럼 여러 원인 후보를 함께 점검해야 합니다.

핵심 해석:

- 이 이슈의 핵심은 Proxmox OS 자체가 아니라 `Intel AMT`의 네트워크 구성입니다.
- Host OS 네트워크와 AMT 네트워크는 별도로 확인해야 합니다.
- 운영 환경에서는 AMT 관리 IP를 `static`으로 고정하는 편이 안전합니다.

### 원인 후보 1. AMT 네트워크가 `Dynamic`으로 설정됨

증상 특징:

- 평소에는 되다가 어느 시점부터 AMT Web UI만 접속 불가
- Proxmox Host 본체 SSH/Web UI는 계속 정상
- DHCP 환경 변화 뒤에 증상이 나타날 수 있음

해결 방법:

- Intel AMT MEBx 또는 Web UI에서 네트워크 모드를 `Static`으로 변경
- 관리 IP, Subnet mask, Gateway, DNS를 명시적으로 입력
- NAS 등 외부 장비에서 `16992` 포트 재확인

### 원인 후보 2. 감시 대상 IP와 실제 AMT 관리 IP 불일치

증상 특징:

- Proxmox Host IP는 알고 있지만 AMT IP가 별도로 바뀌어 있음
- NAS 감시 스크립트는 계속 실패하지만, 다른 주소로는 AMT가 열릴 수 있음

해결 방법:

- 현재 AMT에 실제로 설정된 관리 IP를 확인
- NAS 감시 대상 IP와 문서의 예시 IP를 실제 운영값으로 맞춤
- Proxmox Host 관리 IP와 AMT 관리 IP를 같은 값으로 쓸지, 분리할지 운영 기준을 명확히 정함

### 원인 후보 3. BIOS/ME Firmware 또는 플랫폼 전력 관리 영향

- BIOS/ME Firmware 이슈
- NIC 전력 절감 옵션 또는 링크 협상 이슈

증상 특징:

- 네트워크 설정이 맞아도 간헐적으로 AMT 응답이 사라짐
- 재부팅 후 한동안 정상 동작
- 특정 idle 상태 또는 장시간 무부하 뒤 증상이 재현될 수 있음

해결 방법:

- BIOS에서 C-State, ERP, NIC 절전 관련 옵션 점검
- BIOS/ME Firmware 업데이트 가능 여부 확인
- 필요 시 저전력 관련 옵션을 단계적으로 완화한 뒤 재현 여부 비교

### 원인 후보 4. 외부 감시 방식 또는 네트워크 경로 문제

증상 특징:

- Host 내부 점검과 외부 점검 결과가 다름
- NAS에서는 실패하지만 다른 외부 장비에서는 성공하거나 그 반대 상황이 있음

해결 방법:

- 반드시 외부 장비 기준으로 `nc -zv <AMT-IP> 16992` 검증
- NAS와 Proxmox 사이 방화벽, VLAN, 스위치 포트 상태 점검
- Host 자기 자신에서 수행한 테스트 결과는 참고용으로만 사용

## 해결 전략

최종 운영 기준은 아래 순서로 접근합니다.

1. AMT 네트워크 설정과 실제 관리 IP를 먼저 확인
2. 1차 조치로 `AMT network = static` 고정 적용
3. 필요 시 BIOS/ME Firmware, 전력 관리, 네트워크 경로를 추가 점검
4. Synology NAS에서 외부 감시와 알림 체계 운영

## 1. Intel AMT 네트워크 고정

### 설정 기준

- Intel AMT: `Enabled`
- AMT network: `Static`
- AMT 전용 NIC: `nic0`
- 관리 IP: `192.168.0.254`
- Subnet mask / Gateway / DNS: 운영망 기준으로 명시적 설정

권장 원칙:

- Proxmox Host 관리 IP와 AMT 관리 IP는 운영자가 의도한 값으로 분리합니다.
- 현재 기준에서는 Proxmox Host는 `192.168.0.253`, AMT는 `192.168.0.254`를
  사용합니다.
- `nic0`는 AMT 전용으로 두고 Proxmox 관리 브리지 `vmbr0`에는 연결하지 않습니다.
- DHCP lease 상태에 기대지 말고, AMT 쪽에서 직접 `static` 값을 넣습니다.
- AMT 설정 변경 후에는 외부 장비에서 `16992` 포트 응답을 재확인합니다.

### 이번 사례의 실제 해결 내용

- 실제 장애 원인은 `AMT network = dynamic` 설정이었습니다.
- `static`으로 전환한 뒤 관리 IP 기준으로 다시 감시하자 증상이 해소되었습니다.

## 2. Proxmox Host 안정화 우회책

이번 사례의 직접 원인은 아니었지만, AMT가 장시간 idle 이후 불안정해질 때는
아래 전력 관리 억제 설정이 재발 완화에 도움이 될 수 있습니다.

### BIOS 기준

- Intel AMT: `Enabled`
- BIOS C-State: 가능하면 `C1`까지 제한
- `C1E`: 지원 시 `Disabled`
- `ERP`: 지원 시 `Disabled`

### GRUB 설정

`/etc/default/grub`의 `GRUB_CMDLINE_LINUX_DEFAULT`를 아래와 같이 수정합니다.

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_idle.max_cstate=1 \
processor.max_cstate=1 pcie_aspm=off"
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

## 3. 추가 점검 항목

### BIOS/전력 관리

- BIOS의 C-State, ERP, NIC 절전 옵션을 확인합니다.
- 장시간 idle 이후만 문제가 난다면 전력 관리 영향 가능성을 의심합니다.
- 설정 변경은 한 번에 여러 개를 바꾸지 말고 단계적으로 적용합니다.

### Firmware

- 메인보드 BIOS와 Intel ME Firmware 버전을 확인합니다.
- 벤더가 제공하는 안정화 업데이트가 있으면 적용 검토합니다.

### 네트워크 경로

- NAS, 스위치, VLAN, 방화벽 정책을 점검합니다.
- 동일 대역 다른 장비에서도 `16992` 포트 접근이 되는지 비교합니다.

## 4. Synology NAS 외부 감시

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

## 5. DSM 로그 + Telegram 알림 스크립트

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

### Intel AMT 설정

- Intel AMT MEBx 또는 Web UI에서 네트워크 모드가 `Dynamic`이 아닌 `Static`인지 확인
- 관리 IP가 `192.168.0.254`로 고정되어 있는지 확인
- Subnet mask, Gateway, DNS가 운영망과 일치하는지 확인

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

### AMT가 다시 간헐적으로 안 열림

- 먼저 AMT 네트워크 모드가 다시 `Dynamic`으로 바뀌지 않았는지 확인합니다.
- DHCP reservation만으로 충분하다고 가정하지 말고, AMT 내부 설정값 자체를 점검합니다.
- 감시 대상 IP와 실제 AMT 관리 IP가 같은지 NAS에서 다시 검증합니다.
- 네트워크 설정이 맞다면 BIOS/ME Firmware와 전력 관리 옵션도 함께 점검합니다.

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
