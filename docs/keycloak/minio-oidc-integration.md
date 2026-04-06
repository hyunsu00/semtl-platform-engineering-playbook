# Keycloak MinIO OIDC Integration

## 개요

이 문서는 `Keycloak -> MinIO` OIDC 연동을 표준화하는 첫 번째 앱별 기준 문서입니다.
앞으로 `jenkins`, `harbor`, `gitlab`, `rancher` 등도 같은 형식으로 확장할 수 있도록
공통 기준과 MinIO 전용 설정을 함께 정리합니다.

문서 목적은 다음 두 가지입니다.

- Keycloak 측 공통 작업 패턴을 고정합니다.
- MinIO 측 callback, 그룹 claim, 정책 매핑을 실제 운영 절차로 정리합니다.

## 대상 환경

- Keycloak URL: `https://auth.semtl.synology.me`
- Realm: `semtl`
- MinIO S3 API endpoint: `https://s3.semtl.synology.me`
- MinIO Console endpoint: `https://minio.semtl.synology.me`
- Client ID: `minio`
- Claim 기준: `groups`

## 공통 적용 원칙

앱별 OIDC 문서를 만들 때 아래 항목은 공통으로 유지합니다.

- Realm은 운영용 `semtl`을 사용합니다.
- Client ID는 서비스 이름과 동일하게 맞춥니다.
- Keycloak의 `Client -> Redirect URI`와 서비스 측 callback URL은 완전히 일치해야 합니다.
- 먼저 Keycloak Client를 만들고, 다음에 서비스 측 OIDC를 적용합니다.
- 권한 매핑은 사용자 attribute보다 `groups`를 우선 사용합니다.
- 적용 직후에는 discovery, redirect, login, 권한 반영까지 한 번에 검증합니다.

공통 계정 운영 기준은 [그룹/역할 전략](./group-and-role-strategy.md)을 따릅니다.
MinIO 문서에서는 이 공통 그룹을 MinIO 정책으로 연결하는 방식만 다룹니다.

## 운영 원칙

- OIDC를 붙여도 MinIO 기본 `admin` 계정은 반드시 로그인 가능 상태로 유지합니다.
- OIDC 장애 시에도 `admin` 계정으로 Console 및 관리 작업이 가능해야 합니다.
- OIDC 사용자 권한과 `admin` 계정 권한을 혼동하지 않습니다.
- `admin` 계정은 비상 복구용이므로 비밀번호를 안전하게 보관합니다.

## 사전 조건

- [Keycloak 설치](./installation.md) 완료
- [Keycloak 그룹/역할 전략](./group-and-role-strategy.md) 완료
- [MinIO 설치](../minio/installation.md) 완료
- Keycloak Reverse Proxy 헤더가 정상 반영되어 외부 `issuer`가 `https://`로 노출됨
- MinIO root 계정으로 `mc admin` 명령 수행 가능
- MinIO S3 API와 Console이 각각 다른 Reverse Proxy 도메인으로 분리되어 있음

## 사전 확인

### Keycloak VM에서 실행

```bash
curl -s \
  https://auth.semtl.synology.me/realms/semtl/.well-known/openid-configuration \
  | egrep '"issuer"|"authorization_endpoint"|"token_endpoint"'
```

### MinIO VM에서 실행

```bash
mc alias set local http://127.0.0.1:9000 <MINIO_ROOT_USER> '<MINIO_ROOT_PASSWORD>'
mc admin info local
```

### 확인 기준

- `issuer`가 `https://auth.semtl.synology.me/realms/semtl`
- `mc admin info local`이 오류 없이 응답

## 연동 순서

### 1. 운영자 PC 브라우저에서 Console URL 기준 확인

OIDC 로그인은 사용자가 실제로 접속하는 Console URL 기준으로 동작해야 합니다.
현재 운영 기준은 Reverse Proxy Console 도메인을 사용합니다.

등록 기준:

- 운영 Console URL: `https://minio.semtl.synology.me`
- Redirect URI: `https://minio.semtl.synology.me/oauth_callback`

주의:

- 브라우저 로그인은 반드시 `https://minio.semtl.synology.me`로 접속합니다.
- S3 API 도메인인 `https://s3.semtl.synology.me`는 OIDC callback URL로 사용하지 않습니다.
- 내부 `:9001`로 직접 접속하면서 public URL을 Redirect URI로 등록하면
  로그인 후 callback mismatch가 발생할 수 있습니다.

