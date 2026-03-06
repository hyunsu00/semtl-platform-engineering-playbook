# Repository Guidelines

## 프로젝트 구조와 문서 구성
이 저장소는 문서 중심 저장소입니다. 콘텐츠는 `docs/` 아래 플랫폼별로 정리합니다.
- `docs/<component>/overview.md`
- `docs/<component>/installation.md`
- `docs/<component>/operation-guide.md`
- `docs/<component>/troubleshooting.md`

현재 운영 컴포넌트 예시: `proxmox`, `minio`, `k8s`, `gitlab`, `harbor`, `jenkins`, `keycloak`, `prometheus`, `grafana`, `argocd`

문서에서 참조하는 다이어그램/스크린샷은 `assets/images/`를 사용합니다. 기본 뼈대는 `templates/how-to-template.md`를 재사용합니다. `scripts/`는 자동화 유틸리티용 디렉터리이며(현재는 최소 구성), 기여자가 실행할 공통 명령은 `Makefile`을 기준으로 합니다.

참고 원본 문서(벤더 가이드, 티켓 첨부, 임시 덤프)는 형상관리 대상이 아닙니다. 로컬 전용 경로인 `.local/` 아래에만 저장합니다.
- `.local/references/vendor/`
- `.local/references/tickets/`
- `.local/references/dumps/`
- `.local/scratch/`

`.local/` 구조 설명:
```text
.local/
├── references/
│   ├── vendor/    # 벤더/공식 문서 원본(PDF, 가이드, 릴리즈 노트)
│   ├── tickets/   # Jira/GitLab 이슈 등 티켓 기반 참고 자료
│   └── dumps/     # 로그, 설정 덤프, 임시 추출 파일
└── scratch/       # 초안, 메모, 임시 변환 결과(폐기 가능)
```
쉽게 말해 `references/`는 "근거 자료 보관함", `scratch/`는 "작업 중 임시 폴더"입니다.

`.local/` 파일명 규칙:
- 기본 패턴: `YYYY-MM-DD-출처-주제-버전.확장자`
- 날짜는 문서를 저장한 날짜(UTC 기준)를 사용합니다.
- 공백 대신 `-`를 사용하고, 모두 소문자 `kebab-case`로 작성합니다.
- 같은 주제의 후속본은 `v2`, `v3`처럼 버전을 올립니다.

예시:
- `.local/references/vendor/2026-03-06-hashicorp-vault-install-guide-v1.pdf`
- `.local/references/tickets/2026-03-06-jira-plat-1423-keycloak-sso-timeout-v2.md`
- `.local/references/dumps/2026-03-06-k8s-prod-apiserver-log-v1.txt`
- `.local/scratch/2026-03-06-gitlab-backup-procedure-draft-v1.md`

## 채팅 히스토리 관리
사용자-에이전트 채팅 기록은 형상관리 대상이며 `history/chat/` 아래에 저장합니다.
- 경로: `history/chat/`
- 템플릿: `templates/chat-history-template.md`
- 파일명 패턴: `YYYY-MM-DD-주제-vN.md`
- 시간 표기: UTC 기준 `HH:MM`
- 파일명/주제는 소문자 `kebab-case` 사용

예시:
- `history/chat/2026-03-06-agents-md-history-policy-v1.md`
- `history/chat/2026-03-06-gitlab-runbook-review-v2.md`

채팅 히스토리 작성 규칙:
- 문서마다 H1(`#`)은 1개만 사용합니다.
- `Session Info` 섹션에 날짜(UTC), 참여자, 주제, 관련 경로를 기록합니다.
- 대화 본문은 `Time | Speaker | Message | Action Items` 표 형식을 사용합니다.
- 민감 정보(토큰, 비밀번호, 내부 URL)는 기록 전에 마스킹합니다.
- 참고 원본과 달리 채팅 히스토리는 `.local/`이 아니라 Git 추적 경로(`history/chat/`)에 저장합니다.

## 빌드, 검증, 개발 명령어
모든 명령은 저장소 루트에서 실행합니다.
- `make setup`: 권장 도구(`markdownlint-cli`, `lychee`)가 없으면 설치합니다.
- `make lint`: `**/*.md` 전체의 Markdown 포맷을 검사합니다.
- `make link-check`: Markdown 파일의 내부/외부 링크를 검사합니다.
- `make dev`: 자리표시자 타깃이며, 현재 로컬 미리보기 서버는 없습니다.

PR 생성 전 권장 검증 순서:
```bash
make lint
make link-check
```

## 작성 스타일과 네이밍 규칙
- 문서 파일마다 H1(`#`)은 정확히 1개만 사용합니다.
- 섹션은 짧게 유지하고, 작업 중심 절차와 실행 가능한 명령 예시를 우선합니다.
- 내부 참조는 상대 경로 링크를 사용합니다.
- 명령어, 경로, 환경 변수는 백틱으로 감쌉니다.
- 파일명은 `kebab-case`를 사용합니다(예: `backup-and-restore.md`).
- GitHub Pages 메뉴 라벨은 한국어를 기본으로 사용하며, 파일명/경로는 기존 패턴(`kebab-case`)을 유지합니다.

새 컴포넌트 가이드를 추가할 때는 `docs/` 하위의 기존 폴더/파일 네이밍 패턴을 그대로 따릅니다.
문서를 신설/대폭 업데이트할 때는 관련 항목이 `README.md`, `AGENTS.md`, `mkdocs.yml`에 반영됐는지 함께 확인합니다.
운영 절차 중 주제가 커지면(예: OIDC/SSO) `docs/<component>/` 하위에 별도 문서로 분리해 유지보수합니다.
OIDC/SSO 분리 문서 파일명은 `oidc-integration.md` 패턴을 우선 사용합니다.
OIDC 문서는 Keycloak 측(Client/Realm)과 서비스 측(redirect/callback)의 정합성 검증 절차를 반드시 포함합니다.

## 검증 가이드
이 저장소에는 단위 테스트 프레임워크가 없으며, 품질 게이트는 문서 검증입니다.
- 포맷 검사: `make lint`
- 링크 무결성 검사: `make link-check`

문서 변경 시 두 검사는 필수로 통과해야 합니다. 경고는 숨기지 말고 수정합니다.

## 커밋 및 PR 가이드
히스토리에 맞춰 Conventional Commits 스타일을 사용합니다. 특히 다음 접두사를 권장합니다.
- `docs: ...`
- `fix: ...`
- `chore: ...`

커밋 메시지 작성 규칙:
- 커밋 메시지 본문(요약 문장)은 한글로 작성합니다.
- 필요 시 Conventional Commits 접두사(`docs:`, `fix:`, `chore:` 등)는 유지할 수 있습니다.

커밋은 작은 단위로 유지하고, 한 개의 주제/컴포넌트에 집중합니다. PR에는 다음을 포함합니다.
- 변경된 문서와 영향 경로 요약(예: `docs/gitlab/`)
- 운영 절차 변경의 이유
- 이미지 기반 절차/다이어그램을 수정한 경우에만 스크린샷 첨부
- `make lint`, `make link-check` 통과 여부

## 보안 및 설정 주의사항
시크릿, 토큰, 비공개 URL, 환경별 자격 증명은 절대 커밋하지 않습니다. 예시에는 플레이스홀더를 사용하고 민감 정보는 반드시 마스킹합니다.

참고 문서 운영 원칙:
- 참고 원본은 `.local/`에만 저장하고 Git에 커밋하지 않습니다.
- 최종 결과물만 `docs/`, `assets/images/`에 반영합니다.
- 문서 본문에서 `.local/` 경로를 링크하지 않습니다.
