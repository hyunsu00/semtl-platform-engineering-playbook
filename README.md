# SEMTL Platform Engineering Playbook

Synology, AdGuard Home, Proxmox, MinIO, Jenkins, n8n, Harbor, GitLab,
Kubernetes, Keycloak, Prometheus, Grafana, Argo CD 등 플랫폼 엔지니어링 영역의
설치/설정/운용 문서를 지속적으로 관리하는 저장소입니다.

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

- `docs/synology/installation.md`
  (Synology DNS Server, DHCP DNS 배포, PBS NFS Export 준비)
- `docs/synology/tailscale-installation.md`
  (Synology DSM에서 Tailscale 설치, 자동 업데이트, DSM7 outbound 연결 활성화)
- `docs/synology/wireguard-zigbee2mqtt-ha-integration.md`
  (WireGuard VM 게이트웨이, Zigbee2MQTT 원격 브리지 연결, Home Assistant 연동)
- `docs/adguardhome/installation.md`
  (Synology Container Manager 기반 AdGuard Home 설치, DNS/필터 최적화)
- `docs/proxmox/overview.md`
- `docs/proxmox/vm-template-guide.md`
  (Proxmox VM 템플릿 등록, Cloud-Init 기반 복제 절차)
- `docs/proxmox/storage-and-network-expansion.md`
  (추가 디스크 구성, Kubernetes 사설망 `10.0.0.x` 준비)
- `docs/proxmox/dns-and-hostname-guide.md`
  (Proxmox Host / DHCP VM DNS·hostname 표준)
- `docs/proxmox/config-backup-and-restore.md`
  (Proxmox 로컬 설정 백업 스크립트, 검증, 복구 절차)
- `docs/pbs/installation.md`
  (Proxmox Backup Server 설치, hostname/DNS 보정, 초기 관리 설정)
- `docs/pbs/operation-guide.md`
  (Proxmox VE 연동, 백업 작업, PBS 트러블슈팅)
- `docs/minio/installation.md`
- `docs/minio/operation-guide.md`
- `docs/minio/oidc-integration.md` (MinIO-Keycloak OIDC 전용)
- `docs/jenkins/installation.md`
- `docs/jenkins/kubernetes-agent-integration.md` (Jenkins-Kubernetes Agent 연동)
- `docs/n8n/installation.md`
- `docs/harbor/installation.md`
- `docs/harbor/minio-integration.md` (Harbor-MinIO S3 backend 연동)
- `docs/harbor/operation-guide.md`
- `docs/harbor/oidc-integration.md` (Harbor-Keycloak OIDC 전용)
- `docs/gitlab/harbor-integration.md` (GitLab-Harbor Registry 연동)
- `docs/gitlab/minio-integration.md` (GitLab-MinIO Object Storage 연동)
- `docs/gitlab/oidc-integration.md` (GitLab-Keycloak OIDC 전용)
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
