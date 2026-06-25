# VM OpenWISP Installation

Ubuntu 22.04 Server 기반 `vm-openwisp` VM에 Docker 기반 OpenWISP를 배포합니다.
OpenWrt 장비 등록은 [OpenWrt OpenVPN](./openwrt-openvpn.md) 문서에서 진행합니다.

## 운영값

- VM 이름: `VM-OPENWISP`
- hostname: `vm-openwisp`
- 운영 계정: `semtl`
- IP: `192.168.77.51`
- Dashboard FQDN: `openwisp.semtl.synology.me`
- API FQDN: `openwisp-api.semtl.synology.me`
- OpenVPN FQDN: `openwisp-vpn.semtl.synology.me`
- OpenVPN External Port: `11194/udp`
- OpenVPN Internal Port: `1194/udp`
- 작업 경로: `~/docker/openwisp`
- OpenWISP Version: `25.10.4`
- Web Reverse Proxy: `192.168.77.2` -> `192.168.77.51`

## 1. VM 기준

- vCPU: `2`
- RAM: `4GB`
- Disk: `40GB`
- Network: 운영 LAN
- IPv4: 고정 IP 또는 DHCP 예약

## 2. Ubuntu 기본 설정

```bash
sudo hostnamectl set-hostname vm-openwisp
```

`/etc/hosts`:

```text
127.0.1.1 openwisp.semtl.synology.me vm-openwisp
```

```bash
sudo apt update -y
sudo apt install -y qemu-guest-agent openssh-server
sudo systemctl enable --now qemu-guest-agent
sudo systemctl enable --now ssh
hostname
hostname -f
systemctl is-active qemu-guest-agent
systemctl is-active ssh
ip -brief address
```

성공 기준:

- hostname이 `vm-openwisp`
- FQDN이 `openwisp.semtl.synology.me`
- `qemu-guest-agent`가 `active`
- `ssh`가 `active`
- `192.168.77.51` 확인

## 3. SSH와 시간 확인

```bash
ssh semtl@192.168.77.51
sudo whoami
timedatectl
```

성공 기준:

- `ssh semtl@192.168.77.51` 접속 가능
- `sudo whoami` 결과가 `root`
- 시간 동기화 정상

## 4. Ubuntu 기본 설치 직후 스냅샷

```bash
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*
sudo apt autoremove -y
sudo apt clean
sudo journalctl --vacuum-time=1s
cat /dev/null > /home/semtl/.bash_history && history -c
```

Synology NAS 스냅샷 설명:

```text
#1. VM-OPENWISP [SEMTL-NAS]
- CPU 코어 : 2
- 메모리 : 4GB
- MAC 주소 : 02:11:32:2E:F9:0C
- 컴퓨터이름 : vm-openwisp
- ID : semtl
- PW : <패스워드>
- QEMU 게스트 에이전트 설치
==> sudo apt install qemu-guest-agent
==> sudo systemctl enable qemu-guest-agent
```

성공 기준:

- Ubuntu 기본 설치 직후 스냅샷 생성 완료

## 5. Docker Engine 설치

```bash
for pkg in docker.io docker-doc docker-compose docker-compose-v2 \
  podman-docker containerd runc; do
  sudo apt remove -y "$pkg" 2>/dev/null || true
done

sudo apt update
sudo apt install -y ca-certificates curl make openssl

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker

systemctl is-active docker
docker --version
docker compose version
sudo docker run --rm hello-world
```

성공 기준:

- `docker`가 `active`
- `docker --version` 출력
- `docker compose version` 출력
- `sudo docker run --rm hello-world` 성공

## 6. Docker 권한 설정

```bash
sudo usermod -aG docker "$USER"
exit
```

SSH 재접속 후:

```bash
id
docker run --rm hello-world
```

성공 기준:

- `id`에 `docker` 그룹 포함
- `sudo` 없이 `docker run --rm hello-world` 성공

## 7. OpenWISP Docker Compose 준비

