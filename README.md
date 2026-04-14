# SEMTL Platform Engineering Playbook

Synology, AdGuard Home, Proxmox, MinIO, Jenkins, n8n, Harbor, GitLab,
RKE2, VM-ADMIN, VM-OMADA, Keycloak, Monitoring, Argo CD 등 플랫폼 엔지니어링 영역의
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
- `docs/proxmox/ct-template-guide.md`
  (Proxmox CT 템플릿 등록, 운영 계정 포함 표준 LXC 복제 절차)
- `docs/vm-devtools/installation.md`
  (Synology VMM 기반 vm-devtools VM 생성, semtl 계정, SSH, Docker,
  Homepage/Uptime Kuma/Dozzle 구성)
- `docs/vm-omada/installation.md`
  (Ubuntu 22.04 VM 기반 Omada Controller 설치, Docker 구성, 초기 접속 확인)
- `docs/proxmox/vm-template-guide.md`
  (Proxmox VM 템플릿 등록, Cloud-Init 기반 복제 절차)
- `docs/proxmox/storage-and-network-expansion.md`
  (추가 디스크 구성, Kubernetes 사설망 `10.0.0.x` 준비)
- `docs/proxmox/dns-and-hostname-guide.md`
  (Proxmox Host / DHCP VM DNS·hostname 표준)
- `docs/proxmox/config-backup-and-restore.md`
  (Proxmox 로컬 설정 백업 스크립트, 검증, 복구 절차)
- `docs/proxmox/amt-watchdog-and-alerting.md`
  (Intel AMT 응답 불안정 원인 분석, GRUB 보정, Synology NAS 감시/Telegram 알림)
- `docs/ttyd/installation.md`
  (Ubuntu/Alpine Linux에서 ttyd 설치, 서비스 등록, 기본 검증)
- `docs/upsnap/installation.md`
  (Docker 기반 Upsnap 설치, 장비 등록, Wake-on-LAN 검증)
- `docs/tmux/installation.md`
  (Ubuntu/Alpine Linux에서 tmux 설치, 세션/윈도우/패인 기본 사용법)
- `docs/pbs/installation.md`
  (Proxmox Backup Server 설치, hostname/DNS 보정, 초기 관리 설정)
- `docs/pbs/operation-guide.md`
  (Proxmox VE 연동, 백업 작업, PBS 트러블슈팅)
- `docs/minio/installation.md`
- `docs/minio/harbor-integration.md` (MinIO-Harbor 외부 스토리지 연동)
- `docs/minio/gitlab-integration.md` (MinIO-GitLab Object Storage 연동)
- `docs/minio/jenkins-integration.md` (MinIO-Jenkins Artifact Storage 연동)
- `docs/minio/n8n-integration.md`
  (n8n Enterprise 도입 시 참고하는 MinIO-n8n Binary Storage 절차)
- `docs/vm-admin/installation.md`
  (운영 전용 관리 노드 구성, kubectl 원격 제어, MinIO mc 관리, snap 정리)
- `docs/jenkins/installation.md`
- `docs/n8n/installation.md`
- `docs/harbor/installation.md`
- `docs/gitlab/harbor-integration.md` (GitLab-Harbor Registry 연동)
- `docs/gitlab/backup-and-restore.md`
- `docs/rke2/installation.md`
  (RKE2 단일 control-plane, worker 3대 기준 설치 및 초기 검증)
- `docs/metallb/installation.md`
  (RKE2 설치 직후 MetalLB L2 구성, `ingress-nginx` 외부 IP 할당)
- `docs/keycloak/installation.md`
- `docs/keycloak/group-and-role-strategy.md` (Keycloak 공통 그룹/권한 전략)
- `docs/keycloak/minio-oidc-integration.md` (Keycloak-MinIO OIDC 연동)
- `docs/monitoring/installation.md`
  (`kube-prometheus-stack` 기반 Prometheus, Grafana, Alertmanager 통합 설치)
- `docs/loki/installation.md`
  (MinIO object storage 기반 Loki 설치, Grafana 데이터소스 연결, 초기 로그 조회 검증)
- `docs/rancher/installation.md`
  (Rancher 설치, external TLS 종료 기준 구성, UI 활용 범위와 현재 단계 필요성 정리)
- `docs/cert-manager/installation.md`
  (Kubernetes 내부 TLS 자동화용 cert-manager 설치, 현재 구조에서 아직 필수가 아닌 이유 정리)
- `docs/velero/installation.md`
  (Kubernetes 백업/복구용 Velero 설치, MinIO 백업 저장소 연결, 초기 백업 검증)
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
