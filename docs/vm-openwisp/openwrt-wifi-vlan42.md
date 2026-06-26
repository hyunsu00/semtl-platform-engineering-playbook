# VM OpenWISP OpenWrt Wi-Fi VLAN 42 Configuration

OpenWISP에서 VLAN 42 IoT Wi-Fi를 2.4GHz 전용 SSID로 추가하는 절차입니다.
VLAN 43 Wi-Fi는 [OpenWrt Wi-Fi VLAN 43 설정](./openwrt-wifi-vlan43.md)을 사용합니다.

## 운영값

- OpenWISP dashboard: `https://openwisp.semtl.synology.me`
- VLAN 42 Wi-Fi 템플릿: `semtlx-openwrt-wifi42`
- VLAN 42 인터페이스: `wifi42`
- VLAN 42 device: `br-lan.42`
- VLAN 42 DHCP 대역: `192.168.42.x`
- 2.4GHz Wi-Fi section: `wifi42_radio0`
- 2.4GHz ifname: `wlan42_2g`
- OpenWrt uplink bridge: `br-lan`

## 1. 템플릿 생성

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

`Configuration`:

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

## 2. 장비에 적용

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

## 3. 적용 확인

```sh
/etc/init.d/openwisp-config restart
sleep 20

uci show network.wifi42
uci show wireless.wifi42_radio0
ip link show br-lan.42
```

성공 기준:

- `network.wifi42.device='br-lan.42'`
- `network.wifi42.proto='none'`
- `wireless.wifi42_radio0.network='wifi42'`
- `wireless.wifi42_radio0.encryption='psk2'`
- `br-lan.42` 링크가 `UP`
- `SEMTLX-IoT` 클라이언트가 `192.168.42.x` 주소를 받음
