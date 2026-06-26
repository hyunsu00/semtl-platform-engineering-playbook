# VM OpenWISP OpenWrt Wi-Fi VLAN 43 Configuration

OpenWISP에서 VLAN 43 Wi-Fi를 2.4GHz/5GHz SSID로 추가하는 절차입니다.

## 운영값

- OpenWISP dashboard: `https://openwisp.semtl.synology.me`
- VLAN 43 Wi-Fi 템플릿: `semtlx-openwrt-wifi43`
- VLAN 43 인터페이스: `wifi43`
- VLAN 43 device: `br-lan.43`
- VLAN 43 DHCP 대역: `192.168.43.x`
- 2.4GHz Wi-Fi section: `wifi43_radio0`
- 5GHz Wi-Fi section: `wifi43_radio1`
- 2.4GHz ifname: `wlan43_2g`
- 5GHz ifname: `wlan43_5g`
- OpenWrt uplink bridge: `br-lan`

## 1. 템플릿 생성

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

`Configuration`:

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

## 2. 장비에 적용

```text
Devices
-> <OpenWrt 장비>
-> Configuration
-> Templates
-> semtlx-openwrt-wifi 유지
-> semtlx-openwrt-wifi43 추가 선택
-> Save
```

## 3. 적용 확인

```sh
/etc/init.d/openwisp-config restart
sleep 20

uci show network.wifi43
uci show wireless | grep -E "wireless\\.wifi43_radio[01]\\.(ssid|network|encryption|key)"
ip link show br-lan.43
```

성공 기준:

- `network.wifi43.device='br-lan.43'`
- `network.wifi43.proto='none'`
- `wireless.wifi43_radio0.network='wifi43'`
- `wireless.wifi43_radio1.network='wifi43'`
- `wireless.wifi43_radio0.encryption='psk2'`
- `wireless.wifi43_radio1.encryption='psk2'`
- `br-lan.43` 링크가 `UP`
- `SEMTLX-WiFi`, `SEMTLX-WiFi-5G` 클라이언트가 `192.168.43.x` 주소를 받음
