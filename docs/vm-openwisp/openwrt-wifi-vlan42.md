# VM OpenWISP OpenWrt Wi-Fi VLAN 42 Configuration

OpenWISP에서 OpenWrt 장비에 VLAN 42 Wi-Fi SSID를 추가하는 절차입니다.
기본 Wi-Fi와 VLAN 43 Wi-Fi를 유지하면서 새 무선 section을 추가합니다.

VLAN 43 기본 구성은 [OpenWrt Wi-Fi VLAN 43 설정](./openwrt-wifi-vlan43.md)을
먼저 완료합니다.

## 운영값

- OpenWISP dashboard: `https://openwisp.semtl.synology.me`
- VLAN 42 Wi-Fi 템플릿: `semtlx-openwrt-wifi42`
- VLAN 42 인터페이스: `wifi42`
- VLAN ID: `42`
- VLAN 42 DHCP 대역: `192.168.42.x`
- VLAN 43 Wi-Fi 템플릿: `semtlx-openwrt-wifi43`
- VLAN 43 인터페이스: `wifi43`
- 2.4GHz VLAN 43 Wi-Fi section: `wifi43_radio0`
- 5GHz VLAN 43 Wi-Fi section: `wifi43_radio1`
- OpenWrt uplink bridge: `br-lan`
- 2.4GHz VLAN 42 Wi-Fi section: `wifi42_radio0`
- 2.4GHz 변수: `wifi42_2g_ssid`, `wifi42_2g_password`
- 5GHz VLAN 42 Wi-Fi: 사용하지 않음
- 무선 보안: WPA2-PSK

## 1. 전제 조건 확인

VLAN 42는 기존 VLAN 43 Wi-Fi에 추가되는 SSID입니다. VLAN 43 템플릿을 대체하지
않고 별도 템플릿으로 추가 적용합니다.

전제 조건:

- Omada 스위치/라우터에서 AP가 연결된 포트에 VLAN 42가 tagged로 전달됨
- VLAN 42 DHCP 서버는 Omada 쪽에서 제공함
- OpenWrt에서는 VLAN 42 DHCP 서버를 켜지 않음
- 기존 VLAN 43 Wi-Fi가 추가 SSID 방식으로 정상 동작 중임
- AP의 uplink bridge가 `br-lan`으로 확인됨

확인:

```sh
uci show network | grep -E "network\\..*\\.device|network\\..*\\.ifname"
uci show network.wifi43
uci show wireless | grep -E "wireless\\.wifi43_radio[01]\\.(network|encryption|key)"
```

성공 기준:

- `network.lan.device='br-lan'`
- `network.wifi43.device='br-lan.43'`
- `wireless.wifi43_radio0.network='wifi43'`
- `wireless.wifi43_radio1.network='wifi43'`

## 2. VLAN 42 템플릿 생성

VLAN 42는 기존 Wi-Fi section을 바꾸는 구성이 아니라 새 SSID를 추가하는 구성입니다.
기존 VLAN 43 템플릿을 clone하지 않고 새 템플릿으로 생성합니다.

```text
Configurations
-> Templates
-> Add template
```

입력값:

- Name: `semtlx-openwrt-wifi42`
- Type: `Generic`
- Backend: `OpenWrt`
- Enabled by default: 체크 안 함
- Required: 체크 안 함

## 3. Configuration 입력

`Configuration`에는 VLAN 42 인터페이스와 VLAN 42용 2.4GHz 무선 section만 넣습니다.
`default_radio0`, `default_radio1`은 기본 `openwrt` SSID 비활성화 용도로 사용하고,
`wifi43_radio0`, `wifi43_radio1`은 VLAN 43에서 사용하므로 다시 사용하지 않습니다.

```json
{
  "interfaces": [
    {
      "type": "ethernet",
      "name": "br-lan.42",
      "network": "wifi42"
    },
    {
      "type": "wireless",
      "name": "wlan42_2g",
      "wireless": {
        "id": "wifi42_radio0",
        "mode": "access_point",
        "radio": "radio0",
        "ssid": "{{wifi42_2g_ssid}}",
        "network": [
          "wifi42"
        ],
        "encryption": {
          "protocol": "wpa2_personal",
          "key": "{{wifi42_2g_password}}",
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
  "wifi42_2g_ssid": "SEMTLX-IoT",
  "wifi42_2g_password": "change-this-vlan42-2g-password"
}
```

Wi-Fi 암호는 문서와 Git에 실제 값을 남기지 않습니다.
VLAN 42, VLAN 43, 기본 Wi-Fi 템플릿을 같은 장비에 함께 적용하므로 변수명은 VLAN별로
분리합니다. 같은 변수명을 재사용하면 장비 공통 `Configuration variables`에서 값이
충돌할 수 있습니다.

## 4. 테스트 장비에 추가 적용

