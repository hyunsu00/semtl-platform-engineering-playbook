# AdGuard Home Installation

## 개요

이 문서는 Synology DSM의 `Container Manager`에서 `AdGuard Home`을 설치하고,
내부 DNS와 광고 차단을 함께 운영하는 기준 절차를 정리합니다.

기준 환경:

- Synology NAS 단일 IP 운영
- DSM이 `80/443` 포트를 이미 사용 중
- AdGuard Home은 `53/tcp`, `53/udp`, `3000/tcp`만 사용
- Docker `bridge` 네트워크 모드 사용

중요:

- 이 문서는 **동일 NAS/IP에서 Synology `DNS Server` 패키지를 중지하고**
  `AdGuard Home`이 DNS 역할을 넘겨받는 기준입니다.
- Synology `DNS Server`를 계속 유지해야 하면 `AdGuard Home`은
  **다른 VM 또는 다른 IP**에 설치해야 합니다.

## 최신 UI 메뉴 기준

최신 AdGuard Home UI 기준 주요 메뉴 경로:

- `Settings -> DNS settings`
- `Filters -> DNS blocklists`
- `Filters -> DNS rewrites`
- `Filters -> Custom filtering rules`

이 문서는 위 메뉴명을 기준으로 작성합니다.

## 사전 조건

- DSM 관리자 권한
- `Container Manager` 설치 가능 상태
- NAS SSH 접속 가능 상태
- ASUS 공유기 DHCP DNS 변경 권한
- AdGuard에 할당할 NAS IP 확보
  - 예시: `192.168.0.2`

## 포트와 네트워크 기준

- DSM: `80`, `443`
- AdGuard DNS: `53/tcp`, `53/udp`
- AdGuard 관리 UI: `3000/tcp`
- Docker network: `bridge`

중요:

- 초기 마법사 이후에도 관리 UI는 `3000`을 유지합니다.
- 동일 NAS에서 DSM이 `80/443`을 사용 중이면 AdGuard 관리 UI를
  `80/443`으로 바꾸지 않습니다.

## 1. 사전 점검

### 1.1 `53` 포트 사용 여부 확인

```bash
sudo ss -lntup | grep ':53'
```

확인 포인트:

- `53` 포트를 이미 사용하는 프로세스가 없거나
- Synology `DNS Server` 패키지뿐인지 확인

### 1.2 Synology `DNS Server` 패키지 중지

동일 NAS/IP에서 AdGuard Home을 DNS 서버로 운영할 경우
Synology `DNS Server` 패키지는 중지합니다.

운영 기준:

- `패키지 센터 -> DNS Server -> 중지`
- 또는 DSM에서 DNS 관련 서비스가 `53`을 점유하지 않도록 정리

## 2. AdGuard Home 디렉터리 준비

```bash
sudo mkdir -p /volume1/docker/adguardhome/work
sudo mkdir -p /volume1/docker/adguardhome/conf
```

## 3. Container Manager Project 생성

`Container Manager -> Project -> Create`에서 아래 `compose`를 사용합니다.

```yaml
version: "3"

services:
  adguardhome:
    # 최신 안정화 버전을 명시 (v0.107.73)
    image: adguard/adguardhome:v0.107.73
    container_name: adguardhome
    restart: unless-stopped
    network_mode: "bridge"
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "3000:3000"
    environment:
      - TZ=Asia/Seoul
    volumes:
      - /volume1/docker/adguardhome/work:/opt/adguardhome/work
      - /volume1/docker/adguardhome/conf:/opt/adguardhome/conf
```

이 구성을 사용하는 이유:

- DSM `80/443` 포트와 충돌하지 않음
- NAS `53` 포트와 `3000` 포트만 외부에 노출
- Docker `bridge` 네트워크에서 격리해 운영 가능

배포 후 확인:

```bash
docker ps | grep adguardhome
docker inspect adguardhome | grep -A3 '"NetworkMode"'
```

정상 기준:

- 컨테이너 상태가 `Up`
- `NetworkMode`가 `bridge`

## 4. 초기 마법사 완료

브라우저에서 아래 주소로 접속합니다.

```text
http://192.168.0.2:3000
```

초기 마법사 권장값:

- `Web interface port`: `3000`
- `DNS server port`: `53`
- 관리자 계정: 운영 표준 계정/비밀번호 사용

