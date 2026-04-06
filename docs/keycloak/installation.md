# Keycloak Installation

## 개요

이 문서는 Synology Reverse Proxy(TLS 종료) 뒤에서 Docker Compose로
Keycloak 26.5.4와 Postgres 16을 설치하고, 초기 검증과 OIDC 연동 준비까지
완료하는 표준 절차를 정의합니다.

설치가 가장 중요한 기준 문서이므로, 구축 직후 필요한 검증/초기 백업/기본 장애 조치까지
이 문서에 포함합니다.

## 사전 조건

- 운영 도메인: `auth.semtl.synology.me`
- Reverse Proxy 라우팅 준비:
  `https://auth.semtl.synology.me` -> `http://<KEYCLOAK_VM_IP>:8080`
- VM 방화벽에서 `8080/tcp` 내부 접근 허용
- Docker Engine / Docker Compose 설치 완료
- 관리자 비밀번호와 DB 비밀번호를 별도로 준비

## 기준 아키텍처

- Keycloak 이미지: `quay.io/keycloak/keycloak:26.5.4`
- DB 이미지: `postgres:16`
- TLS 종료 지점: Synology Reverse Proxy
- Keycloak 서비스 포트: 내부 HTTP `8080`
- 프록시 헤더 모드: `--proxy-headers=xforwarded`
- 외부 Hostname: `auth.semtl.synology.me`
- HTTP 활성화: `KC_HTTP_ENABLED=true`

## 설치 절차

### 1. 작업 디렉터리 생성

```bash
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

설정 기준:

- `POSTGRES_PASSWORD`와 `KC_DB_PASSWORD`는 반드시 동일해야 합니다.
- `KEYCLOAK_ADMIN_PASSWORD`는 DB 비밀번호와 분리해 관리합니다.
- `--hostname`에는 `https://`를 붙이지 않고 호스트명만 입력합니다.
- 운영 비밀번호는 평문 하드코딩 대신 추후 `.env` 분리를 권장합니다.

### 3. 컨테이너 기동

```bash
cd ~/keycloak
docker compose up -d
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
```

정상 기준:

- `keycloak`
- `keycloak-postgres`

두 컨테이너가 모두 `Up` 상태여야 합니다.

### 4. Reverse Proxy 헤더 설정 확인

Synology Reverse Proxy 규칙(`auth.semtl.synology.me`)의 Custom Header에 아래 항목을 명시합니다.

- `X-Forwarded-Proto: https`
- `X-Forwarded-Port: 443`
- `X-Forwarded-Host: auth.semtl.synology.me`

주의:

- 헤더 누락 시 로그인 후 `issuer`가 `http://...:8080`으로 노출될 수 있습니다.
- Reverse Proxy 헤더 미검증 상태에서는 OIDC 연동을 진행하지 않습니다.

## 설치 검증

### 1. 컨테이너 및 로그 확인

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
docker logs --tail=200 keycloak | egrep -i 'error|exception|warn'
```

확인 항목:

- `keycloak`, `keycloak-postgres` 컨테이너가 `Up`
- 반복 재시작이 없어야 함
- 치명적 DB 연결 오류가 없어야 함

### 2. 내부 HTTP 응답 확인

```bash
curl -I http://127.0.0.1:8080
```

### 3. 외부 OIDC discovery 확인

```bash
OIDC_DISCOVERY_URL="https://auth.semtl.synology.me/realms/master/.well-known/openid-configuration"
curl -s "$OIDC_DISCOVERY_URL" \
  | egrep '"issuer"|"authorization_endpoint"|"token_endpoint"'
```

정상 기준:

- `issuer`가 `https://auth.semtl.synology.me/realms/master` 형태
- `authorization_endpoint`, `token_endpoint`도 동일 도메인 기준으로 노출

## 설치 직후 운영 기준

- 운영 서비스 클라이언트는 `master` Realm에 직접 혼합 구성하지 않습니다.
- 운영용 Realm은 별도 생성하며 `semtl` 같은 명확한 이름을 사용합니다.
- 변경 작업은 `Realm -> Client -> Redirect URI -> Secret` 순서로 검증합니다.
- 변경 직후 `issuer`와 실제 로그인 플로우를 함께 확인합니다.

## 초기 스냅샷 권장 시점

OIDC 연동 전 아래 스냅샷을 권장합니다.

```bash
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*
sudo apt autoremove -y
sudo apt clean
sudo journalctl --vacuum-time=1s
cat /dev/null > ~/.bash_history && history -c
```

권장 스냅샷:

- 설명:

```text
#1. VM-AUTH [SEMTL-NAS]
- CPU 코어 : 2
- 메모리 : 8GB
- MAC 주소 : 02:11:32:2f:b8:8e
- 컴퓨터이름 : vm-auth
- ID : semtl
- PW : <change-required>
- QEMU 게스트 에이전트 설치
==> sudo apt install qemu-guest-agent
==> sudo systemctl enable qemu-guest-agent
==> sudo systemctl start qemu-guest-agent
- Keycloak 26.5.4
- Reverse Proxy OK
- OIDC 미구성 상태
```

