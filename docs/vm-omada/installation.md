# VM Omada Installation

## 개요

이 문서는 Ubuntu 22.04 Server 기반 `vm-omada` VM에
TP-Link Omada Software Controller를 직접 설치하는 절차를 정리합니다.

이 문서의 목표는 아래 상태까지 한 번에 만드는 것입니다.

- VM 이름: `vm-omada`
- 운영 계정: `semtl`
- 접속 방식: `semtl` 계정 + `sudo`
- OpenJDK 17, `jsvc`, MongoDB 8 설치 완료
- Omada Controller `.deb` 패키지 설치 완료
- 브라우저에서 Omada 초기 설정 화면 접속 가능

이 문서는 Ubuntu 22.04 Server 기준의 최소 설치 절차만 남기고,
Docker 우회 구성은 제외합니다.

## 사용 시점

- Omada Controller를 전용 VM에 직접 설치하려는 경우
- AP, Switch, Gateway를 중앙에서 관리하려는 경우
- Docker 대신 운영체제 서비스 기준으로 단순하게 유지하려는 경우

## 최종 성공 기준

- Ubuntu 22.04 VM 생성 완료
- `qemu-guest-agent`와 `openssh-server` 설치 완료
- `ssh semtl@<VM-IP>` 접속 가능
- `mongod` 서비스가 `active` 상태
- `tpeap status`에서 Controller가 실행 중으로 표시됨
- `https://<VM-IP>:8043` 접속 가능

예시 운영값:

- hostname: `vm-omada`
- IP: `192.168.0.20`
- Omada URL: `https://192.168.0.20:8043`

## 사전 조건

- 가상화 환경에서 Ubuntu 22.04 Server VM 생성 가능 상태
- Omada 장비가 도달 가능한 네트워크 대역 확보
- Omada Controller에 사용할 고정 IP 또는 DHCP 예약 준비
- VM용 스토리지 확보

## 1. VM 생성

Ubuntu 22.04 Server 기반 VM을 생성합니다.

권장 기준:

- Name: `VM-OMADA`
- OS: `Ubuntu 22.04`
- Disk: `40GB`
- Network: 운영 LAN
- IPv4: 고정 IP 또는 DHCP 예약

권장 리소스:

- vCPU: `2`
- RAM: `4GB`
- Disk: `40GB`

운영 메모:

- Omada Controller 자체는 가벼운 편이지만 로그와 백업을 고려하면 `40GB`가 무난합니다.
- 사이트 수나 장비 수가 많으면 `RAM 8GB`까지 여유를 두는 편이 안전합니다.

## 2. Ubuntu 기본 설정

VM 콘솔 또는 초기 SSH로 접속한 뒤 기본 패키지를 설치합니다.

```bash
sudo apt update
sudo apt install -y qemu-guest-agent sudo ca-certificates curl gnupg openssh-server
sudo systemctl enable --now qemu-guest-agent ssh
```

검증:

```bash
systemctl status qemu-guest-agent --no-pager
systemctl status ssh --no-pager
```

## 3. SSH 접속 확인

다른 관리 PC에서 접속을 확인합니다.

```bash
ssh semtl@192.168.0.20
sudo whoami
```

기대 결과:

- `root`

## 4. 시간 점검

인증서와 패키지 설치 문제를 줄이려면 시간을 먼저 확인합니다.

```bash
timedatectl
```

권장 기준:

- `System clock synchronized: yes`
- `NTP service: active`

## 5. Java와 JSVC 설치

TP-Link 공식 가이드 기준으로
Omada Software Controller `v5.15.20` 이상은 Java 17 이상이 필요합니다.
Ubuntu 22.04에서는 OpenJDK 17과 `jsvc`를 설치합니다.

```bash
sudo apt update
sudo apt install -y openjdk-17-jre-headless jsvc
java -version
jsvc -version
```

기대 결과:

- `java -version` 출력에 `17`
- `jsvc -version` 정상 출력

## 6. MongoDB 8 설치

TP-Link 공식 가이드 기준으로
Omada Software Controller `v5.15.20` 이상은 MongoDB 8까지 지원합니다.
Ubuntu 22.04에서는 MongoDB 공식 `jammy` 저장소 기준으로 설치합니다.

```bash
sudo apt update
sudo apt install -y gnupg curl

curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | \
  sudo gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor

echo "deb [ arch=amd64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] \
https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/8.0 multiverse" | \
  sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list

sudo apt update
sudo apt install -y mongodb-org
sudo systemctl enable --now mongod
```

검증:

```bash
systemctl status mongod --no-pager
mongod --version
```

기대 결과:

- `mongod` 서비스가 `active (running)`

## 7. Omada 패키지 다운로드

Omada 공식 다운로드 페이지에서 Linux x64 `.deb` 패키지를 받습니다.
2026-04-14 기준 공식 다운로드 페이지의 최신 Linux 버전은 `6.2.0.17`입니다.

공식 다운로드 페이지:

```text
https://support.omadanetworks.com/download/software/omada-controller/
```

작업 디렉터리 예시:

```bash
mkdir -p ~/downloads/omada
cd ~/downloads/omada
```

다운로드 파일 예시:

- `Omada_SDN_Controller_v6.2.0.17_linux_x64.deb`

`curl` 예시:

```bash
cd ~/downloads/omada
curl -fLo Omada_SDN_Controller_v6.2.0.17_linux_x64.deb \
  "https://static.tp-link.com/upload/software/2026/202604/20260402/Omada_Network_Application_v6.2.0.17_linux_x64_20260331104746.deb"
```

`wget` 예시:

```bash
cd ~/downloads/omada
wget -O Omada_SDN_Controller_v6.2.0.17_linux_x64.deb \
  "https://static.tp-link.com/upload/software/2026/202604/20260402/Omada_Network_Application_v6.2.0.17_linux_x64_20260331104746.deb"
```