```bash
mkdir -p ~/docker/openwisp
cd ~/docker/openwisp

OPENWISP_VERSION="25.10.4"
OPENWISP_ARCHIVE_URL="https://github.com/openwisp/docker-openwisp/archive"
curl -fL "${OPENWISP_ARCHIVE_URL}/refs/tags/${OPENWISP_VERSION}.tar.gz" \
  -o docker-openwisp.tar.gz
tar -xzf docker-openwisp.tar.gz --strip-components=1
rm docker-openwisp.tar.gz

OW_DB_PASS="$(openssl rand -hex 24)"
OW_INFLUXDB_PASS="$(openssl rand -hex 24)"
OW_DJANGO_SECRET_KEY="$(openssl rand -hex 48)"

cat >> .env <<EOF

# SEMTL overrides
DASHBOARD_DOMAIN=openwisp.semtl.synology.me
API_DOMAIN=openwisp-api.semtl.synology.me
VPN_DOMAIN=openwisp-vpn.semtl.synology.me
OPENWISP_VERSION=${OPENWISP_VERSION}
EMAIL_DJANGO_DEFAULT=admin@semtl.synology.me
SSL_CERT_MODE=External
CELERY_SERVICE_NETWORK_MODE=service:openvpn
VPN_NAME=default
VPN_CLIENT_NAME=semtl-openwrt-vpn
DB_USER=openwisp
DB_PASS=${OW_DB_PASS}
INFLUXDB_USER=openwisp
INFLUXDB_PASS=${OW_INFLUXDB_PASS}
DJANGO_SECRET_KEY=${OW_DJANGO_SECRET_KEY}
DJANGO_ALLOWED_HOSTS=.semtl.synology.me
DJANGO_CORS_HOSTS=https://openwisp.semtl.synology.me,https://openwisp-api.semtl.synology.me
TZ=Asia/Seoul
EOF

mkdir -p customization/configuration/django
touch customization/configuration/django/__init__.py
cat > customization/configuration/django/custom_django_settings.py <<'EOF'
CSRF_TRUSTED_ORIGINS = [
    "https://openwisp.semtl.synology.me",
    "https://openwisp-api.semtl.synology.me",
]
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SESSION_COOKIE_DOMAIN = ".semtl.synology.me"
CSRF_COOKIE_DOMAIN = ".semtl.synology.me"
EOF

tail -n 20 .env
test -f docker-compose.yml
```

성공 기준:

- `~/docker/openwisp/docker-compose.yml` 존재
- `OPENWISP_VERSION=25.10.4`
- `SSL_CERT_MODE=External`
- `VPN_DOMAIN=openwisp-vpn.semtl.synology.me`
- `CELERY_SERVICE_NETWORK_MODE=service:openvpn`
- `VPN_NAME=default`
- `VPN_CLIENT_NAME=semtl-openwrt-vpn`
- `DJANGO_ALLOWED_HOSTS=.semtl.synology.me`
- `DJANGO_CORS_HOSTS`에 dashboard/API HTTPS 도메인 포함
- `custom_django_settings.py`에 `CSRF_TRUSTED_ORIGINS` 설정 완료

## 8. OpenWISP 기동

```bash
cd ~/docker/openwisp
OPENWISP_VERSION="$(grep '^OPENWISP_VERSION=' .env | tail -n 1 | cut -d= -f2)"
make start USER=openwisp OPENWISP_VERSION="${OPENWISP_VERSION}"
docker compose ps
```

성공 기준:

- `dashboard`, `api`, `nginx`, `postgres`, `redis` 실행 상태
- `openvpn` 실행 상태
- `celery`, `celery_monitoring`이 `openvpn` 서비스 네트워크 공유

## 9. OpenVPN 포트 포워딩과 확인

포트 포워딩:

```text
WAN UDP 11194 -> 192.168.77.51 UDP 1194
```

확인:

```bash
cd ~/docker/openwisp
docker compose ps openvpn
docker compose logs --tail=100 openvpn
docker compose exec openvpn sh -lc 'echo "VPN_NAME=$VPN_NAME"; ls -l /*.conf'
ss -lunp | grep 1194
docker inspect "$(docker compose ps -q celery)" \
  --format '{{ .HostConfig.NetworkMode }}'
docker inspect "$(docker compose ps -q celery_monitoring)" \
  --format '{{ .HostConfig.NetworkMode }}'
```