### 2. Keycloak VM에서 공통 사용자/그룹 확인

이 단계는 새로 만드는 작업이 아니라 공통 문서에서 준비한 값이 맞는지 확인하는 단계입니다.

확인할 그룹:

- `oidc-devops`
- `oidc-developers`
- `oidc-viewers`

확인할 사용자:

- `semtl` -> `oidc-devops`
- `hyunsu00` -> `oidc-developers`
- `guest` -> `oidc-viewers`

주의:

- `Policy`는 비워둔 상태여야 합니다.
- MinIO 권한은 사용자별 attribute가 아니라 group 기준으로 매핑합니다.

### 3. Keycloak VM에서 MinIO Client 생성

경로:

- `Realm -> semtl`
- `Clients -> Create client`

권장 값:

- Client type: `OpenID Connect`
- Client ID: `minio`
- Name: `minio`

생성 후 확인할 핵심 설정:

- Client authentication: `ON`
- Authorization: `OFF`
- Standard flow: `ON`
- Direct access grants: `OFF`
- Implicit flow: `OFF`
- Service account roles: `OFF`
- PKCE Method: 비워둠
- Require DPoP bound tokens: `OFF`
- Root URL: `https://minio.semtl.synology.me`
- Home URL: `https://minio.semtl.synology.me`
- Valid redirect URIs: `https://minio.semtl.synology.me/oauth_callback`
- Valid post logout redirect URIs: `https://minio.semtl.synology.me`
- Web origins: `https://minio.semtl.synology.me`

주의:

- Redirect URI 끝 경로는 반드시 `/oauth_callback`까지 정확히 입력합니다.
- 테스트 중 와일드카드로 넓게 열 수는 있지만 운영 반영 전에는 정확한 URI 하나로 축소합니다.
- 이 단계에서는 MinIO 설정을 아직 변경하지 않습니다.

### 4. Keycloak VM에서 `groups` claim mapper 설정

MinIO는 토큰 안의 그룹 정보를 읽어 정책과 매핑하는 방식으로 운영합니다.
따라서 Keycloak에서 `groups` claim이 MinIO Client에 포함되어야 합니다.

경로:

- `Clients -> minio -> Client scopes`
- `minio-dedicated` 클릭
- `Mappers`

현재 UI 기준 권장 방식:

- `minio-dedicated -> Mappers -> Configure a new mapper`
- `By configuration -> Group Membership`

권장 값:

- Name: `groups`
- Token Claim Name: `groups`
- Full group path: `OFF`
- Add to ID token: `ON`
- Add to access token: `ON`
- Add to lightweight access token: `OFF`
- Add to userinfo: `ON`
- Add to token introspection: `ON`

설명:

- `minio-dedicated`는 `minio` Client 전용 scope입니다.
- 공용 `groups` client scope를 따로 연결하지 않아도,
  이 전용 scope 안에 mapper를 넣으면 `minio` Client에만 적용할 수 있습니다.
- 현재 화면에서 `Add client scope`를 눌렀을 때 `groups`가 보이지 않으면
  `minio-dedicated` 안에 직접 mapper를 추가하면 됩니다.

검증 포인트:

- mapper 이름보다 `Token Claim Name`이 중요합니다.
- MinIO 설정의 `claim_name`과 Keycloak mapper의 `Token Claim Name`은 반드시 동일해야 합니다.
- 이 문서 기준은 `groups` claim을 사용하므로 그룹명이 토큰에 그대로 보여야 합니다.

다음으로 `Keycloak VM`에서 확인:

- `Clients -> minio -> Credentials`
- `Client Secret` 값 확인

확인 기준:

- `Client Authenticator`는 client secret 기반이어야 합니다.
- MinIO 설정에 넣을 `Client Secret` 값을 복사해 둡니다.

다음 단계에서 `MinIO VM`에 적용:

- 위에서 복사한 `Client Secret` 값을
  `/etc/default/minio`의
  `MINIO_IDENTITY_OPENID_CLIENT_SECRET="<keycloak-client-secret>"` 자리에 넣습니다.

### 5. MinIO VM에서 OIDC용 정책 준비

MinIO OIDC는 Keycloak 그룹에 정책을 `attach`하는 방식이 아닙니다.
MinIO는 토큰의 claim 값으로 정책 이름을 찾습니다.