저장 경로 예시:

- `/home/semtl/downloads/omada/Omada_SDN_Controller_v6.2.0.17_linux_x64.deb`

운영 메모:

- 버전은 계속 바뀌므로 실제 배포 시점에는 공식 다운로드 페이지에서 최신 파일명을 다시 확인합니다.
- 최신 버전 확인은 Omada 공식 다운로드 페이지와 공개 API 응답을 기준으로 합니다.

## 8. Omada Controller 설치

다운로드한 `.deb` 파일이 있는 디렉터리에서 설치합니다.

```bash
cd ~/downloads/omada
sudo dpkg --ignore-depends=jsvc -i Omada_SDN_Controller_v6.2.0.17_linux_x64.deb
sudo apt -f install -y
```

검증:

```bash
sudo tpeap status
```

운영 메모:

- TP-Link 공식 가이드는 OpenJDK 11 이상과 `jsvc 1.1.0` 이상을 사용하는 경우
  `--ignore-depends=jsvc` 옵션 사용을 안내합니다.
- 설치 직후 바로 `running`이 보이지 않으면 수십 초 정도 대기 후 다시 확인합니다.

## 9. 서비스 상태 확인

Omada Controller는 `tpeap` 명령으로 상태를 확인합니다.

```bash
sudo tpeap start
sudo tpeap status
curl -I http://localhost:8088
curl -kI https://localhost:8043
ss -lntp | grep -E '8043|8088'
```

기대 결과:

- `sudo tpeap status`가 실행 중 상태 표시
- `http://localhost:8088` 요청 시 `302` 응답과 `https://localhost:8043/` 리다이렉트 확인
- `8043/tcp`, `8088/tcp` LISTEN 확인

## 10. 웹 초기 설정

브라우저에서 아래 주소로 접속합니다.

```text
https://192.168.0.20:8043
```

초기 접속 시 확인할 항목:

- 자체 서명 인증서 경고 확인 후 진입
- 관리자 계정 생성
- Site 이름 생성
- Omada 장비 Adopt 준비

운영 메모:

- 첫 기동 직후에는 초기화에 수 분 걸릴 수 있습니다.
- `http://192.168.0.20:8088`로 접속하면 보통 `https://192.168.0.20:8043/`로 이동합니다.
- 접속이 되지 않으면 `sudo tpeap status`, `curl -I http://localhost:8088`,
  `curl -kI https://localhost:8043`를 먼저 확인합니다.

## 11. 백업 기준점 생성

초기 설정 화면 접속까지 확인되면 VM 스냅샷이나 백업 기준점을 남깁니다.

권장 시점:

- SSH 접속 확인 완료
- Java, `jsvc`, MongoDB 설치 완료
- Omada Controller 패키지 설치 완료
- `sudo tpeap status` 확인 완료
- `https://<VM-IP>:8043` 접속 확인 완료

Synology NAS 작업 기록 예시:

```text
#2. VM-OMADA [SEMTL-NAS]
- OpenJDK 17, jsvc 설치
==> sudo apt install -y openjdk-17-jre-headless jsvc
- MongoDB 8 설치
==> sudo apt install -y mongodb-org
==> sudo systemctl enable --now mongod
- Omada 설치 파일 다운로드
==> curl -fLo Omada_SDN_Controller_v6.2.0.17_linux_x64.deb \
    "https://static.tp-link.com/upload/software/2026/202604/20260402/Omada_Network_Application_v6.2.0.17_linux_x64_20260331104746.deb"
- Omada Controller 설치
==> sudo dpkg --ignore-depends=jsvc -i Omada_SDN_Controller_v6.2.0.17_linux_x64.deb
==> sudo apt -f install -y
- Omada 서비스 확인
==> sudo tpeap status
==> curl -I http://localhost:8088
==> curl -kI https://localhost:8043
- 접속 확인
==> https://192.168.0.20:8043
```

운영 메모:

- `MAC 주소`는 실제 VM 값으로 바꿔 적습니다.
- 비밀번호는 문서에 그대로 적지 않고 마스킹하거나 별도 안전한 위치에만 보관합니다.
- 스냅샷 설명에는 `IP: 192.168.0.20`도 함께 남기면 추적이 편합니다.
- `Omada URL: https://192.168.0.20:8043`도 같이 적어두면 확인이 쉽습니다.

## 12. 트러블슈팅

### `tpeap status`가 정상 상태가 아님

- `mongod` 서비스가 먼저 떠 있는지 확인합니다.
- `java -version`이 17 이상인지 확인합니다.
- 설치한 Omada 패키지 버전과 의존성 조합이 맞는지 다시 확인합니다.

### `https://<VM-IP>:8043` 접속이 되지 않음

- `sudo tpeap status`로 컨트롤러 상태를 먼저 확인합니다.
- `curl -I http://localhost:8088`로 `302`와
  `Location: https://localhost:8043/`가 보이는지 확인합니다.
- `curl -kI https://localhost:8043`로 HTTPS 응답 여부를 확인합니다.
- `ss -lntp | grep -E '8043|8088'`로 포트 바인딩 여부를 확인합니다.
- VM 방화벽 또는 상위 네트워크에서 `8043/tcp`, `8088/tcp` 접근이 차단되지 않았는지 확인합니다.

### Omada 장비가 Discover되지 않음

- VM과 Omada 장비가 같은 L2 또는 라우팅 가능한 네트워크에 있는지 확인합니다.
- 상위 방화벽에서 Omada 관련 UDP 브로드캐스트가 차단되지 않았는지 확인합니다.

## 참고

- [VM Devtools Installation](../vm-devtools/installation.md)
- [Proxmox Overview](../proxmox/overview.md)