주의:

- 마법사 완료 후에도 관리 UI 포트는 `3000` 유지
- DSM과 충돌하므로 `80/443`으로 변경하지 않음

## 5. `Settings -> DNS settings` 초기 최적화

### 5.1 업스트림 DNS

권장값:

```text
https://dns.cloudflare.com/dns-query
https://dns.quad9.net/dns-query
https://dns.google/dns-query
```

운영 메모:

- `Cloudflare`: 속도
- `Quad9`: 악성 도메인 차단
- `Google`: 호환성 보완용 보조 업스트림
- 3개를 함께 등록하고 `Parallel requests`를 활성화하면 응답 안정성이 좋아짐

### 5.2 Fallback DNS

업스트림 DNS 서버가 응답하지 않을 때 사용할 폴백 DNS 서버를 등록합니다.

권장값:

```text
1.1.1.1
9.9.9.9
8.8.8.8
```

운영 메모:

- 평소에는 DoH 업스트림을 우선 사용하고, 장애 시에만 폴백 DNS로 우회
- 폴백 DNS는 최소 2~3개만 유지해 장애 대응과 관리 복잡도의 균형을 맞춤

### 5.3 Bootstrap DNS

권장값:

```text
1.1.1.1
9.9.9.10
8.8.8.8
2620:fe::10
2620:fe::fe:10
```

운영 메모:

- IPv4 중심 환경이면 Bootstrap DNS도 IPv4만 등록해 단순하게 운영
- `Disable IPv6`를 활성화했다면 IPv6 Bootstrap DNS는 넣지 않음

### 5.4 권장 옵션

- `Parallel requests`: 활성화
- `Upstream timeout`: `3`
- `Rate limit`: `50`
- `Subnet prefix length for IPv4 addresses` : `24`
- `Subnet prefix length for IPv6 addresses` : `56`
- `Blocked response TTL`: `600`
- `DNSSEC`: 활성화
- `Blocking mode`: `NXDOMAIN`
- `Blocked response TTL` : `600`
- `Enable Cache`: 활성화
- `Optimistic caching`: 활성화

### 5.5 캐시 권장값

최신 UI에서 `Cache size`가 바이트 기준으로 보이면 아래 값을 사용합니다.

```text
Cache size: 67108864
Minimum TTL: 300
Maximum TTL: 86400
```

설명:

- `67108864` = `64MiB`
- `Minimum TTL 300` = 5분
- `Maximum TTL 86400` = 1일

### 5.6 IPv6 운영 기준

가정/홈랩이 IPv4 중심이면 아래 기준을 권장합니다.

- `Disable IPv6`: 활성화

주의:

- ISP/공유기에서 IPv6가 안정적으로 운영 중이면 이 항목은 환경에 맞게 조정

## 6. `Filters -> DNS blocklists` 필터 구성

한국 환경 기준 권장 필터:

- `AdGuard DNS filter`
  - URL: `https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt`
- `OISD`
  - URL: `https://big.oisd.nl`
- `KOR: List-KR DNS`
  - URL: `https://adguardteam.github.io/HostlistsRegistry/assets/filter_kr.txt`
- `KOR: YousList`
  - URL: `https://adguardteam.github.io/HostlistsRegistry/assets/filter_kr_youslist.txt`
- `HaGeZi Pro`
  - URL: `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt`
- `URLhaus Malware List`
  - URL: `https://malware-filter.gitlab.io/malware-filter/urlhaus-filter-agh-online.txt`

운영 메모:

- `OISD Small`, `OISD Big`, `AdAway`, `StevenBlack`를 중복으로 같이 넣지 않습니다.
- 필터는 많이 넣는 것보다 **중복 없는 3~4개 조합**이 안정적입니다.

권장하지 않는 조합 예시:

- `OISD`
- `OISD Blocklist Small`
- `OISD Blocklist Big`

위 3개는 데이터 중복이 커서 응답 지연과 관리 복잡도를 키웁니다.

## 7. `Filters -> DNS rewrites` 내부 DNS 등록

동일 NAS에서 Synology `DNS Server`를 내리고 AdGuard Home으로 전환한 경우,
내부 서비스 도메인은 `DNS rewrites`로 직접 관리합니다.

