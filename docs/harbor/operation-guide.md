# Harbor Operation Guide

## 개요

이 문서는 Harbor 2.13.2 운영에서 MinIO S3 backend 점검과
Keycloak OIDC 연동 기준을 정의합니다.

## 운영 기준

- Harbor URL: `https://harbor.semtl.synology.me`
- Storage backend: MinIO S3 (`harbor` bucket)
- 인증: 기본 계정 + 단계적 OIDC(Keycloak) 전환

## 일일 점검

```bash
# Harbor UI/API 접속 가능 여부 점검
curl -I https://harbor.semtl.synology.me

# 프로젝트/이미지 푸시 실패 여부를 CI 로그에서 점검
# (GitLab pipeline recent jobs 확인)
```

확인 항목:

- UI 로그인 정상
- 이미지 pull/push 실패 급증 여부

## 주간 점검

- MinIO backend 연결 상태 확인
- Robot account 만료/권한 점검
- 미사용 이미지/아티팩트 정리 정책 점검

## OIDC 연동 절차

1. Keycloak realm `semtl`에서 `harbor` client 생성
2. Harbor Authentication 모드를 `OIDC`로 전환
3. Issuer를 `https://auth.semtl.synology.me/realms/semtl`로 설정
4. Harbor가 표시한 Redirect URI를 Keycloak에 정확히 등록

Harbor 설정값 예시:

- OIDC Endpoint(issuer): `https://auth.semtl.synology.me/realms/semtl`
- Client ID: `harbor`
- Client Secret: `<keycloak-client-secret>`
- Scope: `openid,profile,email`

## 장애 대응 기본 절차

1. Harbor 접속/로그인 실패 재현
2. Keycloak issuer 및 client 설정 확인
3. Redirect URI mismatch 여부 확인
4. 필요 시 로컬 인증으로 임시 전환 후 복구 진행

## 운영 시 금지사항

- Harbor 관리자 계정 공유 사용
- Robot account를 사람 계정처럼 장기 사용
- OIDC 설정 변경 후 로그인 검증 없이 운영 반영
