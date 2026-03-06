# Harbor Troubleshooting

## 개요
Harbor 주요 장애 사례와 해결 절차를 정리합니다.

## 공통 점검 절차
1. 서비스 상태 확인
2. 최근 변경 사항 확인
3. 로그 수집 및 원인 범위 축소

## 자주 발생하는 이슈
### 이슈 1: 서비스 시작 실패
- 증상: 프로세스가 재시작 반복
- 원인: 설정 오류 또는 포트 충돌
- 해결: 설정 검증 후 재시작

### 이슈 2: 접속 불가
- 증상: UI/API 타임아웃
- 원인: 네트워크/DNS/방화벽 설정 이슈
- 해결: 경로별 네트워크 확인 후 정책 수정

### 이슈 3: OIDC 로그인 후 redirect loop 또는 `redirect_uri` 오류
- 증상: Keycloak 로그인 후 Harbor로 복귀 실패, 반복 로그인
- 원인:
  - Keycloak Redirect URI 미일치
  - Harbor 외부 URL이 HTTPS로 인식되지 않음
  - Reverse Proxy `X-Forwarded-Proto` 전달 누락
- 해결:
  1. Keycloak Client Redirect URI 확인
     - `https://harbor.semtl.synology.me/c/oidc/callback`
  2. Post Logout Redirect URI 확인
     - `https://harbor.semtl.synology.me/account/sign-in`
  3. Harbor `hostname`/`external_url`과 RP 헤더 설정 점검

### 이슈 4: 프로젝트 `+ GROUP`에서 Keycloak 그룹이 검색되지 않음
- 증상: Harbor Members 화면에서 그룹 자동완성 미노출
- 원인:
  - Keycloak 토큰에 `groups` claim이 없음
  - 그룹 변경 후 사용자 재로그인 미수행
  - Mapper 설정(`Group Membership`) 누락/오설정
- 해결:
  1. Keycloak mapper 점검
     - Claim name: `groups`
     - Add to ID token: `ON`
     - Full group path: `OFF`
  2. 그룹 부여 후 Harbor/Keycloak 재로그인
  3. Harbor Authentication 설정의 `Group Claim Name=groups` 확인

## 에스컬레이션 기준
- 15분 이상 서비스 영향 지속
- 데이터 손실 가능성 존재

## 참고
- 장애 대응 Runbook 링크
