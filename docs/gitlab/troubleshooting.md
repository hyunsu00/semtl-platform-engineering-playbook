# Gitlab Troubleshooting

## 개요

GitLab Runner 등록/연동 및 OIDC 로그인에서 발생하는
대표 이슈를 정리합니다.

## 공통 점검 절차

```bash
# GitLab 서비스 상태 확인
sudo gitlab-ctl status

# GitLab 로그 확인
sudo gitlab-ctl tail | egrep -i 'error|exception|fail'

# Runner 파드 상태 확인 (K8s executor 사용 시)
kubectl -n gitlab-runner get pods -o wide
```

## 자주 발생하는 이슈

### 1. Group Runner 생성 버튼이 보이지 않음

증상:

- `Settings > CI/CD > Runners`에서 `New group runner` 미노출

원인:

- 그룹 Owner 권한 부족
- Admin 영역에서 Group Runner 생성 제한

해결:

1. 그룹 Owner 권한 확인
2. Admin -> CI/CD -> Runners에서 Group Runner 허용 확인
3. 우회로로 Instance Runner 생성 후 사용

### 2. Runner 등록 토큰 발급 실패

증상:

- 기존 방식처럼 Registration token 위치가 보이지 않음

원인:

- GitLab 18.x는 Runner 생성 후 토큰 발급 방식으로 변경

해결:

- `New runner` 생성 후 발급되는 `glrt-...` 토큰 사용

### 3. Runner는 Online인데 Job이 실행되지 않음

증상:

- Job pending 지속

원인:

- `Run untagged jobs` 비활성
- Job tags와 Runner tags 불일치

해결:

- Runner의 `Run untagged jobs` 활성화
- 또는 `.gitlab-ci.yml`에 `tags: [k8s]` 지정

### 4. OIDC 로그인 실패

증상:

- 로그인 시 redirect/callback 오류

원인:

- Keycloak client의 redirect URI 불일치
- GitLab `gitlab.rb` OIDC 설정 오타

해결:

- Callback URI를 정확히 일치시킴
- `sudo gitlab-ctl reconfigure` 후 재검증

### 5. 로그인 화면에 `Keycloak` 버튼이 보이지 않음

증상:
- GitLab 로그인 화면이 로컬 계정 폼만 표시

원인:
- `gitlab.rb` OIDC 설정 누락/오타
- `gitlab-ctl reconfigure` 미실행

해결:
```bash
sudo gitlab-ctl reconfigure
sudo gitlab-ctl restart
sudo gitlab-ctl tail gitlab-rails
```

### 6. Keycloak 로그인 사용자로 인증 불가

증상:
- Keycloak 버튼 클릭 후 로그인 실패

원인:
- Realm에 로그인 대상 사용자가 없음
- 사용자 비밀번호(Credentials) 미설정

해결:
1. Keycloak `Users`에서 사용자 생성
2. `Credentials`에서 비밀번호 설정(Temporary 해제 권장)
3. Email 및 Email verified 상태 확인

### 7. Keycloak 이름 변경이 GitLab에 즉시 반영되지 않음

증상:
- Keycloak first/last name 변경 후 GitLab 프로필 이름이 유지됨

원인:
- 기존 GitLab 사용자 프로필은 OIDC 로그인 시 자동 동기화가 제한적임

해결:
- GitLab 사용자 프로필에서 이름을 수동 수정

## 에스컬레이션 기준

- Runner Offline 15분 이상 지속
- 모든 사용자 OIDC 로그인 실패
- 배포 파이프라인 전체 중단
