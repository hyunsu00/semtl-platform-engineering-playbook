# Chat History: k8s-doc-generation

## Session Info
- Date (UTC): `2026-03-06`
- Participants: `user`, `assistant`
- Topic: `k8s-doc-generation`
- Related Paths: `docs/k8s/installation.md`, `docs/k8s/overview.md`, `docs/k8s/operation-guide.md`, `docs/k8s/troubleshooting.md`

## Conversation Log
| Time (UTC) | Speaker | Message | Action Items |
| --- | --- | --- | --- |
| `03:47` | `user` | Proxmox_Kubernetes_HA_전체_설치_가이드.md, proxmox-k8s-ha-setup-guide.md 참고해서 k8s 문서 생성해주는데 설치 관련해서 빼먹는거 없이 만들어 줘야되 | 참고 문서 기반 설치 문서 상세화 |
| `03:48` | `assistant` | 참고 문서 섹션/명령을 추출해 `docs/k8s/` 문서를 설치 중심으로 재작성 진행 | 설치/운영/장애 문서 동기화 |

## Decisions
- 설치 누락 방지를 위해 Proxmox VM 생성부터 CNI, VIP, MetalLB, ingress, etcd 백업까지 전 단계를 설치 문서에 포함한다.
- 기존 `docs/k8s/` 스텁 문서를 실제 운영 가능한 수준으로 함께 갱신한다.

## Follow-ups
- [ ] `make lint`와 `make link-check` 실행 환경 준비 후 문서 검증
