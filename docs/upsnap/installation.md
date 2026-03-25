# Upsnap Installation

## 개요

이 문서는 `Upsnap`을 Docker로 설치하고, Wake-on-LAN 대상 장비를 등록해
전원 제어를 시작하는 절차를 정리합니다.

`Upsnap`은 웹 UI에서 WOL 패킷 전송, 장비 상태 확인, 스케줄 실행을 제공하는
자가 호스팅 도구입니다.

이 저장소 기준으로는 다음과 같은 용도로 사용합니다.

- 내부망 PC 또는 서버 원격 부팅
- NAS 또는 홈랩 장비 전원 On/Off 자동화
- Synology Reverse Proxy 또는 VPN 뒤에서 내부 관리 도구로 운용

## 사전 조건

- Docker Engine 또는 Docker Compose 실행 환경
- WOL 대상 장비에서 BIOS/UEFI의 Wake-on-LAN 활성화
- 대상 장비의 MAC 주소 확보
- 같은 L2 브로드캐스트 도메인 또는 WOL 전달 가능한 네트워크 경로

운영 메모:

- Docker 기준 `host` 네트워크가 필요합니다.
- 컨테이너에는 `NET_RAW` capability가 필요합니다.
- 외부 인터넷에 직접 노출하지 않고 VPN 또는 내부 프록시 뒤에서 운용하는 것을
  권장합니다.

## 1. 설치 디렉터리 준비

Synology 기준 예시 경로:

```bash
mkdir -p /volume1/docker/upsnap/data
cd /volume1/docker/upsnap
```

`/volume1/docker/upsnap/data` 디렉터리는 `Upsnap`의 PocketBase 데이터와
설정을 영구 보관하는 용도입니다.

## 2. Docker Compose 파일 작성

아래 예시는 현재 운영 기준을 반영한 `docker-compose.yml`입니다.

`docker-compose.yml` 예시:

```yaml
services:
  upsnap:
    cap_add:
      - NET_RAW # 권한 있는 ping을 실행하려면 NET_RAW 권한이 필요합니다.
    cap_drop:
      - ALL
    container_name: upsnap
    image: ghcr.io/seriousm4x/upsnap:5 # 이미지는 Docker Hub에서도 이용 가능합니다: seriousm4x/upsnap:5
    network_mode: host # WOL 매직 패킷에는 호스트가 필요합니다.
    restart: unless-stopped
    volumes:
      - /volume1/docker/upsnap/data:/app/pb_data
    environment:
      - TZ=Asia/Seoul # cron 스케줄에 대한 컨테이너 시간대를 설정합니다.
      - UPSNAP_HTTP_LISTEN=127.0.0.1:8090
      - UPSNAP_INTERVAL=*/30 * * * * * # 30초마다 체크
      - UPSNAP_SCAN_RANGE=192.168.0.0/24
  #   - UPSNAP_SCAN_TIMEOUT=500ms
  #     스캔 타임아웃은 nmap host-timeout 값입니다.
  #   - UPSNAP_PING_PRIVILEGED=true
  #     기본값은 true입니다. 비권한 ping을 쓰려면 false로 설정합니다.
  #     Linux 호스트는 ping_group_range 설정이 필요할 수 있습니다.
      - UPSNAP_WEBSITE_TITLE=SEMTL WOL # 사용자 지정 웹사이트 제목
  # security_opt:
  #   - no-new-privileges=true
  # # DNS는 네트워크 스캔 중 이름 확인에 사용됩니다.
  # dns:
  #   - 192.18.0.1
  #   - 192.18.0.2
  # # 또는 종료를 위한 사용자 지정 패키지를 설치하세요.
    entrypoint: >-
      /bin/sh -c "apk update && apk add --no-cache sshpass &&
      rm -rf /var/cache/apk/* && ./upsnap serve"
```

설정 의미:

