# Chat History: k8s-operation-guide-inline-comments

## Session Info

- Date (UTC): `2026-03-06`
- Participants: `user`, `assistant`
- Topic: `k8s-operation-guide-inline-comments`
- Related Paths: `docs/k8s/operation-guide.md`

## Conversation Log

| Time (UTC) | Speaker | Message | Action Items |
| --- | --- | --- | --- |
| `04:14` | `user` | 명령어 설명 말고 ```bash ``` 안의 명령어시 위에 # 붙여서 설명 넣어달라고 | bash 내부 주석 방식 반영 |
| `04:14` | `assistant` | 모든 주요 bash 블록의 명령 위에 `#` 설명 주석을 넣고 외부 설명 문구를 제거 | 문서 포맷 통일 |

## Decisions

- 명령어 설명은 코드블록 외부가 아니라 bash 블록 내부 주석(`#`)으로 유지한다.

## Follow-ups

- [ ] installation/troubleshooting 문서도 같은 포맷 적용 여부 검토
