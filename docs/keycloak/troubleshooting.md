# Keycloak Troubleshooting

## 개요

Keycloak + Reverse Proxy 환경에서 자주 발생하는 이슈와
즉시 조치 절차를 정리합니다.

## 공통 점검 절차

```bash
# 컨테이너 상태 확인
docker ps

# Keycloak 로그 확인
docker logs --tail=300 keycloak

# 내부 응답 확인
curl -I http://127.0.0.1:8080

# 외부 issuer 확인
OIDC_DISCOVERY_URL="https://auth.semtl.synology.me/realms/master/.well-known/openid-configuration"
curl -s "$OIDC_DISCOVERY_URL" \
  | grep '"issuer"'
```

## 자주 발생하는 이슈

### 1. Keycloak 기동 실패 (DB 연결 오류)

증상:

- 컨테이너가 재시작 반복
- 로그에 DB 인증 실패/연결 실패

원인:

- `POSTGRES_PASSWORD`와 `KC_DB_PASSWORD` 불일치

해결:

1. `docker-compose.yml`에서 두 비밀번호 일치 확인
2. 초기 구축 단계라면 DB 볼륨 초기화 후 재기동

```bash
cd ~/keycloak
docker compose down
rm -rf ./postgres
docker compose up -d
```

### 2. 로그인 후 issuer가 `http://...:8080`으로 노출

증상:

- OIDC 콜백 실패
- issuer가 외부 HTTPS 도메인이 아님

원인:

- Reverse Proxy `X-Forwarded-*` 헤더 누락
- Keycloak `--proxy-headers`/`--hostname` 설정 부정합

해결:

1. Reverse Proxy에 `X-Forwarded-Proto: https` 추가
2. Reverse Proxy에 `X-Forwarded-Port: 443` 추가
3. Keycloak 옵션 반영 후 issuer 재확인

```bash
# compose 설정 반영 후 재기동
cd ~/keycloak
docker compose up -d

# issuer 재확인
OIDC_DISCOVERY_URL="https://auth.semtl.synology.me/realms/master/.well-known/openid-configuration"
curl -s "$OIDC_DISCOVERY_URL" \
  | grep '"issuer"'
```

### 3. OIDC 연동 전후 설정 꼬임

증상:

- Client redirect URI mismatch
- 로그인 실패 반복

원인:

- Realm/Client 설정 단계별 검증 누락

해결:

1. 변경 직전 스냅샷으로 복구
2. `Realm -> Client -> Redirect URI -> Secret` 순서로 재적용

## 에스컬레이션 기준

- 15분 이상 인증 불가 지속
- 외부 issuer 불일치가 해결되지 않음
- 복구 후에도 동일 오류 재발
