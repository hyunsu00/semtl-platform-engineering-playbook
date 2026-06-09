# Raspberry Pi 2 Apps Installation

## 개요

Raspberry Pi 2 기본 설치 후 Tailscale, MQTT, Node-RED를 설치합니다.

기준값:

- hostname: `rpi2`
- SSH username: `semtl`
- DHCP IP: `192.168.32.11`
- Tailscale IPv4: `100.114.82.33`
- MQTT username: `admin`

## 사전 조건

- [Installation](./installation.md) 완료
- Tailscale 계정
- MQTT `<MQTT_PASSWORD>`
- Node-RED 접속용 브라우저

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

## 참고

- Tailscale Linux installation:
  `https://tailscale.com/docs/install/linux`
- Node-RED Running on Raspberry Pi:
  `https://nodered.org/docs/getting-started/raspberrypi`
