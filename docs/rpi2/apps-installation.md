# Raspberry Pi 2 Apps Installation

## 개요

Raspberry Pi 2 기본 설치 후 Tailscale, MQTT, Node-RED, Zigbee2MQTT를
설치합니다.

기준값:

- hostname: `rpi2`
- SSH username: `semtl`
- DHCP IP: `192.168.32.11`
- Tailscale IPv4: `100.114.82.33`
- MQTT username: `admin`
- Zigbee2MQTT SLZB-06 frontend: `8099/tcp`
- Zigbee2MQTT ZBBridge Pro frontend: `8100/tcp`

## 사전 조건

- [Installation](./installation.md) 완료
- Tailscale 계정
- MQTT `<MQTT_PASSWORD>`
- Node-RED 접속용 브라우저
- Zigbee coordinator 접속 정보
- Zigbee2MQTT MQTT 계정별 비밀번호

## 1. Tailscale 설치

설치 명령:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

표시되는 인증 URL을 브라우저에서 열고 `rpi2` 등록을 승인합니다.

확인 명령:

```bash
tailscale status
tailscale ip -4
tailscale ip -6
```

관리 PC에서 실행합니다.

```bash
ssh semtl@100.114.82.33
```

정상 기준:

- `tailscale status`에 `rpi2` 표시
- `tailscale ip -4`에 `100.x.y.z` 주소 표시
- Tailscale IPv4 주소로 SSH 접속 가능

필요할 때만 route 수신을 활성화합니다.

```bash
sudo tailscale set --accept-routes=true
tailscale status
```

## 2. MQTT 브로커 설치

설치 명령:

```bash
sudo apt install -y mosquitto mosquitto-clients
sudo systemctl enable --now mosquitto
```

계정 생성:

```bash
sudo mosquitto_passwd -c /etc/mosquitto/passwd admin
```

리스너 설정:

```bash
sudo tee /etc/mosquitto/conf.d/auth.conf >/dev/null <<'EOF'
listener 1883 0.0.0.0
allow_anonymous false
password_file /etc/mosquitto/passwd
EOF
sudo systemctl restart mosquitto
```

확인 명령:

```bash
systemctl is-active mosquitto
sudo ss -lntp | grep ':1883'
```

구독 테스트:

```bash
mosquitto_sub -h localhost -u admin -P '<MQTT_PASSWORD>' -t rpi2/test
```

발행 테스트:

```bash
mosquitto_pub -h localhost -u admin -P '<MQTT_PASSWORD>' -t rpi2/test -m 'hello-rpi2'
```

관리 PC에서 발행 테스트:

```bash
mosquitto_pub -h 192.168.32.11 -u admin -P '<MQTT_PASSWORD>' -t rpi2/test -m 'hello-from-pc'
```

정상 기준:

- `mosquitto`가 `active`
- `1883/tcp` 리스너 표시
- 구독 터미널에 테스트 메시지 표시

## 3. Node-RED 설치

설치 명령:

```bash
bash <(curl -sL https://github.com/node-red/linux-installers/releases/latest/download/update-nodejs-and-nodered-deb)
```

서비스 설정:

```bash
node-red-start
sudo systemctl enable nodered.service
```

확인 명령:

```bash
systemctl is-active nodered.service
sudo ss -lntp | grep ':1880'
```

관리 PC 브라우저에서 확인합니다.

```text
http://192.168.32.11:1880
http://100.114.82.33:1880
```

정상 기준:

- `nodered.service`가 `active`
- `1880/tcp` 리스너 표시
- Node-RED 웹 에디터 접속 가능

## 4. Zigbee2MQTT 이중 인스턴스 설치

구성 목표:

```text
Raspberry Pi 2
├── Mosquitto
├── Node-RED
├── Zigbee2MQTT - SLZB-06
└── Zigbee2MQTT - Tasmota ZBBridge Pro
```

구성값:

| 구분 | SLZB-06 | Tasmota ZBBridge Pro |
| --- | --- | --- |
| 설치 경로 | `/opt/zigbee2mqtt-slzb` | `/opt/zigbee2mqtt-zbbridge-pro` |
| MQTT 계정 | `zigbee2mqtt-slzb` | `zigbee2mqtt-zbbridge-pro` |
| MQTT base topic | `zigbee2mqtt-slzb` | `zigbee2mqtt-zbbridge-pro` |
| Frontend 포트 | `8099` | `8100` |
| Coordinator | `tcp://192.168.32.191:6638` | `tcp://192.168.32.192:8888` |
| Adapter | `ember` | `zstack` |

### 4.1. 사전 확인

확인 명령:

```bash
node -v
npm -v
pnpm -v
systemctl status mosquitto --no-pager
```

Coordinator 통신 확인:

```bash
ping -c 3 192.168.32.191
ping -c 3 192.168.32.192
nc -vz 192.168.32.191 6638
nc -vz 192.168.32.192 8888
```

`nc`가 없으면 설치합니다.