변경 이후 예시:

- `OIDC-GitLab-OK`
- `OIDC-Harbor-OK`
- `MFA-Enabled`

## OIDC 연동 준비

### 권장 순서

1. 운영 Realm 생성 (`semtl` 권장)
2. 서비스별 Client 생성 (`gitlab`, `harbor`, `minio` 등)
3. 서비스 측 redirect/callback URL 등록
4. Keycloak Client 설정과 서비스 측 설정의 정합성 검증
5. 사용자/그룹/권한 매핑 적용

OIDC 문서는 Keycloak 측(Client/Realm)과 서비스 측(redirect/callback)의
정합성 검증 절차를 반드시 포함해야 합니다.

### 앱별 OIDC 문서 분리 원칙

OIDC/SSO는 앱별 callback URL, claim 전략, 권한 매핑 방식이 달라지므로
`docs/keycloak/` 하위에 앱별 문서로 분리해 관리합니다.

현재 작성된 문서:

- [그룹/역할 전략](./group-and-role-strategy.md)
- [MinIO OIDC 연동](./minio-oidc-integration.md)

공통 기준:

- Realm은 `semtl` 사용
- 공통 그룹은 `oidc-devops`, `oidc-developers`, `oidc-viewers`를 우선 사용
- Client ID는 서비스 이름과 일치
- Keycloak `Redirect URI`와 서비스 측 callback URL은 정확히 일치
- 변경 후 discovery, login, 권한 반영까지 함께 검증

공통 계정 운영에서는 사용자 개별 attribute보다 그룹 기반 권한 모델을 우선 사용합니다.
앱별 문서에서는 이 공통 그룹을 각 서비스 권한으로 매핑합니다.

## 백업 및 복구

### 백업 대상

- `~/keycloak/docker-compose.yml`
- `~/keycloak/postgres`
- Realm/Client 설정 export 파일

주기적 백업 예시:

```bash
cp ~/keycloak/docker-compose.yml ~/keycloak/docker-compose.yml.bak.$(date +%F)
du -sh ~/keycloak/postgres
```

### 롤백 절차

설치 초기 단계에서만 사용합니다. 운영 데이터가 있으면 DB 볼륨 삭제 대신 백업/복구 절차를 우선 검토합니다.

```bash
cd ~/keycloak
docker compose down
rm -rf ./postgres
docker compose up -d
```

## 설치 중 자주 발생하는 이슈

### 1. Keycloak 기동 실패 또는 DB 연결 오류

증상:

- 컨테이너가 재시작 반복
- 로그에 DB 인증 실패 또는 연결 실패

주요 원인:

- `POSTGRES_PASSWORD`와 `KC_DB_PASSWORD` 불일치
- Postgres 초기화 데이터와 현재 설정 불일치

조치:

1. `docker-compose.yml`에서 DB 관련 값을 재확인합니다.
2. 초기 구축 단계라면 롤백 절차로 DB 볼륨을 초기화합니다.
3. `docker logs --tail=300 keycloak`로 재기동 후 오류가 사라졌는지 확인합니다.

### 2. issuer가 `http://...:8080`으로 노출됨

증상:

- OIDC 콜백 실패
- 외부 접근은 HTTPS인데 discovery 값이 내부 HTTP 기준으로 노출됨

주요 원인:

- Reverse Proxy `X-Forwarded-*` 헤더 누락
- Keycloak `--proxy-headers` 또는 `--hostname` 설정 부정합

조치:

1. Reverse Proxy에 `X-Forwarded-Proto: https`를 추가합니다.
2. Reverse Proxy에 `X-Forwarded-Port: 443`를 추가합니다.
3. `X-Forwarded-Host`까지 명시했는지 확인합니다.
4. 설정 반영 후 `docker compose up -d`로 재적용합니다.
5. discovery의 `issuer` 값을 다시 확인합니다.

### 3. OIDC 연동 직후 로그인 실패

증상:

- `redirect_uri` mismatch
- 로그인 화면 또는 콜백 단계에서 실패 반복

주요 원인:

- Realm/Client 설정과 서비스 측 callback URL 불일치
- 변경 단계별 검증 누락

조치:

1. 변경 직전 스냅샷으로 복구 가능 여부를 먼저 확인합니다.
2. `Realm -> Client -> Redirect URI -> Secret` 순서로 재검증합니다.
3. 서비스 측 redirect/callback URL과 Keycloak Client 설정이 정확히 일치하는지 확인합니다.

## 에스컬레이션 기준

- 15분 이상 인증 불가 지속
- 외부 `issuer` 불일치가 해결되지 않음
- 복구 후에도 동일 오류 재발

## 보안 주의사항

- 관리자 계정, DB 비밀번호, Client Secret은 문서/채팅에 직접 노출하지 않습니다.
- 예시 값은 모두 플레이스홀더로 유지합니다.
- 운영 전 비밀번호를 재발급하고 `.env` 또는 별도 비밀 관리 수단으로 분리합니다.
