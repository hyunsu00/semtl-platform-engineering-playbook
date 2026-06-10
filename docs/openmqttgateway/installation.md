# OpenMQTTGateway Installation

## 개요

ESP32-DevKitC-VIE 개발보드와 CC1101 `433MHz` RF 모듈을 이용하여
OpenMQTTGateway를 구축합니다. MQTT를 통해 `433MHz` RF 리모컨 신호를
수신하고 SmartThings, Node-RED, Home Assistant에서 활용할 수 있도록
구성합니다.

기준값:

- ESP32 개발보드: `ESP32-DevKitC-VIE`
- ESP32 모듈: `ESP32-WROVER-IE`
- RF 모듈: `CC1101 433MHz`
- OpenMQTTGateway environment: `esp32dev-multi_receiver`
- OpenMQTTGateway version: `v1.8.1`
- MQTT username: `openmqttgateway`
- MQTT base topic: `openmqttgateway/`
- Gateway name: `rf433-gw`
- RF frequency: `433.920`

## 사전 조건

- ESP32-DevKitC-VIE 개발보드
- CC1101 `433MHz` RF 모듈
- `433MHz` SMA 안테나
- USB 데이터 케이블
- OpenMQTTGateway Web Installer 접속용 브라우저
- Mosquitto MQTT Broker
- MQTT `<OPENMQTTGATEWAY_PASSWORD>`

## 1. 시스템 구성

구성 목표:

```text
433MHz RF remote
  -> CC1101 433MHz
  -> ESP32-WROVER-IE
  -> OpenMQTTGateway
  -> Mosquitto MQTT Broker
  -> SmartThings / Node-RED / Home Assistant
```

ESP32 특징:

- 듀얼코어 Xtensa LX6
- PSRAM 탑재
- Wi-Fi `2.4GHz`
- Bluetooth
- 외장 안테나 `IPEX/U.FL`

RF 모듈:

- 모델명: `CC1101 433MHz Wireless Module With SMA Antenna`
- 용도: Arduino 호환 wireless transceiver module
- 주파수: `433.92MHz`
- 안테나: `433MHz` SMA 안테나

## 2. OpenMQTTGateway 설치

PC 브라우저에서 Web Installer에 접속합니다.

```text
https://docs.openmqttgateway.com/upload/web-install.html
```

설치 절차:

1. ESP32를 USB 케이블로 PC에 연결
1. Web Installer에서 시리얼 포트 선택
1. Environment로 `esp32dev-multi_receiver` 선택
1. 설치 진행
1. 설치 완료 후 ESP32 재부팅

## 3. CC1101 배선

아래 배선은 실제 수신 성공이 확인된 구성입니다.

| CC1101 핀 순서 | 기능 | ESP32 |
| --- | --- | --- |
| 1 | GND | GND |
| 2 | VCC | 3V3 |
| 3 | GDO0 | GPIO12 |
| 4 | CSN | GPIO5 |
| 5 | SCK | GPIO18 |
| 6 | MOSI | GPIO23 |
| 7 | MISO | GPIO19 |
| 8 | GDO2 | GPIO27 |

배선도:

```text
CC1101                    ESP32

GND       ------------->  GND
VCC       ------------->  3V3

GDO0      ------------->  GPIO12
CSN       ------------->  GPIO5

SCK       ------------->  GPIO18
MOSI      ------------->  GPIO23
MISO      ------------->  GPIO19

GDO2      ------------->  GPIO27
```

## 4. OpenMQTTGateway 접속

ESP32 부팅 후 웹 브라우저에서 접속합니다.

```text
http://<ESP32_IP>
```

예시:

```text
http://192.168.32.164
```

## 5. Mosquitto MQTT Broker 설정

Mosquitto Broker는 이미 `1883/tcp` 리스너와 비밀번호 인증이 설정되어
있다고 가정합니다.

MQTT 계정 생성:

```bash
sudo mosquitto_passwd /etc/mosquitto/passwd openmqttgateway
```

`/etc/mosquitto/passwd` 파일을 새로 만들 때만 `-c` 옵션을 사용합니다.
기존 계정 파일이 있으면 `-c` 옵션을 사용하지 않습니다.

적용:

```bash
sudo systemctl restart mosquitto
```

확인:

```bash
systemctl status mosquitto --no-pager
```

인증 테스트:

```bash
mosquitto_sub -h localhost -u openmqttgateway \
  -P '<OPENMQTTGATEWAY_PASSWORD>' -t 'openmqttgateway/#' -v
```

