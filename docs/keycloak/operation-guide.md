# Keycloak Operation Guide

## 개요

이 문서는 Keycloak 운영 점검, OIDC 연동 전후 변경 절차,
백업/복구 기준을 정의합니다.

## 운영 기준

- 운영 도메인: `https://auth.semtl.synology.me`
- TLS 종료 지점: Synology Reverse Proxy
- Keycloak은 내부 HTTP(`8080`)로 서비스
- OIDC issuer는 외부 HTTPS URL로 유지

## 일일 점검

```bash
# 컨테이너 상태 확인
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# Keycloak 에러 로그 빠른 점검
docker logs --tail=200 keycloak | egrep -i 'error|exception|warn'

# OIDC issuer 노출값 확인
OIDC_DISCOVERY_URL="https://auth.semtl.synology.me/realms/master/.well-known/openid-configuration"
curl -s "$OIDC_DISCOVERY_URL" \
  | grep '"issuer"'
```

확인 항목:

- `keycloak`, `keycloak-postgres` 컨테이너가 `Up`
- `issuer`가 `https://auth.semtl.synology.me/realms/<realm>` 형태

## 주간 점검

```bash
# 디스크 사용량 확인
df -h

# Keycloak/DB 볼륨 사용량 확인
du -sh ~/keycloak/postgres

# 인증 관련 설정 백업
cp ~/keycloak/docker-compose.yml ~/keycloak/docker-compose.yml.bak.$(date +%F)
```

## 변경 작업 표준

1. 변경 전 스냅샷 생성
2. 변경 범위 문서화(Realm, Client, Redirect URI)
3. 변경 즉시 issuer/로그인 플로우 검증
4. 이상 시 즉시 스냅샷 또는 설정 롤백

권장 스냅샷 네이밍:

- `BASE-Keycloak`
- `OIDC-GitLab-OK`
- `OIDC-Harbor-OK`
- `MFA-Enabled`

## OIDC 연동 운영 순서

1. Keycloak Realm 생성 (`semtl` 권장)
2. Keycloak Client 생성 (`gitlab`, `harbor`)
3. GitLab OIDC 연동 검증
4. Harbor OIDC 연동 검증
5. 그룹/권한 매핑 적용

## MinIO OIDC 설정 표준

MinIO 연동 시 핵심 항목:
- Realm: `semtl`
- Client ID: `minio`
- Discovery URL: `https://auth.semtl.synology.me/realms/semtl/.well-known/openid-configuration`
- 정책 claim: `policy` (권장) 또는 `groups`

Keycloak 최신 버전(21+)에서는 사용자 임의 attribute 입력이 제한될 수 있습니다.
이 경우 `Realm settings -> User profile`에서 `policy` attribute를 먼저 정의합니다.

권장 attribute 설정:
- Name: `policy`
- Multivalued: `OFF`
- Required: `OFF`
- Who can edit: `Admin`
- Who can view: `Admin`

그 다음 `Users -> <user> -> Details`에서 `policy=readwrite`를 부여합니다.

## 백업 및 복구

백업 대상:

- `~/keycloak/docker-compose.yml`
- `~/keycloak/postgres` (DB 데이터)
- Realm/Client 설정(주기적 export)

## 운영 시 금지사항

- `master` Realm에 운영 서비스 클라이언트 직접 혼합 구성
- `--hostname`에 `https://` 스킴 포함
- Reverse Proxy 헤더 미검증 상태에서 OIDC 연동 진행
