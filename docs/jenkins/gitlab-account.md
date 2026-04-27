# Jenkins GitLab Account

## 개요

이 문서는 Jenkins에서 GitLab 저장소를 조회하기 위한 전용 GitLab 계정과
Jenkins Credential 등록 절차를 정리합니다.

목표 상태:

- Jenkins 전용 GitLab 사용자 `jenkins-ci` 생성
- Jenkins가 접근할 GitLab Group 또는 Project에 최소 권한 부여
- GitLab checkout용 Personal Access Token 발급
- GitLab API용 Personal Access Token 발급
- Jenkins `devops` Folder Credential에 GitLab 인증 정보 등록
- Jenkins GitLab Connection 등록
- Jenkins Pipeline에서 Credential ID만 참조

## 사용 시점

- Jenkins Pipeline에서 GitLab 저장소를 checkout해야 하는 경우
- Jenkins Multibranch Pipeline 또는 GitLab Webhook 연동을 준비하는 경우
- 개인 사용자 계정 대신 CI 전용 계정으로 감사 추적을 분리하려는 경우

## 사전 조건

- [GitLab 설치](../gitlab/installation.md) 완료
- [Jenkins 설치](./installation.md) 완료
- [Jenkins RKE2 Agent 설치](./kubernetes-agent-installation.md)의
  `devops` Folder 생성 완료
- GitLab 관리자 계정 또는 사용자 생성 권한
- Jenkins 관리자 계정

권장 운영값:

- GitLab URL: `https://gitlab.semtl.synology.me`
- Jenkins URL: `https://jenkins.semtl.synology.me`
- GitLab 사용자: `jenkins-ci`
- GitLab 표시 이름: `Jenkins CI`
- GitLab 이메일: 비밀번호 설정 링크를 받을 수 있는 운영자 관리 주소
- Jenkins Folder: `devops`
- Jenkins Credential ID: `gitlab-jenkins-ci-token`
- Jenkins GitLab API Credential ID: `gitlab-jenkins-api-token`
- Jenkins GitLab Connection name: `gitlab`

## 구성 기준

- Jenkins에는 사람 계정이나 GitLab `root` 계정 토큰을 등록하지 않습니다.
- Jenkins 전용 GitLab 계정은 필요한 Group 또는 Project에만 추가합니다.
- 코드 checkout만 필요하면 `Reporter` 또는 `Developer` 권한 중 낮은 권한을
  우선 검토합니다.
- protected branch에 push하거나 tag를 생성해야 하는 Job은 별도 계정과 권한으로
  분리합니다.
- GitLab Token 값은 Jenkins Credential에만 저장하고 Pipeline 코드에는 남기지
  않습니다.

## 1. GitLab Jenkins 전용 사용자 생성

GitLab UI에서 Jenkins 전용 사용자를 생성합니다.

GitLab UI 경로:

`Admin Area -> Users -> New user`

입력값:

- Name: `Jenkins CI`
- Username: `jenkins-ci`
- Email: 운영자가 관리하는 주소
- Projects limit: `0`
- Can create top-level group: 체크 해제
- Private profile: 체크 해제
- User type: `Regular`
- External: 체크 해제
- Validate user account: 체크 해제
- Admin note: `Jenkins repository checkout service account`

화면 섹션별 입력 기준:

| 섹션 | 항목 | 값 |
| --- | --- | --- |
| Account | Name | `Jenkins CI` |
| Account | Username | `jenkins-ci` |
| Account | Email | 운영자가 관리하는 주소 |
| Access | Projects limit | `0` |
| Access | Can create top-level group | 체크 해제 |
| Access | Private profile | 체크 해제 |
| Access | User type | `Regular` |
| Access | External | 체크 해제 |
| Access | Validate user account | 체크 해제 |
| Admin notes | Note | `Jenkins repository checkout service account` |

비밀번호 설정 방식:

- GitLab SMTP가 동작하면 reset link 메일로 첫 비밀번호를 설정합니다.
- 메일을 쓰지 않으면 관리자가 임시 비밀번호를 설정합니다.