```bash
sudo apt install -y netcat-openbsd
```

### 4.2. pnpm 준비

설정 명령:

```bash
sudo corepack enable
sudo corepack prepare pnpm@latest --activate
pnpm -v
```

### 4.3. Mosquitto 계정 생성

기존 `/etc/mosquitto/passwd` 파일을 유지해야 하므로 `-c` 옵션은 사용하지
않습니다.

```bash
sudo mosquitto_passwd /etc/mosquitto/passwd zigbee2mqtt-slzb
sudo mosquitto_passwd /etc/mosquitto/passwd zigbee2mqtt-zbbridge-pro
sudo systemctl restart mosquitto
```

SLZB-06 계정 테스트:

```bash
mosquitto_sub -h localhost -u zigbee2mqtt-slzb \
  -P '<SLZB_PASSWORD>' -t '#' -v
```

다른 SSH 창에서 실행합니다.

```bash
mosquitto_pub -h localhost -u zigbee2mqtt-slzb \
  -P '<SLZB_PASSWORD>' -t test/slzb -m hello
```

ZBBridge Pro 계정 테스트:

```bash
mosquitto_sub -h localhost -u zigbee2mqtt-zbbridge-pro \
  -P '<ZBBRIDGE_PASSWORD>' -t '#' -v
```

다른 SSH 창에서 실행합니다.

```bash
mosquitto_pub -h localhost -u zigbee2mqtt-zbbridge-pro \
  -P '<ZBBRIDGE_PASSWORD>' -t test/zbbridge -m hello
```

### 4.4. Zigbee2MQTT SLZB-06 설치

설치 명령:

```bash
cd /opt
sudo mkdir zigbee2mqtt-slzb
sudo chown semtl:semtl zigbee2mqtt-slzb

cd zigbee2mqtt-slzb
wget https://github.com/Koenkk/zigbee2mqtt/archive/refs/tags/2.12.0.tar.gz
tar -xzf 2.12.0.tar.gz --strip-components=1
pnpm install --frozen-lockfile
```

설정 파일 생성:

```bash
mkdir -p data
nano data/configuration.yaml
```

설정 예시:

```yaml
version: 5

homeassistant:
  enabled: true

mqtt:
  server: mqtt://127.0.0.1:1883
  user: zigbee2mqtt-slzb
  password: <SLZB_PASSWORD>
  base_topic: zigbee2mqtt-slzb

serial:
  rtscts: false
  port: tcp://192.168.32.191:6638
  adapter: ember
  baudrate: 115200

frontend:
  enabled: true
  port: 8099

advanced:
  transmit_power: 20
  log_level: info
  channel: 15
  network_key: <SLZB_NETWORK_KEY>
  pan_id: <SLZB_PAN_ID>
  ext_pan_id: <SLZB_EXT_PAN_ID>

availability:
  enabled: true

devices: {}
groups: {}
```

실행 테스트:

```bash
cd /opt/zigbee2mqtt-slzb
pnpm start
```

관리 PC 브라우저에서 확인합니다.

```text
http://192.168.32.11:8099
http://100.114.82.33:8099
```

### 4.5. Zigbee2MQTT ZBBridge Pro 설치

SLZB-06 설치본을 복사해서 사용합니다.

```bash
cd /opt
cp -a zigbee2mqtt-slzb zigbee2mqtt-zbbridge-pro
sudo chown -R semtl:semtl /opt/zigbee2mqtt-zbbridge-pro
```

설정 파일 수정:

```bash
nano /opt/zigbee2mqtt-zbbridge-pro/data/configuration.yaml
```

설정 예시:

```yaml
version: 5

homeassistant:
  enabled: true

mqtt:
  server: mqtt://127.0.0.1:1883
  user: zigbee2mqtt-zbbridge-pro
  password: <ZBBRIDGE_PASSWORD>
  base_topic: zigbee2mqtt-zbbridge-pro

serial:
  port: tcp://192.168.32.192:8888
  baudrate: 115200
  adapter: zstack

frontend:
  enabled: true
  port: 8100

advanced:
  log_level: info
  channel: 15
  pan_id: <ZBBRIDGE_PAN_ID>
  ext_pan_id: <ZBBRIDGE_EXT_PAN_ID>
  network_key: <ZBBRIDGE_NETWORK_KEY>

availability:
  enabled: true

device_options: {}
groups: {}
devices: {}
```

실행 테스트:

```bash
cd /opt/zigbee2mqtt-zbbridge-pro
pnpm start
```

관리 PC 브라우저에서 확인합니다.

```text
http://192.168.32.11:8100
http://100.114.82.33:8100
```

### 4.6. systemd 서비스 등록

SLZB-06 서비스 파일을 생성합니다.

```bash
sudo nano /etc/systemd/system/zigbee2mqtt-slzb.service
```

