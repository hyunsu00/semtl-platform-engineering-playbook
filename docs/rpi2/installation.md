# Raspberry Pi 2 Installation

## 개요

Raspberry Pi 2에 `Raspberry Pi OS (Legacy, 32-bit) Lite`를 설치하고 기본
운영 패키지를 구성합니다.

기준값:

- hostname: `rpi2`
- username: `semtl`
- DHCP IP: `192.168.32.11`
- Wi-Fi SSID: `DJCAMP-IoT`
- timezone: `Asia/Seoul`

## 사전 조건

- Raspberry Pi 2
- microSD 카드, 권장 `16GB` 이상
- 유선 LAN 케이블
- USB Wi-Fi 어댑터, 선택
- Raspberry Pi Imager 실행 PC
- SSH 접속용 터미널

## 1. Raspberry Pi Imager 설치

PC에서 Raspberry Pi Imager를 설치하고 실행합니다.

## 2. OS 이미지 선택

Raspberry Pi Imager에서 선택합니다.

1. `CHOOSE DEVICE` 선택
1. `Raspberry Pi 2` 선택
1. `CHOOSE OS` 선택
1. `Raspberry Pi OS (other)` 선택
1. `Raspberry Pi OS (Legacy, 32-bit) Lite` 선택
1. `CHOOSE STORAGE` 선택
1. 대상 microSD 카드 선택

## 3. OS Customisation 설정

`OS Customisation`에서 설정합니다.

- Hostname: `rpi2`
- Username: `semtl`
- Password: `<RPI2_PASSWORD>`
- Time zone: `Asia/Seoul`
- SSH: 활성화
- SSH authentication: password 또는 public key

유선 LAN 기준이면 Wi-Fi 설정은 비워둡니다.

USB Wi-Fi 어댑터를 사용할 때만 설정합니다.

- SSID: `<WIFI_SSID>`
- Password: `<WIFI_PASSWORD>`
- Wireless LAN country: `KR`

## 4. microSD 카드 기록

1. `Next` 또는 `Write` 선택
1. OS Customisation 적용 확인
1. 기록 대상 microSD 카드 확인
1. 쓰기와 검증 완료 대기
1. microSD 카드 안전 제거

## 5. 첫 부팅과 SSH 접속

1. Raspberry Pi 2에 microSD 카드 장착
1. 유선 LAN 연결
1. 전원 연결
1. 부팅 완료까지 2-3분 대기
1. 공유기 DHCP 목록에서 `rpi2` IP 확인

관리 PC에서 접속합니다.

```bash
ssh semtl@192.168.32.11
```

## 6. 기본 업데이트

설치 명령:

```bash
sudo apt update
sudo apt full-upgrade -y
sudo reboot
```

재접속:

```bash
ssh semtl@192.168.32.11
```

## 7. 기본 운영 설정

확인 명령:

```bash
hostnamectl
timedatectl
```

설정 명령:

```bash
sudo timedatectl set-timezone Asia/Seoul
sudo raspi-config
```

`raspi-config` 확인 항목:

- hostname
- SSH 활성화
- timezone, locale, keyboard
- filesystem expand

## 8. 기본 패키지 설치

설치 명령:

```bash
sudo apt install -y vim curl wget git htop tmux ca-certificates chrony
```

확인 명령:

```bash
git --version
tmux -V
```

## 9. Chrony 설정

설정 명령:

```bash
sudo systemctl enable --now chrony
```

확인 명령:

```bash
systemctl is-active chrony
chronyc tracking
chronyc sources -v
timedatectl
```

정상 기준:

- `chrony`가 `active`
- `timedatectl`에 `System clock synchronized: yes` 표시

## 10. Swap 1GB 설정

확인 명령:

```bash
free -h
sudo swapon --show
```

설정 명령:

```bash
sudo sed -i.bak 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=1024/' /etc/dphys-swapfile
sudo systemctl restart dphys-swapfile
```

확인 명령:

```bash
free -h
sudo swapon --show
```

정상 기준:

- Swap 크기가 `1G` 수준으로 표시됨

## 11. 기본 설치 확인

Raspberry Pi 2에서 실행합니다.

```bash
cat /etc/os-release
uname -a
hostname -I
systemctl is-active ssh
systemctl is-active chrony
chronyc tracking
free -h
sudo swapon --show
ping -c 3 8.8.8.8
ping -c 3 raspberrypi.com
```

관리 PC에서 실행합니다.

```bash
ssh semtl@192.168.32.11
```

정상 기준:

- SSH 서비스가 `active`
- Chrony 서비스가 `active`
- Swap 크기가 `1G` 수준으로 표시됨
- IP와 도메인 ping 성공
- 관리 PC에서 SSH 접속 가능

## 12. USB Wi-Fi 설정

Bookworm 이상 또는 `NetworkManager`가 활성화된 이미지에서 사용합니다.

WLAN 국가 설정:

```bash
sudo raspi-config
sudo reboot
```

`raspi-config` 메뉴:

```text
Localisation Options
WLAN Country
KR (Korea, Republic of)
```

재접속:

```bash
ssh semtl@192.168.32.11
```

확인 명령:

```bash
rfkill list
systemctl is-active NetworkManager
systemctl is-enabled NetworkManager
nmcli dev wifi list
```

`NetworkManager`가 없으면 `raspi-config` 또는 Imager Wi-Fi 설정을 우선
사용합니다.

Wi-Fi 연결:

```bash
sudo nmcli dev wifi connect "DJCAMP-IoT" password "<WIFI_PASSWORD>"
```

연결 확인:

```bash
nmcli device status
iw dev wlan0 link
hostname -I
ip addr show wlan0
```

저장된 연결 확인:

```bash
nmcli connection show
```

자동 연결 비활성화:

```bash
sudo nmcli connection modify "DJCAMP-IoT" connection.autoconnect no
nmcli connection show "DJCAMP-IoT" | grep autoconnect
```

Wi-Fi 절전 비활성화:

```bash
sudo nmcli connection modify "DJCAMP-IoT" 802-11-wireless.powersave disable
nmcli connection show "DJCAMP-IoT" | grep powersave
```

수동 연결:

```bash
sudo rfkill unblock all
sudo nmcli radio wifi on
sudo nmcli connection up "DJCAMP-IoT"
```

수동 해제:

```bash
sudo nmcli connection down "DJCAMP-IoT"
```

정상 기준:

- `rfkill list`의 `Soft blocked`, `Hard blocked`가 `no`
- `NetworkManager`가 `active`, `enabled`
- `wlan0`이 `connected`
- `hostname -I` 또는 `ip addr show wlan0`에 Wi-Fi IP 표시

## 13. 추가 앱 설치

기본 설치 후 추가 앱은 [Apps Installation](./apps-installation.md)을 따릅니다.

## 14. 종료

종료 명령:

```bash
sudo shutdown -h now
```

## 참고

- Raspberry Pi Software
- Raspberry Pi OS downloads
- Raspberry Pi Getting started
