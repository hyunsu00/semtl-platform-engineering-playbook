# VM OpenWISP OpenWrt Wi-Fi Configuration

OpenWISP에서 OpenWrt 기본 `openwrt` SSID를 비활성화하고 radio만 활성 상태로
관리하는 템플릿입니다. 실제 운영 SSID는 VLAN 42/43 템플릿에서 추가합니다.

OpenWrt 장비 등록은 [OpenWrt OpenVPN](./openwrt-openvpn.md)을 먼저 완료합니다.

## 운영값

- OpenWISP dashboard: `https://openwisp.semtl.synology.me`
- Wi-Fi 템플릿: `semtlx-openwrt-wifi`
- 2.4GHz radio: `radio0`
- 5GHz radio: `radio1`
- 2.4GHz 기본 section: `default_radio0`
- 5GHz 기본 section: `default_radio1`

## 1. 템플릿 생성

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
      "disabled": true,
      "wireless": {
        "id": "default_radio0",
        "mode": "access_point",
        "radio": "radio0",
        "ssid": "{{wifi_2g_ssid}}",
        "network": [
          "lan"
        ],
        "encryption": {
          "protocol": "none"
        }
      }
    },
    {
      "type": "wireless",
      "name": "wlan1",
      "disabled": true,
      "wireless": {
        "id": "default_radio1",
        "mode": "access_point",
        "radio": "radio1",
        "ssid": "{{wifi_5g_ssid}}",
        "network": [
          "lan"
        ],
        "encryption": {
          "protocol": "none"
        }
      }
    }
  ]
}
```

`Configuration variables`:

```json
{
  "wifi_2g_ssid": "openwrt",
  "wifi_5g_ssid": "openwrt"
}
```

## 2. 장비에 적용

```text
Devices
-> <OpenWrt 장비>
-> Configuration
-> Templates
-> semtlx-openwrt-wifi 선택
-> Save
```

## 3. 적용 확인

```sh
/etc/init.d/openwisp-config restart
sleep 20

uci show wireless | grep -E "wireless\\.radio[01]\\.disabled|wireless\\.default_radio[01]\\.(ssid|encryption|device|network|mode|disabled)"
wifi status
```

성공 기준:

- `wireless.radio0.disabled='0'`
- `wireless.radio1.disabled='0'`
- `wireless.default_radio0.disabled='1'`
- `wireless.default_radio1.disabled='1'`
- `wireless.default_radio0.encryption='none'`
- `wireless.default_radio1.encryption='none'`

## 다음 단계

- [OpenWrt Wi-Fi VLAN 43 설정](./openwrt-wifi-vlan43.md)
- [OpenWrt Wi-Fi VLAN 42 설정](./openwrt-wifi-vlan42.md)
