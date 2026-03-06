# Chat History: Docs Categorization from Shared Chat 69aa9f02 (v1)

- Date (UTC): `2026-03-06`
- Source: `https://chatgpt.com/share/69aa9f02-5208-8009-bf8e-3890a8bae3dd`
- Scope: `docs/gitlab`, `docs/keycloak`, `docs/harbor`

## 분석 요약

공유 대화의 핵심 주제는 아래 3개였습니다.

- GitLab Runner(Kubernetes executor) 등록/토큰 발급/권한 이슈
- Keycloak 26.5.4 + Postgres 16 설치와 Reverse Proxy 헤더 정합성
- GitLab/Harbor의 Keycloak OIDC 연동 절차

## 문서 반영

- `docs/keycloak/installation.md`
  - Compose 기반 표준 설치 절차
  - `--proxy-headers=xforwarded`, `--hostname`, `KC_HTTP_ENABLED` 기준
  - Reverse Proxy 헤더 요구사항, issuer 검증 절차
  - OIDC 연동 전 스냅샷 권장 시점

- `docs/keycloak/operation-guide.md`
  - 일일/주간 점검 명령
  - 스냅샷 네이밍/변경 표준
  - OIDC 연동 운영 순서

- `docs/keycloak/troubleshooting.md`
  - DB 비밀번호 불일치
  - issuer가 `http://...:8080`으로 노출되는 문제
  - Realm/Client 설정 꼬임 복구

- `docs/gitlab/operation-guide.md`
  - Group/Instance Runner 토큰 발급 절차
  - Helm 기반 gitlab-runner 설치 예시
  - OIDC 연동 운영 기준

- `docs/gitlab/troubleshooting.md`
  - New group runner 버튼 미노출
  - GitLab 18.x 토큰 발급 방식 변경
  - 태그/untagged 설정 불일치
  - OIDC callback 오류

- `docs/harbor/operation-guide.md`
  - MinIO S3 backend 운영 점검
  - Harbor OIDC 연동 절차 및 설정값 기준

## 비고

- 민감 정보(토큰/비밀번호)는 플레이스홀더로 유지
- 공유 대화 맥락을 카테고리 문서로 분리 정리