예시:

```text
외부 서비스
*.semtl.synology.me                 -> 192.168.0.2

내부 서비스
admin.internal.semtl.synology.me    -> 192.168.0.41
auth.internal.semtl.synology.me     -> 192.168.0.31
proxmox.internal.semtl.synology.me  -> 192.168.0.254
pbs.internal.semtl.synology.me      -> 192.168.0.253
haos.internal.semtl.synology.me     -> 192.168.0.21
nas.internal.semtl.synology.me      -> 192.168.0.2
n8n.internal.semtl.synology.me      -> 192.168.0.175
jenkins.internal.semtl.synology.me  -> 192.168.0.174
harbor.internal.semtl.synology.me   -> 192.168.0.173
gitlab.internal.semtl.synology.me   -> 192.168.0.172
minio.internal.semtl.synology.me    -> 192.168.0.171
vm-win11.internal.semtl.synology.me -> 192.168.0.11
k8s-cp1.internal.semtl.synology.me  -> 192.168.0.181
k8s-cp2.internal.semtl.synology.me  -> 192.168.0.182
k8s-cp3.internal.semtl.synology.me  -> 192.168.0.183
k8s-w1.internal.semtl.synology.me   -> 192.168.0.191
k8s-w2.internal.semtl.synology.me   -> 192.168.0.192
k8s-cp.internal.semtl.synology.me   -> 192.168.0.180
router.internal.semtl.synology.me   -> 192.168.0.1
adguard.internal.semtl.synology.me  -> 192.168.0.2
```

권장 기준:

- 외부 서비스는 wildcard 한 건으로 reverse proxy 진입점을 단순화할 수 있음
- 내부 서비스는 wildcard보다 **서비스별 개별 레코드**를 우선 사용

## 8. `Filters -> Custom filtering rules` 최소 규칙

커스텀 규칙은 과하게 넣지 말고 최소 구성만 사용합니다.

권장 최소 규칙:

```text
||version.bind^
||id.server^
||hostname.bind^
||whoami.cloudflare^
||resolver.arpa^
||settings-win.data.microsoft.com^
||v10.events.data.microsoft.com^
||watson.telemetry.microsoft.com^
||device-metrics-us.amazon.com^
||data.mistat.xiaomi.com^
||tracking.miui.com^
||log-ingestion.samsungacr.com^
```

효과:

- DNS fingerprint 정보 노출 감소
- 외부 DNS 식별/조회용 도메인 차단

## 9. ASUS 공유기 DHCP DNS 변경

ASUS 공유기 기준 메뉴 경로:

- `LAN -> DHCP Server`

권장값:

- `DNS Server1`: `192.168.0.2`
- `DNS Server2`: `1.1.1.1`
- `Advertise router's IP in addition to user-specified DNS`: `OFF`

적용 방법:

- 공유기 설정 저장
- 클라이언트 Wi-Fi 재연결 또는 DHCP 갱신

## 10. 검증

DNS 응답 검증:

```bash
nslookup google.com 192.168.0.2
nslookup github.com 192.168.0.2
nslookup gitlab.internal.semtl.synology.me 192.168.0.2
```

정상 기준:

- 외부 도메인이 정상 조회됨
- 내부 도메인이 의도한 IP로 응답

AdGuard 기능 검증:

- 대시보드에서 `Queries`, `Blocked domains`, `Clients` 증가 확인
- `https://adguard.com/test.html`
- `https://d3ward.github.io/toolz/adblock.html`

## 11. 문제 발생 시 점검 포인트

### 11.1 클라이언트가 AdGuard를 우회하는 경우

- 공유기 DHCP DNS가 NAS IP로 적용됐는지 확인
- `DNS Server2`를 비워 두었는지 확인
- ASUS의 router DNS 광고 옵션이 꺼져 있는지 확인

### 11.2 내부 도메인 변경이 바로 반영되지 않는 경우

- AdGuard DNS cache flush
- 클라이언트 DNS 캐시 삭제
- 브라우저 DNS 캐시 삭제

### 11.3 `53` 포트 바인드 실패

- Synology `DNS Server` 패키지 중지 여부 확인
- 다른 DNS 컨테이너/Pi-hole 사용 여부 확인

## 참고

- [Synology Installation](../synology/installation.md)
