# Harbor OIDC Integration

## 개요
이 문서는 Harbor와 Keycloak OIDC 통합 절차를 운영 기준으로 정리합니다.

## 대상 환경
- Harbor: `https://harbor.semtl.synology.me`
- Keycloak: `https://auth.semtl.synology.me`
- Realm: `semtl`
- TLS 종료: Synology Reverse Proxy

## 1. 사전 점검
1. Harbor 외부 URL이 HTTPS 기준으로 고정되어야 합니다.
   - `hostname: harbor.semtl.synology.me`
   - `external_url: https://harbor.semtl.synology.me` (사용 중인 배포 방식에서 지원 시)
2. Reverse Proxy가 `X-Forwarded-Proto: https`와 Host 헤더를 전달해야 합니다.
3. 비상 복구용 로컬 관리자 로그인 경로를 유지합니다.
   - `Primary Auth Mode`를 활성화해 OIDC 장애 시 로컬 로그인 가능 상태 유지

## 2. Keycloak Client 생성
`Realm(semtl) -> Clients -> Create client`

권장 설정:
- Client type: `OpenID Connect`
- Client ID: `harbor`
- Client authentication: `ON` (Confidential)
- Standard flow: `ON`
- Authorization: `OFF`
- Direct access grants / Implicit flow / Service account roles: `OFF`

Login settings:
- Valid Redirect URIs:
  - `https://harbor.semtl.synology.me/c/oidc/callback`
- Valid Post Logout Redirect URIs:
  - `https://harbor.semtl.synology.me/account/sign-in`
- Web origins: `+` 또는 `https://harbor.semtl.synology.me`

저장 후 `Credentials` 탭에서 Client Secret을 확인합니다.

## 3. Keycloak Group Claim 구성
Harbor 그룹 매핑을 위해 `groups` claim을 토큰에 포함합니다.

예시 절차:
1. `Clients -> harbor -> Client scopes`
2. Harbor 전용 scope에 mapper 추가
3. Mapper type: `Group Membership`
4. Token claim name: `groups`
5. `Add to ID token`: `ON`
6. `Full group path`: `OFF`

권장 그룹 구조:
- `harbor-admins` (System Admin 승격용)
- `harbor-devops-admin`
- `harbor-devops-dev`
- `harbor-devops-ro`

## 4. Harbor OIDC 설정
`Harbor UI -> Administration -> Configuration -> Authentication`

입력값:
- Auth Mode: `OIDC`
- OIDC Provider Name: `keycloak`
- OIDC Endpoint: `https://auth.semtl.synology.me/realms/semtl`
- OIDC Client ID: `harbor`
- OIDC Client Secret: `<keycloak-client-secret>`
- OIDC Scope: `openid,profile,email`
- Username Claim: `preferred_username`
- Group Claim Name: `groups`
- OIDC Admin Group: `harbor-admins`
- Verify Certificate: `ON`
- Automatic onboarding: `ON`
- Primary Auth Mode: `ON`

## 5. 프로젝트 권한 매핑
`Projects -> devops -> Members -> + GROUP`

권장 매핑:
- `harbor-devops-admin` -> `Project Admin`
- `harbor-devops-dev` -> `Developer`
- `harbor-devops-ro` -> `Guest` 또는 `Limited Guest`

참고:
- 그룹 매핑 목록은 최신 OIDC 토큰 기준으로 반영되므로, Keycloak 그룹 변경 후 재로그인이 필요합니다.

## 6. Robot Account 운영
OIDC 사용자 대신 CI/CD는 Robot Account를 사용합니다.

권장:
- `gitlab` 로봇 계정: `push + pull`
- `jenkins` 로봇 계정: 용도에 따라 `pull-only` 또는 `push + pull`
- 토큰 만료 주기와 교체 절차를 운영 문서로 고정

## 7. 검증 시나리오
1. Harbor 접속 시 Keycloak 로그인 페이지 리다이렉트 확인
2. OIDC 로그인 성공 후 Harbor 복귀 확인
3. `harbor-admins` 사용자의 System Admin 권한 확인
4. devops 프로젝트에서 그룹 권한(읽기/쓰기) 검증
5. Robot Account로 `docker login` 및 push/pull 검증
