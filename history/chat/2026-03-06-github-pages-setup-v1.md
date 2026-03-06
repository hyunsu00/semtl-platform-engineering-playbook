# Chat History: github-pages-setup

## Session Info

- Date (UTC): `2026-03-06`
- Participants: `user`, `assistant`
- Topic: `github-pages-setup`
- Related Paths: `mkdocs.yml`, `.github/workflows/pages.yml`, `docs/assets/images/k8s/`, `docs/k8s/installation.md`

## Conversation Log

| Time (UTC) | Speaker | Message | Action Items |
| --- | --- | --- | --- |
| `07:41` | `user` | github에 push한 작성한 문서 웹에서 바로 볼수는 없어? | GitHub Pages 구성 |
| `07:41` | `assistant` | MkDocs + GitHub Actions 배포 방식으로 구성 진행 | 사이트 배포 자동화 |
| `07:42` | `user` | 그렇게 해줘 | 배포 설정 반영 |

## Decisions

- 문서 웹 배포는 `mkdocs-material` 기반 GitHub Pages 워크플로로 자동화한다.
- Pages 빌드 호환을 위해 K8s 이미지 자산을 `docs/assets/images/k8s/`에도 반영한다.

## Follow-ups

- [ ] GitHub Actions 실행 완료 후 Pages URL 최종 확인
