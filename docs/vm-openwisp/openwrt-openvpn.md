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

## 7. OpenWrt VPN IP 고정

`vm-openwisp`에서 Compose override와 CCD 파일을 생성합니다.

```bash
cd ~/docker/openwisp
mkdir -p customization/openvpn/ccd

cat > customization/openvpn/supervisord.conf <<'EOF'
[unix_http_server]
file=/run/supervisord.sock

[supervisorctl]
serverurl=unix:///run/supervisord.sock

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisord]
nodaemon=true
user=root
logfile=/dev/stdout
logfile_maxbytes=0
loglevel=info
pidfile=/supervisord.pid

[program:openvpn]
user=root
directory=/
command=/usr/sbin/openvpn --config %(ENV_VPN_NAME)s.conf --client-config-dir /etc/openvpn/ccd
autostart=true
autorestart=true
stopsignal=INT
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0
EOF

cat > docker-compose.override.yml <<'EOF'
services:
  openvpn:
    volumes:
      - ./customization/openvpn/supervisord.conf:/supervisord.conf:ro
      - ./customization/openvpn/ccd:/etc/openvpn/ccd:ro
EOF
```

장비 CN 이름으로 CCD 파일을 생성합니다.

```bash
cat > 'customization/openvpn/ccd/94:83:C4:AA:35:AD-GL-MT6000-L3wRcCtX' <<'EOF'
ifconfig-push 10.8.0.11 10.8.0.1
EOF

docker compose up -d --force-recreate openvpn celery celery_monitoring
docker compose exec openvpn sh -lc 'ls -l /etc/openvpn/ccd'
docker compose exec openvpn sh -lc 'grep client-config-dir /supervisord.conf'
```

OpenWrt에서 OpenVPN을 다시 연결합니다.

```sh
/etc/init.d/openvpn restart
ip addr show tun0
```

성공 기준:

- `customization/openvpn/ccd`가 호스트에 존재
- OpenVPN 컨테이너에 `/etc/openvpn/ccd` mount 확인
- OpenVPN 실행 옵션에 `--client-config-dir /etc/openvpn/ccd` 포함
- OpenWrt `tun0`에 `10.8.0.11` 할당

## 8. OpenWrt 관리 인터페이스 설정

OpenWISP agent가 `tun0`의 VPN IP를 `Management ip`로 자동 보고하도록 설정합니다.

```sh
uci set openwisp.http.management_interface='tun0'
uci commit openwisp
/etc/init.d/openwisp-config restart

uci get openwisp.http.management_interface
/usr/sbin/openwisp-get-address tun0
```

성공 기준:

- `openwisp.http.management_interface`가 `tun0`
- `/usr/sbin/openwisp-get-address tun0` 결과가 `10.8.0.11`
- OpenWISP 장비 상세의 `Management ip`가 `10.8.0.11`로 자동 갱신

OpenWISP UI의 `관리 인터페이스`에서 `openvpn:`을 선택해도 이 환경에서는 IP를
가져오지 못할 수 있습니다. `network.openvpn`이 `proto='none'`이고 실제 주소는
OpenVPN 프로세스가 `tun0`에 직접 올리기 때문입니다.

## 9. OpenWISP에서 OpenWrt 터널 확인

OpenWrt의 VPN IP는 실제 `tun0` 주소로 바꿉니다.

```bash
cd ~/docker/openwisp
docker compose exec openvpn ping -c 3 10.8.0.11
```

성공 기준:

- `vm-openwisp`에서 OpenWrt VPN IP ping 성공
- OpenWISP 장비 상세의 `Management ip`가 `10.8.0.11`
- OpenWISP `Ping` health check 성공

`Ping` health check와 `Management ip`는 즉시 갱신되지 않을 수 있습니다. OpenWrt
관리 인터페이스 설정 후 다음 agent/check 주기까지 기다린 뒤 장비 상세 페이지를
새로고침합니다.

## 참고. 초기화 및 제거

다음 명령은 OpenWrt 장비 재등록 또는 문제 복구가 필요할 때만 실행합니다.
정상 터널 확인 후 이어서 실행하는 절차가 아닙니다.

### OpenWISP 설정값 초기화

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

### OpenWrt에서 OpenWISP 제거

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
