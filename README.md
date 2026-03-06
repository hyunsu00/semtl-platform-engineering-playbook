# SEMTL Platform Engineering Playbook

Proxmox, Jenkins, Harbor, GitLab, Kubernetes, Keycloak, Prometheus, Grafana, Argo CD 등 플랫폼 엔지니어링 영역의 설치/설정/운용 문서를 지속적으로 관리하는 저장소입니다.

## 목적
- 설치 및 초기 구성 절차 표준화
- 운영 기준(백업, 모니터링, 장애 대응) 문서화
- 변경 이력 기반의 지속 개선

## 디렉터리 구조
```text
.
├── docs/                # 최종 사용자/운영자용 문서
├── assets/              # 문서에서 사용하는 이미지/첨부 파일
│   └── images/
├── templates/           # 재사용 가능한 문서 템플릿
├── scripts/             # 문서 검사/변환/자동화 스크립트
└── Makefile             # 공통 명령어 진입점
```

## 시작하기
```bash
make setup
make lint
make link-check
```

## 문서 작성 규칙
- 각 문서는 H1(`#`) 하나만 사용
- 파일명은 `kebab-case` 사용 (예: `argocd-installation-guide.md`)
- 내부 링크는 상대 경로 우선
- 명령어/경로/환경 변수는 실제 실행 가능한 형태로 작성

## 권장 문서 맵
- `docs/proxmox/overview.md`
- `docs/jenkins/installation.md`
- `docs/harbor/operation-guide.md`
- `docs/gitlab/backup-and-restore.md`
- `docs/k8s/cluster-bootstrap.md`
- `docs/keycloak/sso-integration.md`
- `docs/prometheus/monitoring-basics.md`
- `docs/grafana/dashboard-guide.md`
- `docs/argocd/gitops-workflow.md`

## 검증
```bash
make lint
make link-check
```

## 변경 이력 관리
문서 변경은 가능하면 작은 단위로 커밋하며, Conventional Commits를 권장합니다.
- `docs: ...`
- `fix: ...`
- `chore: ...`
