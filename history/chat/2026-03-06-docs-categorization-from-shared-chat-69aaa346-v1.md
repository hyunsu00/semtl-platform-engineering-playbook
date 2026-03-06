# Chat History: Docs Categorization from Shared Chat 69aaa346 (v1)

- Date (UTC): `2026-03-06`
- Source: `https://chatgpt.com/share/69aaa346-c568-8009-8f09-38b505881df8`
- Scope: `docs/proxmox`, `docs/gitlab`, `docs/harbor`, `docs/jenkins`, `docs/index.md`

## 분석 요약

공유 대화의 핵심은 아래와 같습니다.

- 인프라 구축 순서를 고정
- VM/K8s 배치 원칙을 명확화
- Synology Reverse Proxy 단일 진입점 유지
- GitLab/Harbor/Jenkins 설치 기준(스펙, 방식, 검증) 정의

## 문서 반영

- `docs/proxmox/overview.md`
  - 아키텍처 원칙, 구축 순서, 금지사항 반영

- `docs/gitlab/installation.md`
  - `4 vCPU / 12GB RAM` 기준
  - Omnibus 설치, Registry 비활성 정책 반영

- `docs/harbor/installation.md`
  - VM + Docker Compose 설치
  - MinIO S3 backend 기준 반영

- `docs/jenkins/installation.md`
  - Kubernetes + Helm 설치
  - requests/limits, executor, LoadBalancer 기준 반영

- `docs/index.md`
  - `Build Order` 섹션 추가

## 비고

- 민감 정보는 플레이스홀더로 유지
- 공유 대화의 "설계 원칙 유지 + 따라하기" 요구를 문서 구조에 반영