- `network_mode: host`: WOL magic packet 전송에 필요
- `cap_add: NET_RAW`: privileged ping에 필요
- `/volume1/docker/upsnap/data:/app/pb_data`: Synology 볼륨에 데이터 영속화
- `UPSNAP_HTTP_LISTEN`: 웹 UI 바인드 주소와 포트
- `UPSNAP_INTERVAL`: `30초`마다 장비 상태 체크
- `UPSNAP_SCAN_RANGE`: 장비 검색 시 사용할 기본 대역
- `UPSNAP_WEBSITE_TITLE`: 웹 UI 제목 지정
- `entrypoint`: `sshpass` 설치 후 `Upsnap` 실행

운영 메모:

- `2026-03-25` 기준 최신 공식 릴리스는 `5.3.1`입니다.
- Docker 이미지 태그는 공식 예시처럼 메이저 태그 `:5`를 사용하면 같은 메이저 내
  업데이트를 따라갈 수 있습니다.
- 특정 버전 고정이 필요하면 `ghcr.io/seriousm4x/upsnap:5.3.1`처럼 명시합니다.
- `127.0.0.1:8090`으로 바인드하면 같은 호스트의 Reverse Proxy를 통해서만
  노출하는 구성이 쉬워집니다.

## 3. 컨테이너 기동

```bash
docker compose up -d
docker compose ps
```

로그 확인:

```bash
docker compose logs -f upsnap
```

접속 URL:

- 로컬 직접 확인: `http://127.0.0.1:8090`
- Reverse Proxy 사용 시: 프록시에 연결한 도메인으로 접속

## 4. 첫 로그인과 관리자 계정 생성

처음 접속하면 관리자 계정을 생성합니다.

권장 기준:

- 관리자 계정은 개인 계정으로 생성
- 공용 계정보다 사용자별 계정 분리
- 강한 비밀번호 사용

초기 계정 생성 후에는 해당 계정으로 로그인합니다.

## 5. 장비 등록

`Upsnap`은 수동 등록과 네트워크 스캔 방식을 모두 지원합니다.

### 수동 등록

장비를 수동으로 등록할 때는 아래 값을 준비합니다.

- 장비 이름
- IP 주소
- MAC 주소
- Ping 포트
- 필요 시 Shutdown 명령

예시:

- 이름: `vm-admin`
- IP: `192.168.0.20`
- MAC: `AA:BB:CC:DD:EE:FF`
- Ping Port: `22`

### 자동 스캔

자동 스캔은 `UPSNAP_SCAN_RANGE=192.168.0.0/24` 대역을 기준으로 수행합니다.

주의:

- 스캔 기능은 네트워크 환경과 권한에 따라 일부 장비를 찾지 못할 수 있습니다.
- 장비 검색 정확도가 중요하면 수동 등록을 우선합니다.

## 6. WOL 동작 검증

대상 장비를 등록한 뒤 `Wake` 버튼으로 부팅을 시도합니다.

검증 포인트:

- 대상 장비가 실제로 전원 On 되는지 확인
- `Upsnap` UI에서 장비 상태가 `Online`으로 바뀌는지 확인
- Ping 포트가 실제 서비스 포트와 맞는지 확인

장비가 켜지지 않으면 아래 항목을 먼저 점검합니다.

- BIOS/UEFI의 Wake-on-LAN 활성화 여부
- OS 또는 NIC 드라이버의 WOL 설정
- MAC 주소 정확성
- 같은 네트워크 대역 또는 브로드캐스트 전달 가능 여부
- 중간 스위치 또는 공유기의 브로드캐스트 제한 여부

## 7. Reverse Proxy 연동

이 문서 기준 설정은 `127.0.0.1:8090` 바인드이므로, 운영상 Reverse Proxy 뒤에
두는 구성을 전제로 합니다.

예:

- 외부: `https://upsnap.semtl.synology.me`
- 내부 대상: `http://127.0.0.1:8090`

운영 메모:

