# Synology Tailscale Installation

## 개요

이 문서는 `Synology DSM7` 환경에서 `Tailscale`을 설치하고
`192.168.0.0/24`를 subnet router로 광고해 외부에서 `192.168.0.x` 대역에
접근하는 가장 단순한 절차만 정리합니다.

## 아키텍처와 예시 값

- Synology NAS IP: `192.168.0.2`
- Synology 관리 UI: `https://192.168.0.2:5001`
- Tailscale 장치 이름: `semtl-nas`
- Tailscale IPv4 예시: `100.81.55.127`
- Tailscale IPv6 예시: `fd7a:115c:a1e0::2b37:377f`
- Tailscale FQDN 예시: `semtl-nas.taila9290d.ts.net`
- 예시 로컬 LAN 대역: `192.168.0.0/24`
- Tailscale 주소 대역: `100.64.0.0/10`
- 예시 광고 라우트: `192.168.0.0/24`

## 사전 조건

- DSM 관리자 권한
- `패키지 센터` 사용 가능 상태
- Tailscale에 로그인할 계정 또는 SSO 제공자 준비
- subnet router 광고를 위한 SSH 접근 권한

## 1. Package Center로 Tailscale 설치

절차:

1. DSM 로그인
1. `패키지 센터` 열기
1. `Tailscale` 검색
1. `설치`

설치 후:

1. `Tailscale` 앱 실행
1. 브라우저 로그인 창이 열리면 원하는 계정 또는 SSO로 로그인
1. Tailnet 인증 완료

정상 기준:

- Synology NAS가 Tailscale `Machines` 목록에 표시됨
- 예시 기준 `semtl-nas`, `100.81.55.127`, `semtl-nas.taila9290d.ts.net` 확인 가능

## 2. Synology를 Subnet Router로 사용

Tailscale을 설치한 뒤 외부 기기에서 `192.168.0.x` 대역으로 직접 접근하려면
Synology NAS가 subnet router 역할을 하도록 로컬 대역을 광고해야 합니다.

예시:

```bash
sudo tailscale set --advertise-routes=192.168.0.0/24
```

주의:

- Tailscale만 설치한 상태로는 NAS 자신만 접근되고 `192.168.0.x` 대역 전체는 자동으로 열리지 않습니다.
- subnet router 승인 전에는 Tailscale Admin Console에 `Pending approval`로 보일 수 있습니다.

그 다음 Tailscale Admin Console에서:

1. `Machines`
1. 해당 Synology 장치 선택
1. `Subnets`
1. `Edit route settings`
1. 광고한 라우트 승인

승인 후 확인 예시:

- 외부 기기에서 `http://192.168.0.1`
- 외부 기기에서 `ping 192.168.0.1`
- 외부 기기에서 `192.168.0.x` 대역의 내부 장비 접속
- Tailscale UI 기준 `Subnet router`에 `1 route` 표시
- `192.168.0.0/24` 상태가 `Approved`

### 2-1. 여러 VLAN 대역을 함께 광고하는 경우

예시:

```bash
sudo tailscale set --advertise-routes=192.168.1.0/24,192.168.10.0/24,192.168.110.0/24
```

또는 대역을 크게 묶는 예시:

```bash
sudo tailscale set --advertise-routes=192.168.0.0/16
```

전제 조건:

- Synology NAS가 각 VLAN 대역과 실제로 통신 가능해야 합니다.
- 광고 후 Tailscale Admin Console에서 각 route를 승인해야 합니다.

### 2-2. FQDN으로 접근하고 싶을 때

`vm-win11.semtl.synology.me` 같은 이름으로 접근하고 싶다면 Tailscale subnet router와
별개로 이름 해석이 필요합니다.

권장 순서:

1. 로컬 DNS가 있다면 `vm-win11.semtl.synology.me -> 192.168.0.x` A 레코드 등록
1. 외부 Tailscale 기기에서도 같은 이름을 쓰려면 MagicDNS 또는 각 기기의 `hosts` 파일을 별도로 관리

주의:

- 장비 내부의 `/etc/hosts`만 수정하면 그 장비 자신만 해당 이름을 해석합니다.
- 다른 PC가 같은 이름으로 접근하려면 그 PC가 사용할 DNS 서버 또는 `hosts` 파일에 동일한 매핑이 필요합니다.

## 3. outbound 연결 활성화

Synology DSM7에서 NAS 내부 패키지나 컨테이너가 Tailscale 네트워크로 나가야 하면
작업 스케줄러로 `configure-host`를 등록합니다.

경로:

1. DSM `Control Panel`
1. `Task Scheduler`
1. `Create`
1. `Triggered Task`
1. `User-defined script`

권장값:

- 작업 이름: `tailscale-configure-host`
- 사용자: `root`
- 이벤트: `Boot-up`
- 활성화: `켜기`

사용자 정의 스크립트:

```bash
/var/packages/Tailscale/target/bin/tailscale configure-host
synosystemctl restart pkgctl-Tailscale.service
```

즉시 한 번 적용하려면 SSH에서 아래를 실행합니다.

```bash
sudo /var/packages/Tailscale/target/bin/tailscale configure-host
sudo synosystemctl restart pkgctl-Tailscale.service
```

실행 중 아래와 비슷한 메시지가 나오면 정상입니다.

```text
Done. To restart Tailscale to use the new permissions, run:
  sudo synosystemctl restart pkgctl-Tailscale.service
```

적용 확인:

```bash
tailscale status
tailscale ip -4
tailscale ip -6
```

확인 기준:

- `tailscale status`에 Synology 장치와 peer 목록이 표시됨
- `tailscale ip -4` 결과가 예시 기준 `100.81.55.127`
- `tailscale ip -6` 결과가 예시 기준 `fd7a:115c:a1e0::2b37:377f`
- 필요 시 Synology NAS에서 다른 tailnet 장비의 `100.x.x.x` 주소로 접근 테스트

## 4. 선택 사항: 업데이트

패키지 센터 버전이 최신 릴리즈보다 늦을 수 있어 필요하면 업데이트 작업을 추가할 수 있습니다.

경로:

1. DSM `Control Panel`
1. `Task Scheduler`
1. `Create`
1. `Scheduled Task`
1. `User-defined script`

사용자 정의 스크립트:

```bash
tailscale update --yes
```

## 참고

- Tailscale Synology 가이드:
  `https://tailscale.com/docs/integrations/synology`
- Tailscale Subnet Routers:
  `https://tailscale.com/kb/1019/subnets`
- Tailscale Subnet Router Quick Guide:
  `https://tailscale.com/kb/1406/quick-guide-subnets`
