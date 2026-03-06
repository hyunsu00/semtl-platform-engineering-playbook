# Chat History: chat-history-policy

## Session Info
- Date (UTC): `2026-03-06`
- Participants: `user`, `assistant`
- Topic: `chat-history-policy`
- Related Paths: `AGENTS.md`, `templates/chat-history-template.md`, `history/chat/`

## Conversation Log
| Time (UTC) | Speaker | Message | Action Items |
| --- | --- | --- | --- |
| `03:37` | `user` | 너와 나의 채팅 기록 history 남겼으면 하는데. AGENTS.md에도 명시 해줘. history 양식도 필요할거고 채팅 히스토리 기록도 형상관리 할꺼야 | 채팅 히스토리 정책/양식 반영 |
| `03:38` | `assistant` | `AGENTS.md`에 규칙을 추가하고 템플릿/초기 히스토리 파일을 생성하기로 결정 | 정책 문서화 및 파일 생성 |

## Decisions
- 채팅 히스토리는 `.local/`이 아니라 `history/chat/`에서 Git으로 관리한다.
- 공통 양식은 `templates/chat-history-template.md`를 기준으로 사용한다.

## Follow-ups
- [ ] 이후 세션부터 동일 양식으로 `history/chat/`에 지속 기록