따라서 이 문서에서는 `claim_name="groups"`를 사용하므로,
Keycloak 그룹명과 동일한 이름의 MinIO 정책을 미리 만들어 둡니다.

권장 정책 이름:

- `oidc-devops`
- `oidc-developers`
- `oidc-viewers`

정책 의미:

- `oidc-devops`: MinIO 기본 `consoleAdmin`과 동일 권한
- `oidc-developers`: MinIO 기본 `readwrite`와 동일 권한
- `oidc-viewers`: MinIO 기본 `readonly`와 동일 권한

`MinIO VM`에서 실행:

```bash
mkdir -p ~/keycloak

mc admin policy info local consoleAdmin \
  --policy-file ~/keycloak/minio-oidc-policy-devops.json
mc admin policy info local readwrite \
  --policy-file ~/keycloak/minio-oidc-policy-developers.json
mc admin policy info local readonly \
  --policy-file ~/keycloak/minio-oidc-policy-viewers.json

cat ~/keycloak/minio-oidc-policy-devops.json
cat ~/keycloak/minio-oidc-policy-developers.json
cat ~/keycloak/minio-oidc-policy-viewers.json

mc admin policy create local oidc-devops ~/keycloak/minio-oidc-policy-devops.json
mc admin policy create local oidc-developers ~/keycloak/minio-oidc-policy-developers.json
mc admin policy create local oidc-viewers ~/keycloak/minio-oidc-policy-viewers.json

mc admin policy list local
mc admin policy info local oidc-devops
mc admin policy info local oidc-developers
mc admin policy info local oidc-viewers
```

설정 기준:

- Keycloak 그룹명과 MinIO 정책명을 동일하게 맞춥니다.
- 정책 파일은 `>` 리다이렉션 대신 `--policy-file`로 생성합니다.
- `mc admin policy create` 전에 `cat`으로 JSON 내용이 실제로 저장됐는지 확인합니다.
- `mc admin policy attach --group ...` 는 MinIO 내부 그룹용이므로
  Keycloak OIDC 그룹에는 사용하지 않습니다.
- OIDC 정책을 붙이더라도 기본 `admin` 계정은 삭제하거나 비활성화하지 않습니다.

운영 메모:

- 초기 검증은 `oidc-developers`와 `oidc-viewers`부터 맞추고,
  `oidc-devops`는 마지막에 확인하는 것이 안전합니다.
- 운영 안정화 후 bucket 단위 최소 권한 정책으로 세분화합니다.

### 6. MinIO VM에서 OIDC 설정 적용

이 문서 기준으로 MinIO OIDC는 `/etc/default/minio`의 환경 변수로 적용합니다.
특히 Reverse Proxy 환경에서는 `MINIO_BROWSER_REDIRECT_URL`이
Keycloak `redirect_uri` 정합성에 직접 영향을 주므로 함께 설정합니다.

`MinIO VM`에서 실행:

```bash
sudo editor /etc/default/minio
```

추가할 값:

```bash
MINIO_BROWSER_REDIRECT_URL="https://minio.semtl.synology.me"
MINIO_SERVER_URL="https://s3.semtl.synology.me"
MINIO_IDENTITY_OPENID_CONFIG_URL="https://auth.semtl.synology.me/realms/semtl/.well-known/openid-configuration"
MINIO_IDENTITY_OPENID_CLIENT_ID="minio"
MINIO_IDENTITY_OPENID_CLIENT_SECRET="<keycloak-client-secret>"
MINIO_IDENTITY_OPENID_CLAIM_NAME="groups"
MINIO_IDENTITY_OPENID_DISPLAY_NAME="Keycloak SSO"
MINIO_IDENTITY_OPENID_SCOPES="openid,profile,email"
```

적용 후 재시작:

```bash
sudo systemctl restart minio
sudo systemctl status minio --no-pager
```

설정 기준:

- OIDC 설정 소스는 `mc admin config set`이 아니라 `/etc/default/minio`입니다.
- `MINIO_BROWSER_REDIRECT_URL`은 브라우저 사용자가 실제 접속하는 Console URL과 같아야 합니다.
- `MINIO_SERVER_URL`은 외부 S3 API endpoint와 같아야 합니다.
- `MINIO_IDENTITY_OPENID_CONFIG_URL`은 반드시 `semtl` Realm discovery URL을 사용합니다.
- `MINIO_IDENTITY_OPENID_CLIENT_ID`는 `minio` Client ID와 같아야 합니다.
- `MINIO_IDENTITY_OPENID_CLIENT_SECRET`는
  `Clients -> minio -> Credentials`에서 발급받은 값을 사용합니다.
