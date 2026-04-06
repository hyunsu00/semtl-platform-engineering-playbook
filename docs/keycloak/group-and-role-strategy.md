# Keycloak Group And Role Strategy

## 개요

이 문서는 Keycloak 공통 기반 준비 문서입니다.
여기서는 아래 항목까지만 설정합니다.

- `semtl` Realm 생성
- `oidc-devops`, `oidc-developers`, `oidc-viewers` 그룹 생성
- 운영 담당자 `semtl` 계정 생성
- 개발 사용자 `hyunsu00` 계정 생성
- 조회 사용자 `guest` 계정 생성
- 각 계정의 그룹 할당

앱별 OIDC 연동은 이 문서에서 다루지 않습니다.
Client 생성, `groups` claim, redirect URI, 서비스 권한 매핑은 앱별 문서에서 진행합니다.

## 공통 원칙

- 운영 Realm은 `semtl`을 사용합니다.
- 사용자 계정은 서비스별로 따로 만들지 않고 공통 계정으로 운영합니다.
- 권한 부여는 사용자별 attribute보다 그룹 기반을 우선합니다.
- 그룹 이름은 역할 기준으로 유지합니다.

기본 그룹 의미:

- `oidc-devops`: 운영/관리자 그룹
- `oidc-developers`: 일반 사용자 그룹
- `oidc-viewers`: 조회 전용 그룹

## 따라가기 순서

1. `semtl` Realm 생성
2. `oidc-devops`, `oidc-developers`, `oidc-viewers` 그룹 생성
3. `hyunsu00` 개발 사용자 생성
4. `hyunsu00`에 `oidc-developers` 그룹 할당
5. `semtl` 사용자 생성
6. `semtl`에 `oidc-devops` 그룹 할당
7. `guest` 조회 사용자 생성
8. `guest`에 `oidc-viewers` 그룹 할당
9. 이후 앱별 문서로 이동

## 1. `semtl` Realm 생성

경로:

- `Keycloak Admin Console -> Manage realms -> Create realm`

입력 예시:

- Realm name: `semtl`
- Enabled: `ON`

확인 기준:

- 좌측 상단 Realm selector에 `semtl`이 보여야 합니다.
- 이후 작업은 모두 `semtl` Realm 안에서 진행합니다.

## 2. 그룹 생성

경로:

- `Realm -> semtl -> Groups -> Create group`

생성할 그룹과 설명:

- Name: `oidc-devops`
- Description: `플랫폼 운영 및 관리자 권한이 필요한 공통 운영 그룹`
- Name: `oidc-developers`
- Description: `일반 개발 및 실무 사용자를 위한 공통 기본 그룹`
- Name: `oidc-viewers`
- Description: `조회 전용 사용자를 위한 공통 읽기 전용 그룹`

따라가기:

1. `Create group` 선택
2. `Name`에 `oidc-devops` 입력
3. `Description`에 `플랫폼 운영 및 관리자 권한이 필요한 공통 운영 그룹` 입력
4. 같은 방식으로 `oidc-developers`, `oidc-viewers`도 생성

확인 기준:

- `Groups` 목록에 `oidc-devops`, `oidc-developers`, `oidc-viewers`가 모두 보여야 합니다.

## 3. 개발 사용자 `hyunsu00` 생성

경로:

- `Realm -> semtl -> Users -> Create new user`

입력 예시:

- Username: `hyunsu00`
- Email: 비워둠 또는 선택 입력
- First name: `HyunSu`
- Last name: `Kim`
- Enabled: `ON`
- Email verified: `OFF`
- Required user actions: 비워둠
- Policy: 비워둠

비밀번호 설정:

- `Users -> hyunsu00 -> Credentials`
- Password: `<change-required>`
- Temporary: `OFF`

중요:

- `Required user actions`는 비워둡니다.
- `Policy` 칸이 보여도 비워둡니다.
- `hyunsu00`는 이메일 인증을 아직 사용하지 않으므로 `Email verified`를 `OFF`로 둡니다.
- 이메일 없이 생성해도 OIDC 로그인 테스트에는 문제 없습니다.
- 공통 그룹 방식에서는 사용자별 `policy` attribute를 사용하지 않습니다.

