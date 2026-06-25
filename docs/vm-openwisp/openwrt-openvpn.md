# VM OpenWISP OpenWrt OpenVPN

OpenWISP 서버 설치 후 OpenWrt 장비 등록과 OpenVPN 관리 터널을 확인합니다.
서버 설치는 [설치 문서](./installation.md)를 먼저 완료합니다.

## 운영값

- OpenWISP dashboard: `https://openwisp.semtl.synology.me`
- OpenVPN endpoint: `openwisp-vpn.semtl.synology.me:11194/udp`
- OpenVPN internal port: `1194/udp`
- VPN-client 템플릿: `semtl-openwrt-vpn`
- OpenVPN 서버 터널 IP: `10.8.0.1`

## 1. OpenWrt 필수 패키지 확인

```sh
apk update
apk add openvpn-openssl
apk add luci-app-openvpn
which openvpn
openvpn --version
ls -l /etc/init.d/openvpn
```

성공 기준:

- `/usr/sbin/openvpn` 존재
- `/etc/init.d/openvpn` 존재

## 2. VPN-client 템플릿 확인

```text
Network Configuration
-> Templates
-> semtl-openwrt-vpn
-> Preview configuration
```

성공 기준:

- `semtl-openwrt-vpn` 템플릿 존재
- Preview configuration에 아래 remote 값 표시

```text
list remote 'openwisp-vpn.semtl.synology.me 11194'
```

## 3. OpenWrt 등록 정보 확인

```sh
uci show openwisp
ls /etc/config | grep openwisp
ls /etc/init.d | grep -i openwisp
```

성공 기준:

- `openwisp.http.uuid` 값 존재
- `openwisp.http.key` 값 존재
- `openwisp.http.url='https://openwisp.semtl.synology.me'`
- `openwisp-config` 서비스 존재
- `openwisp-monitoring` 서비스 존재

## 4. 설정 다시 내려받기

```sh
/etc/init.d/openwisp-config restart
sleep 15
uci get openvpn.default.remote
```

성공 기준:

```text
openwisp-vpn.semtl.synology.me 11194
```

## 5. OpenVPN 클라이언트 실행

```sh
/etc/init.d/openvpn enable
/etc/init.d/openvpn restart
uci get openvpn.default.remote
logread -e openvpn
ip addr show tun0
ping -c 3 10.8.0.1
```

성공 기준:

- `openvpn.default.remote`가 `openwisp-vpn.semtl.synology.me 11194`
- `tun0` 인터페이스가 `UP`
- OpenWrt에 `10.8.0.x` 터널 IP 할당
- `10.8.0.1` ping 성공

## 6. OpenWrt 방화벽 설정

```sh
uci add firewall zone
uci set firewall.@zone[-1].name='openwisp_vpn'
uci set firewall.@zone[-1].input='ACCEPT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='REJECT'
uci add_list firewall.@zone[-1].device='tun0'
uci commit firewall
/etc/init.d/firewall restart
uci show firewall | grep openwisp_vpn
uci show firewall | grep tun0
```

성공 기준:

- `openwisp_vpn` zone의 `input`이 `ACCEPT`
- `openwisp_vpn` zone에 `tun0` 장치 포함

## 7. OpenWISP에서 OpenWrt 터널 확인

OpenWrt의 VPN IP는 실제 `tun0` 주소로 바꿉니다.

```bash
cd ~/docker/openwisp
docker compose exec openvpn ping -c 3 10.8.0.4
```

성공 기준:

- `vm-openwisp`에서 OpenWrt VPN IP ping 성공
- OpenWISP 장비 상세의 `Management ip`에 OpenWrt VPN IP 입력
- OpenWISP `Ping` health check 성공

## 8. OpenWISP 설정값 초기화

```sh
/etc/init.d/openwisp-config stop
/etc/init.d/openwisp-monitoring stop

uci -q delete openwisp.http.uuid
uci -q delete openwisp.http.key
uci commit openwisp

rm -rf /etc/openwisp

uci show openwisp
test ! -d /etc/openwisp && echo "openwisp state cleared"
```

성공 기준:

- `openwisp.http.uuid` 값 없음
- `openwisp.http.key` 값 없음
- `/etc/openwisp` 없음
- OpenWISP dashboard에서 장비를 새로 등록할 준비 완료

## 9. OpenWrt에서 OpenWISP 제거

```sh
/etc/init.d/openwisp-config stop
/etc/init.d/openwisp-config disable
/etc/init.d/openwisp-monitoring stop
/etc/init.d/openwisp-monitoring disable

apk del openwisp-config openwisp-monitoring

rm -f /etc/config/openwisp
rm -rf /etc/openwisp

ls /etc/init.d | grep -i openwisp
ls /etc/config | grep openwisp
apk list --installed | grep openwisp
```

성공 기준:

- `openwisp-config` 서비스 없음
- `openwisp-monitoring` 서비스 없음
- `/etc/config/openwisp` 없음
- `/etc/openwisp` 없음
- 설치된 `openwisp` 패키지 없음