VLAN 43 템플릿을 제거하지 않고 VLAN 42 템플릿을 추가로 선택합니다.

```text
Devices
-> <OpenWrt 장비>
-> Configuration
-> Templates
-> semtlx-openwrt-wifi 유지
-> semtlx-openwrt-wifi43 유지
-> semtlx-openwrt-wifi42 추가 선택
-> Save
```

성공 기준:

- 장비 설정 상태가 `applied` 또는 동기화 대기 상태
- `semtlx-openwrt-wifi` 템플릿이 유지됨
- `semtlx-openwrt-wifi43` 템플릿이 유지됨
- `semtlx-openwrt-wifi42` 템플릿이 추가됨

## 5. OpenWrt 적용 확인

```sh
/etc/init.d/openwisp-config restart
sleep 20

uci show network.wifi42
uci show network.wifi43
uci show network | grep -E "br-lan\\.42|vlan_br_lan_42|wifi42"
uci show wireless | grep -E "wireless\\.(default_radio[01]|wifi42_radio0|wifi43_radio[01])\\.(network|encryption|key)"
ip link show br-lan.42
ip link show br-lan.43
```

성공 기준:

- `network.wifi42.proto='none'`
- `network.wifi42.device='br-lan.42'`
- `network.wifi43.device='br-lan.43'`
- `wireless.default_radio0.disabled='1'`
- `wireless.default_radio1.disabled='1'`
- `wireless.wifi42_radio0.network='wifi42'`
- `wireless.wifi42_radio0.encryption`이 WPA2 개인키 방식으로 설정됨
- `wireless.wifi42_radio0.key`가 설정됨
- `wireless.wifi43_radio0.network='wifi43'`
- `wireless.wifi43_radio1.network='wifi43'`
- VLAN 42 Wi-Fi 클라이언트가 Omada DHCP에서 `192.168.42.x` 주소를 받음
- VLAN 43 Wi-Fi 클라이언트가 Omada DHCP에서 `192.168.43.x` 주소를 받음

## 트러블슈팅

### VLAN 42 SSID가 보이지 않음

확인:

```sh
uci show wireless | grep -E "wireless\\.wifi42_radio0"
wifi status
logread -e hostapd
```

조치:

- `wifi42_radio0` section이 생성됐는지 확인
- `radio0`이 기본 Wi-Fi 또는 VLAN 43 템플릿에서 활성화되어 있는지 확인
- 장비에 `semtlx-openwrt-wifi42` 템플릿이 추가 적용됐는지 확인

### VLAN 42 클라이언트가 IP를 받지 못함

확인:

```sh
uci show network.wifi42
uci show wireless.wifi42_radio0
ip link show br-lan.42
logread -e netifd
```

조치:

- `network.wifi42`가 없으면 `semtlx-openwrt-wifi42` 템플릿의 `Configuration`에
  VLAN 42 인터페이스 블록이 포함됐는지 확인합니다.
- Omada에서 AP 연결 포트에 VLAN 42 tagged가 설정됐는지 확인
- Omada의 VLAN 42 DHCP 서버가 동작 중인지 확인
- OpenWrt uplink 장치명이 `br-lan`이 맞는지 확인

`wifi42_radio0`은 있는데 `network.wifi42`와 `br-lan.42`가 없으면 무선 SSID만
생성되고 VLAN 42 인터페이스가 생성되지 않은 상태입니다. 먼저 실제 렌더링된 VLAN 42
인터페이스 이름을 확인합니다.

```sh
uci show network | grep -E "br-lan\\.42|vlan_br_lan_42|wifi42"
```

`network.vlan_br_lan_42`가 보이면 OpenWISP가 VLAN 42 인터페이스를 `wifi42`가 아니라
자동 이름으로 생성한 상태입니다. 이 경우 `wireless.wifi42_radio0.network`를
`vlan_br_lan_42`로 맞추거나, 템플릿에서 VLAN 42 인터페이스 이름을 장비에 맞게
일관되게 관리합니다.

아무 결과도 없으면 OpenWISP에서 `semtlx-openwrt-wifi42` 템플릿을 열고
`Configuration`의 `interfaces` 배열에 다음 항목이 있는지 확인합니다.

```json
{
  "type": "ethernet",
  "name": "br-lan.42",
  "network": "wifi42"
}
```

수정 후 장비 설정을 다시 저장하고 동기화합니다.

```sh
/etc/init.d/openwisp-config restart
sleep 20
uci show network.wifi42
ip link show br-lan.42
```

## 참고

- [OpenWrt Wi-Fi 설정](./openwrt-wifi-configuration.md)
- [OpenWrt Wi-Fi VLAN 43 설정](./openwrt-wifi-vlan43.md)
- [OpenWISP Configuration Templates 문서](https://openwisp.io/docs/25.10/controller/user/templates.html)