생성 후 확인:

- Users 목록에 `jenkins-ci`가 표시됨
- 사용자가 `Blocked` 상태가 아님
- reset link 또는 임시 비밀번호로 첫 로그인 가능
- `jenkins-ci`가 Admin 권한을 갖지 않음
- `jenkins-ci`가 top-level group 또는 personal project를 만들 수 없음
- 2FA 정책이 있다면 CI 전용 계정의 토큰 사용 정책을 별도로 확인

### 1-1. 임시 비밀번호 설정

GitLab SMTP를 사용하지 않거나 reset link 메일을 받을 수 없으면 GitLab VM에서
관리자가 `jenkins-ci` 계정의 임시 비밀번호를 설정합니다.

```bash
sudo gitlab-rake "gitlab:password:reset[jenkins-ci]"
```

프롬프트에서 임시 비밀번호를 2회 입력합니다.

설정 후 확인:

1. `https://gitlab.semtl.synology.me`에 `jenkins-ci`로 로그인합니다.
1. 필요하면 첫 로그인 후 임시 비밀번호를 운영용 비밀번호로 변경합니다.
1. 로그인한 `jenkins-ci` 계정에서 Personal Access Token을 발급합니다.

비밀번호 운영 메모:

- GitLab 계정 비밀번호는 `jenkins-ci`로 로그인해 Token을 발급하기 위한
  용도입니다.
- Jenkins Credential에는 GitLab 계정 비밀번호를 저장하지 않습니다.
- Jenkins에는 다음 단계에서 발급하는 Personal Access Token만 등록합니다.

계정 운영 메모:

- GitLab 사용자 생성 화면에서 비밀번호 reset link가 사용자 이메일로 발송됩니다.
- GitLab SMTP가 동작한다면 실제 수신 가능한 운영자 관리 주소를 사용할 수
  있습니다.
- SMTP를 사용하지 않는 내부 GitLab이면 식별 가능한 운영자 관리 주소를 쓰고,
  임시 비밀번호 방식으로 첫 로그인을 처리합니다.
- 사람 계정과 Jenkins 계정을 분리하면 퇴사, 권한 변경, 토큰 회전 시 영향을
  줄이기 쉽습니다.

## 2. GitLab 권한 부여

Jenkins가 접근할 Group 또는 Project에 `jenkins-ci` 사용자를 추가합니다.

Group 단위 권한 예시:

`Groups -> devops -> Manage -> Members -> Invite members`

Project 단위 권한 예시:

`Project -> Manage -> Members -> Invite members`

입력값:

- User: `jenkins-ci`
- Role: `Reporter` 또는 `Developer`
- Expiration date: 운영 정책에 맞게 설정

권한 선택 기준:

- `Reporter`: private 저장소 clone, issue/metadata 조회 중심
- `Developer`: branch push, tag push, merge request 생성 등이 필요한 경우
- `Maintainer`: Jenkins 일반 checkout 용도로는 사용하지 않음

확인 항목:

- 대상 Group 또는 Project Members 목록에 `jenkins-ci`가 표시됨
- Jenkins가 checkout할 저장소에 실제 접근 가능한 권한인지 확인
- protected branch push가 필요한 경우 protected branch 설정과 함께 별도 검토

## 3. GitLab Personal Access Token 발급

`jenkins-ci` 계정으로 GitLab에 로그인한 뒤 Jenkins용 Token을 생성합니다.
이때 사용하는 GitLab 계정 비밀번호는 Token 발급을 위한 로그인 용도이며,
Jenkins Credential에는 저장하지 않습니다.

GitLab UI 경로:

`User avatar -> Preferences -> Access Tokens`

### 3-1. Checkout용 Token

Jenkins Pipeline에서 GitLab 저장소를 checkout할 때 사용할 Token입니다.

입력값:

- Token name: `jenkins-ci-checkout`
- Expiration date: 운영 정책에 맞게 설정
- Scopes:
  - `read_repository`

