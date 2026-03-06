# MinIO OIDC Integration

## 개요
이 문서는 MinIO와 Keycloak OIDC 연동 절차를 독립 문서로 정리합니다.

## 대상 환경
- Keycloak: `https://auth.semtl.synology.me`
- Realm: `semtl`
- MinIO S3 API endpoint: `http://192.168.0.171:9000`
- MinIO Console: `http://192.168.0.171:9001`

## 1. Keycloak Client 구성
1. `Realm -> semtl` 선택
2. `Clients -> Create client`
3. Client ID: `minio`
4. OIDC client로 생성
5. Redirect URI에 MinIO callback URI 등록

참고:
- Callback URI는 운영 MinIO/Proxy 구성에 맞춰 정확히 등록합니다.
- 잘못된 Redirect URI는 로그인 루프/실패의 주요 원인입니다.

## 2. 정책 Claim 전략
권장 전략:
- Keycloak 사용자 attribute `policy`를 토큰 claim으로 전달
- MinIO에 동일 이름 정책을 생성해 매핑

예시:
- Keycloak user attribute: `policy=readwrite`
- MinIO policy name: `readwrite`

## 3. Keycloak 21+ User Profile 주의사항
최신 Keycloak에서는 사용자 attribute를 임의 입력하지 못할 수 있습니다.
이 경우 먼저 `User profile`에 attribute를 정의해야 합니다.

절차:
1. `Realm settings -> User profile`
2. `Create attribute`
3. 다음 값으로 생성
   - Name: `policy`
   - Display name: `policy`
   - Multivalued: `OFF`
   - Required: `OFF`
   - Who can edit: `Admin`
   - Who can view: `Admin`
4. 저장 후 `Users -> <user> -> Details`에서 `policy=readwrite` 입력

## 4. MinIO OIDC 설정 적용
```bash
mc alias set myminio http://127.0.0.1:9000 <MINIO_ROOT_USER> '<MINIO_ROOT_PASSWORD>'

mc admin config set myminio identity_openid \
  config_url="https://auth.semtl.synology.me/realms/semtl/.well-known/openid-configuration" \
  client_id="minio" \
  client_secret="<keycloak-client-secret>" \
  claim_name="policy" \
  scopes="openid,profile,email"

mc admin service restart myminio
mc admin config get myminio identity_openid
```

## 5. 검증 절차
1. MinIO Console에서 OIDC 로그인 시도
2. 로그인 사용자 권한이 `policy` 값과 일치하는지 확인
3. `mc admin info myminio`로 관리 연결 상태 점검

## 6. 운영 체크리스트
- `mc alias`는 반드시 S3 API endpoint(`9000`)를 사용
- Console endpoint(`9001`)를 `mc alias`로 사용하지 않음
- Keycloak client secret 변경 시 MinIO 설정 동기화
- Keycloak claim mapper 변경 시 권한 회귀 테스트 수행