성공 기준:

- `openvpn`이 `Up` 또는 `healthy`
- 내부 `1194/udp` listen 확인
- `VPN_NAME=default`
- OpenVPN 컨테이너 안에 `/default.conf` 존재
- `celery`, `celery_monitoring`의 `NetworkMode`가 OpenVPN 공유 네트워크
- OpenWISP dashboard에서 VPN 서버 `default` 확인
- OpenWISP dashboard에서 VPN 클라이언트 템플릿 `semtl-openwrt-vpn` 확인

## 10. Synology Reverse Proxy 확인

```bash
getent hosts openwisp.semtl.synology.me
curl -I -H "Host: openwisp.semtl.synology.me" http://192.168.77.51
```

Synology Reverse Proxy:

```text
openwisp.semtl.synology.me -> http://192.168.77.51:80
openwisp-api.semtl.synology.me -> http://192.168.77.51:80
```

사용자 지정 머리글:

```text
Upgrade             $http_upgrade
Connection          $connection_upgrade
Host                $host
X-Forwarded-Host    $host
X-Forwarded-Proto   https
X-Forwarded-Port    443
```

성공 기준:

- `getent hosts` 결과가 `192.168.77.2`
- `https://openwisp.semtl.synology.me` 접속 가능
- 초기 관리자 계정 `admin` / `admin` 로그인 가능
- 최초 로그인 후 관리자 비밀번호 변경 완료

## 11. OpenWISP 운영 명령

상태 확인:

```bash
cd ~/docker/openwisp
docker compose ps
docker compose logs --tail=100
docker compose logs -f dashboard nginx openvpn
```

다시 시작:

```bash
cd ~/docker/openwisp
OPENWISP_VERSION="$(grep '^OPENWISP_VERSION=' .env | tail -n 1 | cut -d= -f2)"
make stop
make start USER=openwisp OPENWISP_VERSION="${OPENWISP_VERSION}"
```

초기 설치 재시도:

```bash
cd ~/docker/openwisp
OPENWISP_VERSION="$(grep '^OPENWISP_VERSION=' .env | tail -n 1 | cut -d= -f2)"
make clean
make start USER=openwisp OPENWISP_VERSION="${OPENWISP_VERSION}"
```

성공 기준:

- `docker compose ps`에서 주요 컨테이너 실행 상태 확인
- `make stop` 후 `make start` 재기동 가능
- `make clean`은 운영 데이터 삭제 가능성을 확인한 뒤에만 실행
- `VPN_NAME=default` 유지

## 12. 최종 확인

```bash
hostnamectl
timedatectl
systemctl is-active qemu-guest-agent
systemctl is-active ssh
systemctl is-active docker
docker --version
docker compose version
docker ps
cd ~/docker/openwisp
docker compose ps
docker compose ps openvpn
docker compose logs --tail=50 openvpn
docker compose exec openvpn sh -lc 'echo "VPN_NAME=$VPN_NAME"; ls -l /default.conf'
ss -lunp | grep 1194
test -d ~/docker/openwisp && echo "openwisp workdir ok"
```

성공 기준:

- hostname이 `vm-openwisp`
- 시간 동기화 정상
- `qemu-guest-agent`, `ssh`, `docker`가 `active`
- Docker와 Compose plugin 정상 출력
- `sudo` 없이 `docker ps` 실행 가능
- OpenWISP 컨테이너 실행 상태 확인
- OpenVPN 컨테이너 실행 상태 확인
- `VPN_NAME=default`
- `/default.conf` 존재
- 내부 `1194/udp` listen 확인
- `openwisp workdir ok` 출력
- `openwisp.semtl.synology.me`가 `192.168.77.2`로 해석됨
- 외부 `openwisp-vpn.semtl.synology.me:11194/udp` 포워딩 완료
