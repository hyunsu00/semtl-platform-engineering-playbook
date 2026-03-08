# Keycloak Installation

## 개요

이 문서는 Synology Reverse Proxy(TLS 종료) 뒤에서 Docker Compose로
Keycloak 26.5.4와 Postgres 16을 설치하는 표준 절차를 정의합니다.

## 사전 조건

- DNS/도메인 준비: `auth.semtl.synology.me`
- Reverse Proxy 라우팅 준비:
  `https://auth.semtl.synology.me` -> `http://<KEYCLOAK_VM_IP>:8080`
- VM 방화벽에서 `8080/tcp`(내부 경로) 허용
- Docker/Compose 설치 완료

## 기준 아키텍처

- Keycloak: `quay.io/keycloak/keycloak:26.5.4`
- DB: `postgres:16`
- 프록시 모드: `--proxy-headers=xforwarded`
- Hostname: `auth.semtl.synology.me`
- 내부 HTTP: `KC_HTTP_ENABLED=true`

## 설치 절차

### 1. 작업 디렉터리 생성

```bash
# Keycloak 전용 작업 경로 생성
mkdir -p ~/keycloak
cd ~/keycloak
```

### 2. Compose 파일 작성

`docker-compose.yml`:

```yaml
services:
  postgres:
    image: postgres:16
    container_name: keycloak-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: keycloak
      POSTGRES_USER: keycloak
      POSTGRES_PASSWORD: <strong-db-password>
    volumes:
      - ./postgres:/var/lib/postgresql/data

  keycloak:
    image: quay.io/keycloak/keycloak:26.5.4
    container_name: keycloak
    restart: unless-stopped
    depends_on:
      - postgres
    command:
      - start
      - --proxy-headers=xforwarded
      - --hostname=auth.semtl.synology.me
      - --hostname-strict=true
    environment:
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://postgres:5432/keycloak
      KC_DB_USERNAME: keycloak
      KC_DB_PASSWORD: <strong-db-password>
      KC_HTTP_ENABLED: "true"
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: <strong-admin-password>
    ports:
      - "8080:8080"
```

주의:

- `POSTGRES_PASSWORD`와 `KC_DB_PASSWORD`는 반드시 동일해야 합니다.
- `--hostname`은 `https://`를 붙이지 않고 호스트명만 사용합니다.

### 3. 컨테이너 기동

```bash
# 백그라운드로 Keycloak/Postgres 기동
cd ~/keycloak
docker compose up -d

# 실행 상태 확인
docker ps
```

### 4. Reverse Proxy 헤더 설정 확인

Synology Reverse Proxy 규칙(`auth.semtl.synology.me`)의 Custom Header에
아래 항목을 명시합니다.

- `X-Forwarded-Proto: https`
- `X-Forwarded-Port: 443`
- `X-Forwarded-Host: auth.semtl.synology.me` (권장)

## 설치 검증

```bash
# Keycloak 컨테이너 최근 로그 확인
docker logs -f keycloak --tail=200

# 내부 HTTP 응답 확인
curl -I http://127.0.0.1:8080

# OIDC discovery issuer 확인
OIDC_DISCOVERY_URL="https://auth.semtl.synology.me/realms/master/.well-known/openid-configuration"
curl -s "$OIDC_DISCOVERY_URL" \
  | egrep '"issuer"|"authorization_endpoint"|"token_endpoint"'
```

정상 기준:

- `issuer`가 `https://auth.semtl.synology.me/realms/master` 형태
- `authorization_endpoint`, `token_endpoint`도 같은 도메인 기준으로 노출

## 초기 스냅샷 권장 시점

OIDC 연동 전 아래 스냅샷을 권장합니다.

스냅샷 생성 전 아래 정리 작업을 먼저 수행합니다.

```bash
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*
sudo apt autoremove -y
sudo apt clean
sudo journalctl --vacuum-time=1s
cat /dev/null > ~/.bash_history && history -c
```

- 이름: `BASE-Keycloak-Install`
- 설명: `Keycloak 26.5.4 / Reverse Proxy OK / OIDC 미구성`

## 롤백 절차

설치 초기(데이터 미중요) 기준:

```bash
# 컨테이너 중지
cd ~/keycloak
docker compose down

# DB 볼륨 초기화(초기 구축 단계에서만 사용)
rm -rf ./postgres

# 재기동
docker compose up -d
```

## 보안 주의사항

- 관리자/DB 비밀번호를 문서/채팅에 노출하지 않습니다.
- 운영 전 비밀번호를 재발급하고 `.env` 분리 사용을 권장합니다.
