# Chat History: k8s-installation-proxmox-hw-images

## Session Info

- Date (UTC): `2026-03-06`
- Participants: `user`, `assistant`
- Topic: `k8s-installation-proxmox-hw-images`
- Related Paths: `docs/k8s/installation.md`, `assets/images/k8s/`

## Conversation Log

| Time (UTC) | Speaker | Message | Action Items |
| --- | --- | --- | --- |
| `04:08` | `user` | k8s/installation.md 파일 의 proxmox의 VM H/W 참고 이미지 활용하여 업데이트 해줘. 위치는 .local/scratch/스크린샷*.png 파일이야 | 스크린샷 반영 |
| `04:09` | `assistant` | `.local/scratch` 이미지 확인 후 `assets/images/k8s/`로 복사하고 설치 문서에 상대 경로 이미지 링크 추가 | 문서 업데이트 |

## Decisions

- `.local/` 경로는 문서 본문에 직접 링크하지 않고 `assets/images/k8s/`로 이관해 참조한다.
- Proxmox VM H/W 섹션에 cp1/cp2/cp3/w1/w2 이미지 5장을 모두 포함한다.

## Follow-ups

- [ ] `make lint` 가능한 환경 확보 후 문서 검증 재실행
