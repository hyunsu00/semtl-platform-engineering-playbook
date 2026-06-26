# VM OpenWISP OpenWrt Wi-Fi Configuration

OpenWISP에서 OpenWrt 장비의 Wi-Fi SSID를 중앙 관리하는 절차입니다.
OpenWrt 장비 등록은 [OpenWrt OpenVPN](./openwrt-openvpn.md)을 먼저 완료합니다.

## 운영값

- OpenWISP dashboard: `https://openwisp.semtl.synology.me`
- Wi-Fi 템플릿: `semtlx-openwrt-wifi`
- 2.4GHz radio: `radio0`
- 5GHz radio: `radio1`
- 2.4GHz Wi-Fi section: `default_radio0`
- 5GHz Wi-Fi section: `default_radio1`
- 연결 네트워크: `lan`
- 2.4GHz 변수: `wifi_2g_ssid`, `wifi_2g_password`
- 5GHz 변수: `wifi_5g_ssid`, `wifi_5g_password`

## 1. OpenWrt 무선 장치 확인

```sh
uci show wireless
wifi status
```

성공 기준:

- `wireless.radio0` 존재
- `wireless.radio1` 존재
- `wireless.default_radio0` 존재
- `wireless.default_radio1` 존재

## 2. Wi-Fi 템플릿 생성

```text
Configurations
-> Templates
-> Add template
```

입력값:

- Name: `semtlx-openwrt-wifi`
- Type: `Generic`
- Backend: `OpenWrt`
- Enabled by default: 체크 안 함
- Required: 체크 안 함

`Configuration`:

```json
{
  "radios": [
    {
      "name": "radio0",
      "driver": "mac80211",
      "protocol": "802.11ax",
      "channel": 0,
      "band": "2g",
      "channel_width": 20,
      "disabled": false
    },
    {
      "name": "radio1",
      "driver": "mac80211",
      "protocol": "802.11ax",
      "channel": 0,
      "band": "5g",
      "channel_width": 80,
      "disabled": false
    }
  ],
  "interfaces": [
    {
      "type": "wireless",
      "name": "wlan0",
      "wireless": {
        "id": "default_radio0",
        "mode": "access_point",
        "radio": "radio0",
        "ssid": "{{wifi_2g_ssid}}",
        "network": [
          "lan"
        ],
        "encryption": {
          "protocol": "wpa2_personal",
          "key": "{{wifi_2g_password}}",
          "cipher": "auto"
        }
      }
    },
    {
      "type": "wireless",
      "name": "wlan1",
      "wireless": {
        "id": "default_radio1",
        "mode": "access_point",
        "radio": "radio1",
        "ssid": "{{wifi_5g_ssid}}",
        "network": [
          "lan"
        ],
        "encryption": {
          "protocol": "wpa2_personal",
          "key": "{{wifi_5g_password}}",
          "cipher": "auto"
        }
      }
    }
  ]
}
```

`Configuration variables`:

```json
{
  "wifi_2g_ssid": "SEMTLX-WiFi",
  "wifi_2g_password": "change-this-2g-password",
  "wifi_5g_ssid": "SEMTLX-WiFi-5G",
  "wifi_5g_password": "change-this-5g-password"
}
```

성공 기준:

- `Preview configuration` 성공
- `radio0.disabled`가 `0`
- `radio1.disabled`가 `0`
- `default_radio0.ssid`가 `wifi_2g_ssid` 값으로 렌더링됨
- `default_radio1.ssid`가 `wifi_5g_ssid` 값으로 렌더링됨
- `default_radio0.key`가 `wifi_2g_password` 값으로 렌더링됨
- `default_radio1.key`가 `wifi_5g_password` 값으로 렌더링됨

Wi-Fi 암호는 문서와 Git에 실제 값을 남기지 않습니다.

## 3. 장비에 템플릿 적용

```text
Devices
-> <OpenWrt 장비>
-> Configuration
-> Templates
-> semtlx-openwrt-wifi 선택
-> Save
```

장비별 값이 필요하면 장비의 `Configuration variables`에 입력합니다.

```json
{
  "wifi_2g_ssid": "SEMTLX-AP-01",
  "wifi_2g_password": "device-specific-2g-password",
  "wifi_5g_ssid": "SEMTLX-AP-01-5G",
  "wifi_5g_password": "device-specific-5g-password"
}
```

성공 기준:

- 장비 설정 상태가 `applied` 또는 동기화 대기 상태
- `semtlx-openwrt-wifi` 템플릿이 장비에 연결됨
- 장비별 변수가 필요한 경우 4개 변수 모두 입력됨

## 4. OpenWrt 적용 확인

```sh
/etc/init.d/openwisp-config restart
sleep 20

uci show wireless | grep -E "wireless\\.radio[01]\\.disabled|wireless\\.default_radio[01]\\.(ssid|key|device|network|mode)"
wifi status
```

성공 기준:

- `wireless.radio0.disabled='0'`
- `wireless.radio1.disabled='0'`
- `wireless.default_radio0.device='radio0'`
- `wireless.default_radio1.device='radio1'`
- `wireless.default_radio0.network='lan'`
- `wireless.default_radio1.network='lan'`
- `wireless.default_radio0.mode='ap'`
- `wireless.default_radio1.mode='ap'`
- `wireless.default_radio0.ssid`가 2.4GHz SSID 값과 일치
- `wireless.default_radio1.ssid`가 5GHz SSID 값과 일치
- `wifi status`에서 `radio0`, `radio1`이 `up`

## 5. 이전 추가 section 정리

`id` 없이 템플릿을 적용한 적이 있으면 `wifi_wlan0`, `wifi_wlan1`이 남을 수
있습니다. `default_radio0`, `default_radio1` 적용이 확인된 뒤 제거합니다.

```sh
uci show wireless | grep -E "wireless\\.wifi_wlan[01]="

uci -q delete wireless.wifi_wlan0
uci -q delete wireless.wifi_wlan1
uci commit wireless
wifi reload
```

성공 기준:

- `uci show wireless | grep -E "wireless\\.wifi_wlan[01]="` 결과 없음
- LuCI 무선 개요에 운영 SSID 2개만 표시됨
- SSH 또는 VPN 관리 접속이 유지됨

## 6. OpenWISP 세션 확인

```text
Monitoring
-> WiFi Sessions
```

성공 기준:

- 연결된 클라이언트 MAC 주소 표시
- 장비 또는 SSID 기준으로 세션 필터링 가능
- 클라이언트 접속 이력 수집

## 트러블슈팅

### SSID가 보이지 않음

확인:

```sh
uci show wireless
wifi status
logread -e hostapd
```

성공 기준을 만족하지 않으면 `radio`, `band`, `disabled`, `ssid`, `key`, `network`
값을 다시 확인합니다.

### 설정이 반영되지 않음

확인:

```sh
uci show openwisp
logread -e openwisp
/etc/init.d/openwisp-config restart
```

성공 기준:

- `openwisp.http.uuid` 존재
- `openwisp.http.key` 존재
- OpenWISP 장비 상세의 configuration status에 오류 없음

## 참고

- [OpenWISP Wi-Fi Access Point SSID 문서](https://openwisp.io/docs/25.10/tutorials/wifi-access-point.html)
- [OpenWISP Configuration Templates 문서](https://openwisp.io/docs/25.10/controller/user/templates.html)
- [OpenWISP Configuration Variables 문서](https://openwisp.io/docs/25.10/controller/user/variables.html)