생성 후 Token 값을 복사해 `gitlab-jenkins-ci-token` Credential 등록에
사용합니다.

### 3-2. Jenkins GitLab Connection API용 Token

Jenkins `GitLab Connection`에서 GitLab API를 호출할 때 사용할 Token입니다.

입력값:

- Token name: `jenkins-api`
- Expiration date: 운영 정책에 맞게 설정
- Scopes:
  - `api`

생성 후 Token 값을 복사해 `gitlab-jenkins-api-token` Credential 등록에
사용합니다.

권장 Scope 기준:

- checkout용 Token은 `read_repository`만 사용합니다.
- GitLab Connection용 Token은 Jenkins GitLab Plugin의 API 호출을 위해
  `api` scope를 사용합니다.
- push/tag 생성이 필요한 Job에는 `write_repository`가 필요할 수 있으나,
  checkout/API 계정과 분리하는 것을 권장합니다.

생성 후 공통 확인:

- Token 값을 즉시 복사
- Token 값은 다시 확인할 수 없으므로 Jenkins Credential 등록 전까지 안전하게
  임시 보관

## 4. Jenkins Credential 등록

Jenkins UI에서 checkout용 Credential과 GitLab Connection API용 Credential을
분리해 등록합니다.

### 4-1. Checkout용 Credential 등록

Jenkins UI 경로:

`Dashboard -> devops -> Credentials -> Folder -> Global credentials (unrestricted)`

입력 순서:

1. `Global credentials (unrestricted)`를 선택합니다.
1. `Add Credentials`를 선택합니다.

입력값:

- Kind: `Username with password`
- Username: `jenkins-ci`
- Password: `jenkins-ci-checkout` Token 값
- ID: `gitlab-jenkins-ci-token`
- Description: `GitLab jenkins-ci token for repository checkout`

등록 확인:

- `devops` Folder credentials 목록에 `gitlab-jenkins-ci-token`이 표시됨
- Credential 상세 화면에서 Token 값이 평문으로 노출되지 않음

운영 메모:

- Jenkins Credential 화면에 `Scope` 항목이 보이지 않아도 정상입니다.
- Folder credentials에 등록하면 해당 Folder와 하위 Job에서 사용하는
  Credential로 관리됩니다.
- GitLab Personal Access Token의 `Scopes`와 Jenkins Credential 화면의
  표시 항목은 서로 다른 개념입니다.
- `Password` 필드에는 GitLab 계정 비밀번호가 아니라 Personal Access Token을
  입력합니다.
- Pipeline에는 Token 값을 직접 쓰지 않고 Credential ID만 사용합니다.
- Token이 노출되면 GitLab에서 즉시 revoke하고 새 Token으로 교체합니다.

### 4-2. GitLab API용 Credential 등록

GitLab Connection에서 사용할 API Token을 Jenkins Credential로 등록합니다.

Jenkins UI 경로:

`Dashboard -> Manage Jenkins -> Credentials -> System -> Global credentials (unrestricted)`

입력 순서:

1. `Global credentials (unrestricted)`를 선택합니다.
1. `Add Credentials`를 선택합니다.

입력값:

- Kind: `GitLab API token`
- API token: `jenkins-api` Token 값
- ID: `gitlab-jenkins-api-token`
- Description: `GitLab API token for Jenkins GitLab Connection`

운영 메모:

- `GitLab API token` Kind가 보이지 않으면 Jenkins GitLab Plugin 설치 여부를
  확인합니다.
- GitLab Connection은 Jenkins 전역 설정에서 사용하므로 System Credential에
  등록합니다.
- checkout용 `gitlab-jenkins-ci-token`과 API용 `gitlab-jenkins-api-token`은
  서로 다른 Token입니다.

## 5. Jenkins GitLab Connection 등록

Jenkins 전역 설정에서 GitLab Connection을 등록합니다.

Jenkins UI 경로:

`Dashboard -> Manage Jenkins -> System -> GitLab`

