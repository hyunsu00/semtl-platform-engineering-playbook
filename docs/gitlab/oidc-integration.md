# GitLab OIDC Integration

## 개요
이 문서는 Keycloak과 GitLab OIDC 연동 절차를 운영 기준으로 정리합니다.

## 대상 환경
- Keycloak: `https://auth.semtl.synology.me`
- Realm: `semtl`
- GitLab: `https://gitlab.semtl.synology.me`
- GitLab 배포: Omnibus

## 1. 사전 점검
1. Realm discovery endpoint 확인
```bash
curl -s https://auth.semtl.synology.me/realms/semtl/.well-known/openid-configuration | head
```
2. GitLab 외부 URL 확인
- `https://gitlab.semtl.synology.me`
3. Reverse Proxy가 `X-Forwarded-*` 헤더를 정상 전달하는지 확인

## 2. Keycloak Client 생성
경로: `Realm(semtl) -> Clients -> Create client`

기본 설정:
- Client type: `OpenID Connect`
- Client ID: `gitlab`
- Client authentication: `ON` (Confidential)
- Standard flow: `ON`
- Authorization: `OFF`
- Direct access grants: `OFF`
- Service account roles: `OFF`
- PKCE Method: `S256`

Login settings:
- Root URL: `https://gitlab.semtl.synology.me`
- Home URL: `https://gitlab.semtl.synology.me`
- Valid Redirect URIs:
  - `https://gitlab.semtl.synology.me/users/auth/openid_connect/callback`
- Valid Post Logout Redirect URIs:
  - `https://gitlab.semtl.synology.me/`
- Web origins:
  - `https://gitlab.semtl.synology.me`

생성 후 `Credentials` 탭에서 Client Secret을 확인합니다.

## 3. Keycloak 사용자 준비
OIDC 로그인은 Keycloak 사용자를 기준으로 동작합니다.

필수 항목:
- Username
- Password(Credentials 탭)
- Email(권장)
- Email verified(`ON` 권장)

## 4. GitLab Omnibus 설정
`/etc/gitlab/gitlab.rb`에 아래 설정 추가:

```ruby
gitlab_rails['omniauth_enabled'] = true
gitlab_rails['omniauth_allow_single_sign_on'] = ['openid_connect']
gitlab_rails['omniauth_block_auto_created_users'] = false

gitlab_rails['omniauth_providers'] = [
  {
    name: "openid_connect",
    label: "Keycloak",
    args: {
      name: "openid_connect",
      scope: ["openid","profile","email"],
      response_type: "code",
      issuer: "https://auth.semtl.synology.me/realms/semtl",
      discovery: true,
      client_auth_method: "basic",
      uid_field: "sub",
      send_scope_to_token_endpoint: true,
      pkce: true,
      client_options: {
        identifier: "gitlab",
        secret: "<keycloak-client-secret>",
        redirect_uri: "https://gitlab.semtl.synology.me/users/auth/openid_connect/callback"
      }
    }
  }
]
```

적용:
```bash
sudo gitlab-ctl reconfigure
sudo gitlab-ctl restart
```

## 5. 검증 절차
1. GitLab 로그인 페이지에 `Keycloak` 버튼 노출 확인
2. 버튼 클릭 후 Keycloak 로그인 성공 확인
3. GitLab 자동 사용자 생성 확인
4. 필요 시 사용자 타입을 `Administrator`로 승격

## 6. 운영 주의사항
- `master` realm을 서비스 로그인에 직접 사용하지 않습니다.
- Redirect URI 오타(슬래시/프로토콜 불일치)를 허용하지 않습니다.
- 로컬 `root` 계정은 브레이크글래스 용도로 유지합니다.

## 7. 동기화 관련 참고
- Keycloak에서 이름(first/last name)을 변경해도 GitLab 기존 사용자 프로필은 자동 동기화되지 않을 수 있습니다.
- 기존 사용자 이름 변경은 GitLab 프로필에서 수동 반영합니다.