- `Upsnap` 자체 로그인 기능이 있어도 인터넷 직접 공개는 권장하지 않습니다.
- 외부 접근이 필요하면 VPN을 우선 사용합니다.
- Reverse Proxy 뒤에 둘 때도 관리 IP 제한을 함께 거는 편이 안전합니다.

## 8. 선택 설정

### 포트 변경

기본 포트 `8090` 대신 다른 포트를 쓰려면 다음 값을 바꿉니다.

```yaml
environment:
  - UPSNAP_HTTP_LISTEN=127.0.0.1:5000
```

### 타임존 설정

스케줄 기능을 사용할 경우 `TZ`를 명시하는 편이 좋습니다.

```yaml
environment:
  - TZ=Asia/Seoul
```

### Shutdown 명령용 패키지 추가

이 문서 기준으로는 `sshpass`를 추가 설치해 SSH 기반 종료 명령에 활용합니다.

```yaml
entrypoint: >-
  /bin/sh -c "apk update && apk add --no-cache sshpass &&
  rm -rf /var/cache/apk/* && ./upsnap serve"
```

## 9. 검증

컨테이너 상태:

```bash
docker compose ps
```

로그 확인:

```bash
docker compose logs --tail=100 upsnap
```

포트 확인:

```bash
ss -lntp | grep 8090
```

기대 결과:

- `Upsnap` 웹 UI가 정상 응답
- 관리자 로그인 가능
- 등록 장비에 대해 `Wake` 동작 성공

## 10. 트러블슈팅

### Windows 장비가 켜져 있는데 `Offline`으로 표시됨

`Upsnap`은 기본적으로 Ping 응답을 기준으로 장비 상태를 판단합니다.

예:

- 실제 Windows PC는 켜져 있음
- 하지만 `Upsnap`에서는 빨간색 또는 `Offline`으로 표시됨

가장 흔한 원인:

- Windows 방화벽이 ICMP Echo 요청을 차단

이 경우 실제로는 장비가 켜져 있어도 `Upsnap`은 Ping 실패로 판단해
`Offline`으로 표시할 수 있습니다.

#### 해결 방법 1: Windows 방화벽에서 Ping 허용

경로:

1. `제어판`
2. `Windows Defender 방화벽`
3. `고급 설정`
4. `인바운드 규칙`
5. `파일 및 프린터 공유 (에코 요청 - ICMPv4-In)` 규칙 활성화

PowerShell 또는 명령 프롬프트(관리자 권한)에서 바로 적용:

```powershell
netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes
```

적용 후 기대 결과:

- Windows 장비에 Ping 응답 가능
- `Upsnap` 상태가 `Online`으로 바뀜

#### 해결 방법 2: Ping 대신 서비스 포트 기준으로 점검

장비가 Windows라면 Ping 대신 실제 서비스 포트를 기준으로 상태를 확인하는 편이
더 정확할 수 있습니다.

예:

- RDP 사용 PC: `3389`
- SSH 사용 장비: `22`

운영 메모:

- Ping은 되지만 실제 서비스가 죽어 있을 수도 있습니다.
- 반대로 Windows 방화벽 때문에 Ping만 막히고 서비스는 정상일 수도 있습니다.
- 가능하면 장비 역할에 맞는 포트를 `Ping Port`로 지정하는 편이 실무상 더 정확합니다.

## 11. 운영 권장사항

- `Upsnap`을 공인 인터넷에 직접 노출하지 않습니다.
- 외부 접근은 WireGuard, Tailscale, OpenVPN 같은 VPN 경로를 우선합니다.
- 장비별 권한을 분리하고 관리자 계정을 최소화합니다.
- WOL 대상 장비 목록과 MAC 주소는 운영 문서로 별도 관리합니다.
- 브로드캐스트 기반 WOL은 네트워크 구조 변경에 민감하므로 스위치/라우터 변경 시
  다시 검증합니다.