입력값:

- Connection name: `gitlab.semtl.synology.me`
- GitLab host URL: `https://gitlab.semtl.synology.me`
- Credentials: `gitlab-jenkins-api-token`

등록 후 확인:

1. `Test Connection`을 선택합니다.
1. 연결 성공 메시지를 확인합니다.
1. 저장합니다.

운영 메모:

- 이 설정은 GitLab Plugin이 GitLab API와 통신할 때 사용합니다.
- Pipeline checkout에는 계속 `gitlab-jenkins-ci-token`을 사용합니다.
- Connection name은 Job 설정이나 플러그인 연동에서 참조할 수 있으므로 짧고
  일관된 이름을 사용합니다.

## 6. Pipeline checkout 예시

Pipeline에서는 Jenkins Credential ID를 사용해 GitLab 저장소를 checkout합니다.

```groovy
pipeline {
  agent any

  stages {
    stage('Checkout') {
      steps {
        git branch: 'main',
            credentialsId: 'gitlab-jenkins-ci-token',
            url: 'https://gitlab.semtl.synology.me/devops/example-app.git'
      }
    }
  }
}
```

운영 메모:

- 예제 URL은 실제 GitLab Group/Project 경로로 교체합니다.
- Kubernetes Agent 기반 Job에서는 [Jenkins RKE2 Agent 설치](./kubernetes-agent-installation.md)의
  Pod Template을 함께 사용합니다.
- Harbor push/pull까지 이어지는 Job은 [Jenkins Harbor 연동](./harbor-integration.md)을
  참고합니다.

## 검증 방법

GitLab에서 확인:

- `jenkins-ci` 사용자가 대상 Group 또는 Project Member로 등록됨
- `jenkins-ci` 계정 Token이 만료되지 않음
- 대상 저장소 URL이 `https://gitlab.semtl.synology.me/...` 형식으로 확인됨

Jenkins에서 확인:

- `devops` Folder Credential에 `gitlab-jenkins-ci-token`이 존재함
- Pipeline checkout 단계가 성공함
- Jenkins Console Output에 Token 값이 노출되지 않음

## 트러블슈팅

### Checkout 시 인증 실패

가능성:

- Jenkins Credential Username이 `jenkins-ci`가 아님
- Password에 GitLab 계정 비밀번호를 넣었거나 만료된 Token을 넣음
- Token scope에 `read_repository`가 없음
- 대상 Project에 `jenkins-ci` 권한이 없음

확인:

- GitLab에서 `jenkins-ci` 사용자 상태가 active인지 확인
- 대상 Group 또는 Project Members에 `jenkins-ci`가 있는지 확인
- Token 만료일과 scope를 확인
- Jenkins Credential ID가 Pipeline의 `credentialsId`와 일치하는지 확인

### Private 저장소가 보이지 않음

가능성:

- `jenkins-ci` 사용자가 Group에는 있지만 하위 Project 권한 상속이 제한됨
- Project가 다른 Group 아래에 있음
- 저장소 URL 오타

조치:

- Project Members에서 `jenkins-ci`가 실제로 보이는지 확인
- Project clone URL을 다시 복사해 Pipeline URL에 반영
- 최소 권한으로 먼저 checkout을 검증한 뒤 필요한 권한만 추가

## 보안 기준

- Jenkins용 GitLab 계정은 개인 계정과 분리합니다.
- Token 만료일을 설정하고 주기적으로 교체합니다.
- Credential ID만 문서와 Pipeline에 남기고 Token 값은 기록하지 않습니다.
- checkout 전용 계정과 push/tag 생성 계정은 분리합니다.
- 불필요해진 Token은 GitLab에서 즉시 revoke합니다.

## 참고

- [Jenkins 설치](./installation.md)
- [Jenkins RKE2 Agent 설치](./kubernetes-agent-installation.md)
- [Jenkins Harbor 연동](./harbor-integration.md)
- [GitLab 설치](../gitlab/installation.md)