정상 기준:

- `mosquitto`가 `active`
- `1883/tcp` 리스너가 활성화됨
- `openmqttgateway` 계정으로 MQTT 인증 가능

## 6. MQTT 설정

OpenMQTTGateway 웹 UI에서 MQTT를 설정합니다.

| 항목 | 값 |
| --- | --- |
| MQTT Server | `<MQTT_BROKER_IP>` |
| MQTT Port | `1883` |
| MQTT Username | `openmqttgateway` |
| MQTT Password | `<OPENMQTTGATEWAY_PASSWORD>` |
| MQTT Secure Connection | `OFF` |

MQTT Broker가 Raspberry Pi 2에 있으면 MQTT Server 값으로
`192.168.32.11`을 사용합니다.

## 7. Gateway 설정

OpenMQTTGateway 웹 UI에서 Gateway 값을 설정합니다.

| 항목 | 값 |
| --- | --- |
| MQTT Base Topic | `openmqttgateway/` |
| Gateway Name | `rf433-gw` |

최종 MQTT Topic 구조:

```text
openmqttgateway/rf433-gw/#
```

## 8. Discovery 설정

Home Assistant 사용 가능성을 고려하여 MQTT Discovery를 활성화합니다.

| 항목 | 값 |
| --- | --- |
| MQTT Discovery | `ON` |
| MQTT Discovery Prefix | `homeassistant` |

Discovery 활성화 이유:

- Home Assistant 자동 등록에 사용
- 현재 SmartThings만 사용해도 향후 Home Assistant 연동 가능
- 비활성화하지 않아도 성능 영향이 거의 없음

## 9. RF 설정

OpenMQTTGateway 웹 UI에서 RF 값을 설정합니다.

| 항목 | 값 |
| --- | --- |
| Frequency | `433.920` |
| Active Library | `RF` |

라이브러리 설정:

- `RF`: 사용
- `RF2`: 사용 안 함
- `RTL_433`: 사용 안 함

Sonoff RM433R2 리모컨으로 정상 수신을 확인합니다.

## 10. 정상 동작 확인

CC1101 연결 확인 메시지:

```text
C1101 spi Connection OK
```

MQTT Topic 확인:

| 용도 | Topic |
| --- | --- |
| 시스템 상태 | `openmqttgateway/rf433-gw/SYStoMQTT` |
| 온라인 상태 | `openmqttgateway/rf433-gw/LWT` |
| RF 수신 | `openmqttgateway/rf433-gw/433toMQTT/13145953` |

MQTT 수신 예시:

```text
openmqttgateway/rf433-gw/433toMQTT/13145953
```

Payload 예시:

```json
{
  "value": 13145953,
  "protocol": 1,
  "length": 24,
  "delay": 245,
  "frequency": 433.92
}
```

## 11. Node-RED 구독 예시

전체 OpenMQTTGateway 구독:

```text
openmqttgateway/rf433-gw/#
```

`433MHz` 수신만 구독:

```text
openmqttgateway/rf433-gw/433toMQTT/#
```

특정 버튼만 구독:

```text
openmqttgateway/rf433-gw/433toMQTT/13145953
```

## 12. Sonoff RF Bridge 코드 비교

| Sonoff RF Bridge HEX | OpenMQTTGateway DEC |
| --- | --- |
| `C89661` | `13145953` |
| `C89662` | `13145954` |
| `C89663` | `13145955` |
| `C89664` | `13145956` |
| `C89665` | `13145957` |
| `C89768` | `13145960` |
| `C89769` | `13145961` |
| `C8976C` | `13145964` |

## 13. 검증 완료 기준

동작 확인 항목:

- ESP32-DevKitC-VIE 정상 동작
- ESP32-WROVER-IE 정상 동작
- CC1101 SPI 통신 정상
- OpenMQTTGateway `v1.8.1` 정상 동작
- Mosquitto MQTT 인증 연동 정상
- MQTT Topic 송신 정상
- Sonoff RM433R2 수신 정상
- SmartThings MQTT Device Creator 연동 가능
- Node-RED 연동 가능

최종 구성:

```text
ESP32-DevKitC-VIE
  + ESP32-WROVER-IE
  + CC1101 433MHz Wireless Module
  + OpenMQTTGateway v1.8.1
  + Mosquitto MQTT Broker
  + SmartThings MQTT Device Creator
```

## 참고

- OpenMQTTGateway Web Installer:
  `https://docs.openmqttgateway.com/upload/web-install.html`