```ini
[Unit]
Description=Zigbee2MQTT SLZB
After=network-online.target mosquitto.service
Wants=network-online.target

[Service]
WorkingDirectory=/opt/zigbee2mqtt-slzb
ExecStart=/usr/bin/pnpm start
Restart=always
RestartSec=10
User=semtl
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
```

ZBBridge Pro 서비스 파일을 생성합니다.

```bash
sudo nano /etc/systemd/system/zigbee2mqtt-zbbridge-pro.service
```

```ini
[Unit]
Description=Zigbee2MQTT ZBBridge Pro
After=network-online.target mosquitto.service
Wants=network-online.target

[Service]
WorkingDirectory=/opt/zigbee2mqtt-zbbridge-pro
ExecStart=/usr/bin/pnpm start
Restart=always
RestartSec=10
User=semtl
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
```

서비스 적용:

```bash
sudo systemctl daemon-reload
sudo systemctl enable zigbee2mqtt-slzb
sudo systemctl enable zigbee2mqtt-zbbridge-pro
sudo systemctl start zigbee2mqtt-slzb
sudo systemctl start zigbee2mqtt-zbbridge-pro
```

상태 확인:

```bash
systemctl status zigbee2mqtt-slzb --no-pager
systemctl status zigbee2mqtt-zbbridge-pro --no-pager
```

로그 확인:

```bash
journalctl -u zigbee2mqtt-slzb -f
journalctl -u zigbee2mqtt-zbbridge-pro -f
```

### 4.7. 재부팅 테스트

재부팅:

```bash
sudo reboot
```

재접속 후 확인:

```bash
systemctl status mosquitto --no-pager
systemctl status zigbee2mqtt-slzb --no-pager
systemctl status zigbee2mqtt-zbbridge-pro --no-pager
```

관리 PC 브라우저에서 확인합니다.

```text
http://192.168.32.11:8099
http://192.168.32.11:8100
http://100.114.82.33:8099
http://100.114.82.33:8100
```

정상 기준:

- `mosquitto`가 `active`
- `zigbee2mqtt-slzb`가 `active`
- `zigbee2mqtt-zbbridge-pro`가 `active`
- 두 Zigbee2MQTT frontend 접속 가능

### 4.8. Home Assistant 이전 순서

Pi2에서 두 Zigbee2MQTT가 정상 동작하기 전에는 Home Assistant Add-on을
삭제하지 않습니다.

이전 순서:

1. Pi2 Mosquitto 정상 확인
1. Pi2 Zigbee2MQTT SLZB-06 정상 확인
1. Pi2 Zigbee2MQTT ZBBridge Pro 정상 확인
1. Home Assistant MQTT Integration을 Pi2 Mosquitto로 연결
1. Home Assistant에서 장치 자동 발견 확인
1. 기존 Home Assistant Zigbee2MQTT Add-on 중지
1. 기존 Home Assistant Mosquitto Broker Add-on 중지
1. 문제 없으면 기존 Add-on 삭제

주의 사항:

- 같은 Coordinator에 Zigbee2MQTT 두 개가 동시에 접속하면 안 됩니다.
- Home Assistant Add-on Zigbee2MQTT와 Pi2 Zigbee2MQTT가 같은 SLZB-06
  또는 ZBBridge Pro에 동시에 연결되면 충돌합니다.

### 4.9. 관리 명령어

시작:

```bash
sudo systemctl start zigbee2mqtt-slzb
sudo systemctl start zigbee2mqtt-zbbridge-pro
```

중지:

```bash
sudo systemctl stop zigbee2mqtt-slzb
sudo systemctl stop zigbee2mqtt-zbbridge-pro
```

재시작:

```bash
sudo systemctl restart zigbee2mqtt-slzb
sudo systemctl restart zigbee2mqtt-zbbridge-pro
```

자동 실행 해제:

```bash
sudo systemctl disable zigbee2mqtt-slzb
sudo systemctl disable zigbee2mqtt-zbbridge-pro
```

### 4.10. 백업 대상

반드시 백업할 파일:

```text
/opt/zigbee2mqtt-slzb/data/configuration.yaml
/opt/zigbee2mqtt-slzb/data/database.db
/opt/zigbee2mqtt-zbbridge-pro/data/configuration.yaml
/opt/zigbee2mqtt-zbbridge-pro/data/database.db
/etc/mosquitto/passwd
/etc/mosquitto/conf.d/
```

간단 백업:

```bash
tar -czvf ~/zigbee2mqtt-backup-$(date +%Y%m%d-%H%M).tar.gz \
  /opt/zigbee2mqtt-slzb/data \
  /opt/zigbee2mqtt-zbbridge-pro/data \
  /etc/mosquitto/passwd \
  /etc/mosquitto/conf.d
```

## 참고

- Tailscale Linux installation:
  `https://tailscale.com/docs/install/linux`
- Node-RED Running on Raspberry Pi:
  `https://nodered.org/docs/getting-started/raspberrypi`
- Zigbee2MQTT Getting started:
  `https://www.zigbee2mqtt.io/guide/getting-started/`
