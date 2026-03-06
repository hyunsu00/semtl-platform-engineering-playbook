# Chat History: k8s-doc-update-from-shared-chat

## Session Info

- Date (UTC): `2026-03-06`
- Participants: `user`, `assistant`
- Topic: `k8s-doc-update-from-shared-chat`
- Related Paths: `docs/k8s/overview.md`, `docs/k8s/installation.md`, `docs/k8s/operation-guide.md`, `docs/k8s/troubleshooting.md`

## Conversation Log

| Time (UTC) | Speaker | Message | Action Items |
| --- | --- | --- | --- |
| `09:18` | `user` | 공유 ChatGPT 링크 분석해서 k8s 폴더 문서 업데이트 요청 | 공유 대화 분석/문서 반영 |
| `09:22` | `assistant` | 공유 대화에서 성공 경로 기준, 2/2/2/4/4, Ubuntu 22.04, vmbr1 내부망 우선 원칙을 추출하고 문서 반영 | 설치/운영/트러블슈팅 보강 |

## Decisions

- `docs/k8s/` 문서는 성공 경로 중심으로 유지한다.
- 표준 스펙은 `2/2/2/4/4 vCPU`, `8/8/8/12/12GB RAM`으로 통일한다.
- INTERNAL-IP는 내부망(`10.10.10.x`) 기준으로 운영한다.

## Follow-ups

- [ ] 필요 시 공유 대화의 추가 결정사항(예: 메뉴/템플릿 요청)을 문서 스타일 가이드에 확장 반영