- `MINIO_IDENTITY_OPENID_CLAIM_NAME`은 Keycloak mapper의 `Token Claim Name`과 같아야 합니다.
- `MINIO_IDENTITY_OPENID_DISPLAY_NAME`은 MinIO Console 로그인 화면에 표시할 SSO 버튼 이름입니다.
- MinIO는 `groups` claim 안의 값과 같은 이름의 정책을 사용자에게 적용합니다.
- OIDC 로그인 자체는 Console 도메인(`https://minio.semtl.synology.me`) 기준으로 검증합니다.
- OIDC 적용 후에도 `admin` 계정의 기존 로그인 경로는 그대로 사용할 수 있어야 합니다.

## 정합성 검증

### 1. Keycloak VM 또는 운영자 PC에서 Discovery 검증

```bash
curl -s \
  https://auth.semtl.synology.me/realms/semtl/.well-known/openid-configuration \
  | egrep '"issuer"|"authorization_endpoint"|"token_endpoint"'
```

정상 기준:

- 모든 endpoint가 `auth.semtl.synology.me` 기준으로 노출

### 2. MinIO VM에서 OIDC 설정 검증

```bash
sudo egrep \
  'MINIO_BROWSER_REDIRECT_URL|MINIO_SERVER_URL|MINIO_IDENTITY_OPENID_' \
  /etc/default/minio
```

확인 항목:

- `MINIO_BROWSER_REDIRECT_URL="https://minio.semtl.synology.me"`
- `MINIO_SERVER_URL="https://s3.semtl.synology.me"`
- `MINIO_IDENTITY_OPENID_CONFIG_URL`이 `.../realms/semtl/.well-known/openid-configuration`
- `MINIO_IDENTITY_OPENID_CLIENT_ID="minio"`
- `MINIO_IDENTITY_OPENID_CLAIM_NAME="groups"`
- `MINIO_IDENTITY_OPENID_DISPLAY_NAME="Keycloak SSO"`

### 3. 운영자 PC 브라우저에서 로그인 검증

검증 절차:

1. 브라우저에서 `https://minio.semtl.synology.me` 접속
2. `Login with SSO` 또는 OIDC 로그인 버튼 선택
3. Keycloak 로그인 수행
4. MinIO Console 진입 확인
5. 브라우저 로그아웃 후 기본 `admin` 계정 로그인도 별도로 확인

정상 기준:

- Keycloak 로그인 후 MinIO Console로 정상 복귀
- `oidc-developers` 사용자는 bucket 생성/업로드가 가능
- `oidc-devops` 사용자는 관리 기능까지 접근 가능
- 기본 `admin` 계정도 계속 로그인 가능

### 4. Keycloak VM, MinIO VM, 브라우저에서 정합성 검증

`Keycloak VM`에서 확인:

- Client 설정

`MinIO VM`에서 확인:

- OIDC 설정

운영자 PC 브라우저에서 확인:

- 실제 로그인 URL

반드시 함께 확인할 항목:

- Keycloak Valid redirect URI
- 실제 브라우저 접속 URL
- MinIO Console 외부 공개 URL
- MinIO `claim_name`
- Keycloak mapper의 `Token Claim Name`
- 테스트 사용자의 그룹 할당 상태

이 다섯 항목 중 하나라도 다르면 로그인은 성공해도 권한 반영 또는 callback 단계에서 실패할 수 있습니다.

## 운영 체크리스트

- Keycloak Realm: `semtl`
- Client ID: `minio`
- Redirect URI: `https://minio.semtl.synology.me/oauth_callback`
- Claim name: `groups`
- `oidc-devops`, `oidc-developers`, `oidc-viewers` 그룹 준비
- MinIO policy와 Keycloak group 매핑 일치
- public Console URL과 실제 로그인 URL 일치
- 기본 `admin` 계정 로그인 가능

## 참고

- [Keycloak 설치](./installation.md)
- [Keycloak 그룹/역할 전략](./group-and-role-strategy.md)
- [MinIO 설치](../minio/installation.md)
