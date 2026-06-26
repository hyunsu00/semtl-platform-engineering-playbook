# VM OpenWISP OpenWrt Wi-Fi VLAN 43 Configuration

OpenWISP에서 OpenWrt 장비에 VLAN 43 Wi-Fi SSID를 추가하는 절차입니다.
기본 `default_radio0`, `default_radio1` section은 `openwrt` SSID 비활성화 용도로
유지하고, VLAN 43은 새 무선 section으로 추가합니다.

기본 Wi-Fi 템플릿은 [OpenWrt Wi-Fi 설정](./openwrt-wifi-configuration.md)을
먼저 생성합니다. VLAN 42 SSID를 추가로 운영하는 절차는
[OpenWrt Wi-Fi VLAN 42 설정](./openwrt-wifi-vlan42.md)을 사용합니다.

## 운영값

- OpenWISP dashboard: `https://openwisp.semtl.synology.me`
- 기본 Wi-Fi 템플릿: `semtlx-openwrt-wifi`
- VLAN 43 Wi-Fi 템플릿: `semtlx-openwrt-wifi43`
- VLAN 43 인터페이스: `wifi43`
- VLAN ID: `43`
- VLAN 43 DHCP 대역: `192.168.43.x`
- 기존 관리 대역: `192.168.41.x`
- OpenWrt uplink bridge: `br-lan`
- 2.4GHz VLAN 43 Wi-Fi section: `wifi43_radio0`
- 5GHz VLAN 43 Wi-Fi section: `wifi43_radio1`
- 2.4GHz 변수: `wifi43_2g_ssid`, `wifi43_2g_password`
- 5GHz 변수: `wifi43_5g_ssid`, `wifi43_5g_password`
- 무선 보안: WPA2-PSK

## 1. 전제 조건 확인

VLAN 43은 기존 기본 Wi-Fi에 추가되는 SSID입니다. 기본 Wi-Fi 템플릿을 대체하지
않고 별도 템플릿으로 추가 적용합니다.

전제 조건:

- Omada 스위치/라우터에서 AP가 연결된 포트에 VLAN 43이 tagged로 전달됨
- AP 관리망 `192.168.41.x`는 기존 untagged/native 또는 별도 관리 VLAN으로 유지됨
- VLAN 43 DHCP 서버는 Omada 쪽에서 제공하고 OpenWrt에서는 DHCP 서버를 켜지 않음
- 기본 템플릿 `semtlx-openwrt-wifi`가 생성되어 있음

OpenWrt uplink 장치명을 확인합니다.

```sh
uci show network | grep -E "network\\..*\\.device|network\\..*\\.ifname"
ip link show
```

성공 기준:

- AP의 uplink bridge 또는 device 이름 확인
- 기본값과 다르면 이후 예시의 `br-lan`을 실제 장치명으로 교체

GL-MT6000에서 다음처럼 보이면 기본 예시 그대로 `br-lan`을 사용합니다.

```text
network.lan.device='br-lan'
lan5@eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> ... master br-lan state UP
br-lan: <BROADCAST,MULTICAST,UP,LOWER_UP> ... state UP
```

이 경우 AP가 연결된 실제 포트는 `lan5`이고, OpenWrt의 논리 uplink bridge는
`br-lan`입니다. VLAN 43 인터페이스는 `lan5`가 아니라 `br-lan` 위에 생성합니다.

## 2. VLAN 43 템플릿 생성

VLAN 43은 기존 Wi-Fi section을 바꾸는 구성이 아니라 새 SSID를 추가하는 구성입니다.
기존 기본 Wi-Fi 템플릿을 clone하지 않고 새 템플릿으로 생성합니다.

```text
Configurations
-> Templates
-> Add template
```

입력값:

- Name: `semtlx-openwrt-wifi43`
- Type: `Generic`
- Backend: `OpenWrt`
- Enabled by default: 체크 안 함
- Required: 체크 안 함

## 3. Configuration 입력

`Configuration`에는 VLAN 43 인터페이스와 VLAN 43용 새 무선 section만 넣습니다.
`default_radio0`, `default_radio1`은 기본 `openwrt` SSID 비활성화 용도로 사용하므로
다시 사용하지 않습니다.

GL-MT6000처럼 `network.lan.device='br-lan'`으로 확인된 장비는 그대로 붙여넣습니다.
AP의 uplink 장치명이 `br-lan`이 아니면 `interfaces` 첫 항목의 `name`만 실제
장치명으로 바꿉니다.

```json
{
  "interfaces": [
    {
      "type": "ethernet",
      "name": "br-lan.43",
      "network": "wifi43"
    },
    {
      "type": "wireless",
      "name": "wlan43_2g",
      "wireless": {
        "id": "wifi43_radio0",
        "mode": "access_point",
        "radio": "radio0",
        "ssid": "{{wifi43_2g_ssid}}",
        "network": [
          "wifi43"
        ],
        "encryption": {
          "protocol": "wpa2_personal",
          "key": "{{wifi43_2g_password}}",
          "cipher": "auto"
        }
      }
    },
    {
      "type": "wireless",
      "name": "wlan43_5g",
      "wireless": {
        "id": "wifi43_radio1",
        "mode": "access_point",
        "radio": "radio1",
        "ssid": "{{wifi43_5g_ssid}}",
        "network": [
          "wifi43"
        ],
        "encryption": {
          "protocol": "wpa2_personal",
          "key": "{{wifi43_5g_password}}",
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
  "wifi43_2g_ssid": "SEMTLX-WiFi",
  "wifi43_2g_password": "change-this-vlan43-2g-password",
  "wifi43_5g_ssid": "SEMTLX-WiFi-5G",
  "wifi43_5g_password": "change-this-vlan43-5g-password"
}
```