## 4. `hyunsu00`에 `oidc-developers` 그룹 할당

경로:

- `Users -> hyunsu00 -> Groups -> Join group`

선택 그룹:

- `oidc-developers`

확인 기준:

- `Users -> hyunsu00 -> Groups`에 `oidc-developers`가 보여야 합니다.

## 5. 운영 담당자 `semtl` 생성

경로:

- `Realm -> semtl -> Users -> Create new user`

입력 예시:

- Username: `semtl`
- Email: `hyun955807@naver.com`
- First name: `semtl`
- Last name: `Admin`
- Enabled: `ON`
- Email verified: `ON`
- Required user actions: 비워둠
- Policy: 비워둠

비밀번호 설정:

- `Users -> semtl -> Credentials`
- Password: `<change-required>`
- Temporary: `OFF`

중요:

- `Required user actions`는 초기 구축 단계에서는 비워둡니다.
- `Policy`는 입력하지 않습니다.
- 운영 보안 강화는 앱 연동이 끝난 뒤 `CONFIGURE_TOTP` 등으로 별도 적용합니다.

## 6. `semtl`에 `oidc-devops` 그룹 할당

경로:

- `Users -> semtl -> Groups -> Join group`

선택 그룹:

- `oidc-devops`

확인 기준:

- `Users -> semtl -> Groups`에 `oidc-devops`가 보여야 합니다.

## 7. 조회 사용자 `guest` 생성

경로:

- `Realm -> semtl -> Users -> Create new user`

입력 예시:

- Username: `guest`
- Email: 비워둠 또는 선택 입력
- First name: `Guest`
- Last name: `Viewer`
- Enabled: `ON`
- Email verified: `OFF`
- Required user actions: 비워둠
- Policy: 비워둠

비밀번호 설정:

- `Users -> guest -> Credentials`
- Password: `<change-required>`
- Temporary: `OFF`

중요:

- 조회 계정도 초기 테스트 단계에서는 `Required user actions`를 비워둡니다.
- `guest`는 이메일 인증을 사용하지 않으므로 `Email verified`를 `OFF`로 둡니다.
- 이메일 없이 생성해도 조회 권한 테스트에는 문제 없습니다.
- `Policy`는 입력하지 않습니다.

## 8. `guest`에 `oidc-viewers` 그룹 할당

경로:

- `Users -> guest -> Groups -> Join group`

선택 그룹:

- `oidc-viewers`

확인 기준:

- `Users -> guest -> Groups`에 `oidc-viewers`가 보여야 합니다.

## 9. 확인 체크리스트

- Realm: `semtl`
- 그룹: `oidc-devops`, `oidc-developers`, `oidc-viewers`
- `hyunsu00` 개발 사용자 생성 완료
- `hyunsu00 -> oidc-developers` 할당 완료
- `semtl` 생성 완료
- `semtl -> oidc-devops` 할당 완료
- `guest` 조회 사용자 생성 완료
- `guest -> oidc-viewers` 할당 완료
- `Required user actions` 비워둠
- `Policy` 비워둠

## 주의사항

- `Policy` 필드가 보여도 현재 공통 그룹 방식에서는 사용하지 않습니다.
- `Policy`와 `Groups`를 혼용하면 권한 추적이 어려워집니다.
- 앱별 OIDC 설정은 이 문서에서 하지 않고 각 앱 문서에서 진행합니다.

잘못된 예:

- `semtl` 사용자에 `Policy=readwrite` 입력
- 동시에 `Groups=oidc-devops`도 사용

올바른 예:

- `semtl`: `Policy` 비워둠, `Groups=oidc-devops`
- `hyunsu00`: `Policy` 비워둠, `Groups=oidc-developers`
- `guest`: `Policy` 비워둠, `Groups=oidc-viewers`

## 다음 단계

공통 기반 준비가 끝났으면 앱별 문서로 이동합니다.

- [MinIO OIDC 연동](./minio-oidc-integration.md)

## 참고

- [Keycloak 설치](./installation.md)