Wi-Fi 암호는 문서와 Git에 실제 값을 남기지 않습니다.
VLAN 42, VLAN 43, 기본 Wi-Fi 템플릿을 같은 장비에 함께 적용하므로 변수명은 VLAN별로
분리합니다. 같은 변수명을 재사용하면 장비 공통 `Configuration variables`에서 값이
충돌할 수 있습니다.

OpenWrt에 렌더링되면 VLAN 43 인터페이스는 DHCP 주소를 직접 받는 용도가 아니라
무선 클라이언트를 상위 Omada VLAN으로 브리지하는 용도입니다. 생성 결과는 대략
다음 형태가 됩니다.

```text
config interface 'wifi43'
        option device 'br-lan.43'
        option proto 'none'

config wifi-iface 'wifi43_radio0'
        option network 'wifi43'

config wifi-iface 'wifi43_radio1'
        option network 'wifi43'
```

## 4. 테스트 장비에 추가 적용

기본 Wi-Fi 템플릿을 제거하지 않고 VLAN 43 템플릿을 추가로 선택합니다.

```text
Devices
-> <OpenWrt 장비>
-> Configuration
-> Templates
-> semtlx-openwrt-wifi 유지
-> semtlx-openwrt-wifi43 추가 선택
-> Save
```

성공 기준:

- 장비 설정 상태가 `applied` 또는 동기화 대기 상태
- `semtlx-openwrt-wifi` 템플릿이 유지됨
- `semtlx-openwrt-wifi43` 템플릿이 추가됨

## 5. OpenWrt 적용 확인

```sh
/etc/init.d/openwisp-config restart
sleep 20

uci show network.wifi43
uci show wireless | grep -E "wireless\\.(default_radio[01]|wifi43_radio[01])\\.(network|encryption|key)"
ip link show br-lan.43
```

성공 기준:

- `network.wifi43.proto='none'`
- `network.wifi43.device='br-lan.43'`
- `wireless.default_radio0.disabled='1'`
- `wireless.default_radio1.disabled='1'`
- `wireless.wifi43_radio0.network='wifi43'`
- `wireless.wifi43_radio1.network='wifi43'`
- `wireless.wifi43_radio0.encryption`이 WPA2 개인키 방식으로 설정됨
- `wireless.wifi43_radio1.encryption`이 WPA2 개인키 방식으로 설정됨
- `wireless.wifi43_radio0.key`가 설정됨
- `wireless.wifi43_radio1.key`가 설정됨
- `br-lan.43` 링크가 존재함
- VLAN 43 Wi-Fi 클라이언트가 Omada DHCP에서 `192.168.43.x` 주소를 받음
- AP 관리 접속은 기존 `192.168.41.x`에서 유지됨

## 6. 기존 대체 구성에서 추가 구성으로 변경

이전에 `default_radio0`, `default_radio1`을 `wifi43`으로 바꿔 적용했다면,
VLAN 43 템플릿을 위의 추가 구성으로 교체하고 기본 Wi-Fi 템플릿을 함께 적용합니다.

확인:

```sh
uci show wireless | grep -E "wireless\\.(default_radio[01]|wifi43_radio[01])\\.(network|encryption|key)"
```

최종 기대값:

```text
wireless.default_radio0.disabled='1'
wireless.default_radio1.disabled='1'
wireless.wifi43_radio0.network='wifi43'
wireless.wifi43_radio1.network='wifi43'
```

## 트러블슈팅

### VLAN 43 SSID가 보이지 않음

확인:

```sh
uci show wireless | grep -E "wireless\\.wifi43_radio[01]"
wifi status
logread -e hostapd
```

조치:

- `wifi43_radio0`, `wifi43_radio1` section이 생성됐는지 확인
- `radio0`, `radio1`이 기본 Wi-Fi 템플릿에서 활성화되어 있는지 확인
- 장비에 `semtlx-openwrt-wifi43` 템플릿이 추가 적용됐는지 확인

### VLAN 43 클라이언트가 IP를 받지 못함

확인:

```sh
ip link show br-lan.43
logread -e netifd
```

조치:

- Omada에서 AP 연결 포트에 VLAN 43 tagged가 설정됐는지 확인
- OpenWrt uplink 장치명이 `br-lan`이 맞는지 확인
- Omada의 VLAN 43 DHCP 서버가 동작 중인지 확인

## 참고

- [OpenWrt Wi-Fi 설정](./openwrt-wifi-configuration.md)
- [OpenWrt Wi-Fi VLAN 42 설정](./openwrt-wifi-vlan42.md)
- [OpenWISP Configuration Templates 문서](https://openwisp.io/docs/25.10/controller/user/templates.html)
