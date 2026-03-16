# Proxmox Overview

## 목적

이 문서는 Proxmox 기반 DevOps 인프라의
구성 원칙과 구축 순서를 정의합니다.

## 기준 아키텍처

- 상태 저장 서비스: VM에 배치
- 변동 부하 서비스: Kubernetes에 배치
- 외부 노출: Synology Reverse Proxy 단일 진입점
- 관리/서비스 브리지: `vmbr0` (`192.168.0.254/24`, gateway `192.168.0.1`)
- 내부 Kubernetes 브리지: `vmbr1` (`10.10.10.1/24`, gateway 없음)
- 업링크 NIC: `nic0` (`enp0s31f6` 계열 장치)

## 구축 순서 (고정)

1. PBS VM 생성/설치
1. MinIO VM 생성/설치
1. GitLab VM 생성/Omnibus 설치
1. Harbor VM 생성/Docker Compose 설치
1. Jenkins VM 생성 및 직접 설치
1. n8n VM 생성 및 설치
1. Kubernetes에 GitLab Runner 설치
1. Synology Reverse Proxy 라우팅 구성

## VM/CT 기준 배치

### CT 리소스

| ID | 이름 |
| --- | --- |
| `121` | `ct-lb1` |
| `122` | `ct-lb2` |
| `131` | `ct-devtools` |

### DevOps VM 리소스

| ID | 이름 |
| --- | --- |
| `100` | `vm-pbs` |
| `101` | `vm-minio` |
| `102` | `vm-gitlab` |
| `103` | `vm-harbor` |
| `104` | `vm-jenkins` |
| `105` | `vm-n8n` |

### Kubernetes VM

| ID | 이름 |
| --- | --- |
| `201` | `k8s-cp1` |
| `202` | `k8s-cp2` |
| `203` | `k8s-cp3` |
| `211` | `k8s-w1` |
| `212` | `k8s-w2` |

## 네트워크 기준

현재 Proxmox 노드의 확정 네트워크 구성은 아래와 같습니다.

| 항목 | 값 |
| --- | --- |
| 물리 NIC | `nic0` |
| Linux 이름 | `enp0s31f6` |
| 브리지 1 | `vmbr0` |
| `vmbr0` 용도 | 관리망 + 일반 VM/CT 서비스망 |
| `vmbr0` 주소 | `192.168.0.254/24` |
| `vmbr0` 게이트웨이 | `192.168.0.1` |
| `vmbr0` bridge-port | `nic0` |
| 브리지 2 | `vmbr1` |
| `vmbr1` 용도 | Kubernetes 내부 전용망 |
| `vmbr1` 주소 | `10.10.10.1/24` |
| `vmbr1` 게이트웨이 | 없음 |
| `vmbr1` bridge-port | 없음 |

운영 원칙:

- 일반 VM과 CT는 기본적으로 `vmbr0`를 사용합니다.
- Kubernetes 노드는 `vmbr0`와 `vmbr1`를 함께 연결합니다.
- `vmbr1`는 내부 전용 브리지이므로 물리 NIC를 연결하지 않습니다.
- Proxmox 호스트의 기본 라우팅은 `vmbr0`를 통해 외부망으로 나갑니다.

## 최종 리소스 계획

현재 Proxmox 물리 서버 기준 리소스는 `20 cores / 64GB RAM`입니다.
아래 계획은 DevOps VM, Kubernetes, 보조 CT를 함께 운영하는 최종 기준안입니다.

### CT (LXC)

| CT | vCPU | Memory | Swap |
| --- | --- | --- | --- |
| `ct-lb1` (`121`) | 1 | `512MB` | `512MB` |
| `ct-lb2` (`122`) | 1 | `512MB` | `512MB` |
| `ct-devtools` (`131`) | 2 | `2GB` | `1GB` |

합계:

- CPU: `4 vCPU`
- RAM: `3GB`

하드웨어 상세:

| CT | Root Disk | Storage |
| --- | --- | --- |
| `ct-lb1` (`121`) | `8GB` | `vmct-service` |
| `ct-lb2` (`122`) | `8GB` | `vmct-service` |
| `ct-devtools` (`131`) | `40GB` | `vmct-service` |

### DevOps VM

| VM | vCPU | 최소 RAM | 최대 RAM |
| --- | --- | --- | --- |
| `vm-pbs` (`100`) | 2 | `2GB` | `4GB` |
| `vm-minio` (`101`) | 2 | `4GB` | `6GB` |
| `vm-gitlab` (`102`) | 4 | `12GB` | `16GB` |
| `vm-harbor` (`103`) | 4 | `4GB` | `6GB` |
| `vm-jenkins` (`104`) | 2 | `4GB` | `8GB` |
| `vm-n8n` (`105`) | 2 | `2GB` | `4GB` |

합계:

- CPU: `16 vCPU`
- 최소 RAM: `28GB`
- 최대 RAM: `44GB`

하드웨어 상세:

| VM | BIOS/Machine | OS Disk | Network |
| --- | --- | --- | --- |
| `vm-pbs` (`100`) | `UEFI/q35` | `40GB` / `vmct-service` | `vmbr0` |
| `vm-minio` (`101`) | `UEFI/q35` | `40GB` / `vmct-service` | `vmbr0` |
| `vm-gitlab` (`102`) | `UEFI/q35` | `60GB` / `vmct-service` | `vmbr0` |
| `vm-harbor` (`103`) | `UEFI/q35` | `60GB` / `vmct-service` | `vmbr0` |
| `vm-jenkins` (`104`) | `UEFI/q35` | `60GB` / `vmct-service` | `vmbr0` |
| `vm-n8n` (`105`) | `UEFI/q35` | `60GB` / `vmct-service` | `vmbr0` |

설정 이유:

- GitLab: 단일 운영 규모 기준으로 Sidekiq, Puma, Gitaly를 감안해 `4 vCPU`
- Harbor: Registry 및 이미지 처리 부하를 고려해 `4 vCPU`
- Jenkins: Controller는 전용 VM에 직접 설치하고, 빌드 실행은
  Kubernetes agent 연동 기준으로 `2 vCPU`로 운영
- MinIO: CPU보다 디스크 I/O와 네트워크 영향이 더 큼

### Kubernetes Control Plane 리소스

| VM | vCPU | 최소 RAM | 최대 RAM |
| --- | --- | --- | --- |
| `k8s-cp1` | 2 | `6GB` | `8GB` |
| `k8s-cp2` | 2 | `6GB` | `8GB` |
| `k8s-cp3` | 2 | `6GB` | `8GB` |

합계:

- CPU: `6 vCPU`
- RAM: `18GB ~ 24GB`

하드웨어 상세:

| VM | BIOS/Machine | OS Disk | Network |
| --- | --- | --- | --- |
| `k8s-cp1` (`201`) | `UEFI/q35` | `60GB` / `k8s-service` | `vmbr0+vmbr1` |
| `k8s-cp2` (`202`) | `UEFI/q35` | `60GB` / `k8s-service` | `vmbr0+vmbr1` |
| `k8s-cp3` (`203`) | `UEFI/q35` | `60GB` / `k8s-service` | `vmbr0+vmbr1` |

### Kubernetes Worker 리소스

| VM | vCPU | 최소 RAM | 최대 RAM |
| --- | --- | --- | --- |
| `k8s-w1` | 4 | `6GB` | `12GB` |
| `k8s-w2` | 4 | `6GB` | `12GB` |

합계:

- CPU: `8 vCPU`
- RAM: `12GB ~ 24GB`

하드웨어 상세:

| VM | BIOS/Machine | OS Disk | Network |
| --- | --- | --- | --- |
| `k8s-w1` (`211`) | `UEFI/q35` | `200GB` / `k8s-service` | `vmbr0+vmbr1` |
| `k8s-w2` (`212`) | `UEFI/q35` | `200GB` / `k8s-service` | `vmbr0+vmbr1` |

### 전체 리소스 합계

CPU:

| 구분 | 합계 |
| --- | --- |
| CT | `4 vCPU` |
| DevOps | `16 vCPU` |
| Kubernetes | `14 vCPU` |
| Total | `34 vCPU` |

- 물리 CPU: `20 cores`
- CPU overcommit: `34 / 20 = 1.7x`
- 평가: 운영 기준에서 비교적 안정적인 CPU overcommit 범위

RAM(최소 기준):

| 구분 | 합계 |
| --- | --- |
| CT | `3GB` |
| DevOps | `28GB` |
| Kubernetes | `30GB` |
| Total | `61GB` |

- 물리 RAM: `64GB`
- 최소 기준 잔여 RAM: `3GB`

RAM(최대 기준):

| 구분 | 합계 |
| --- | --- |
| CT | `3GB` |
| DevOps | `44GB` |
| Kubernetes | `48GB` |
| Total | `95GB` |

- RAM overcommit: `95 / 64 = 1.48x`
- 평가: Ballooning + KSM 사용 조건에서 운영 가능한 범위

### 운영 여유와 확장 기준

- KSM 절감 효과: 대략 `5GB ~ 10GB`
- 체감 메모리 여유: `64GB` 물리 서버를 약 `70GB` 수준으로 운용하는 효과 기대
- 현재 CPU 여유: `34 vCPU` 사용 계획 기준, 실무상 `40 ~ 44 vCPU`까지 확장 여지
- 추가 가능 CPU: 대략 `6 ~ 10 vCPU`
- 현재 RAM 여유: 최소 할당 기준 `3GB`
- KSM 체감 포함 RAM 여유: 대략 `5GB ~ 8GB`

추가 배치 예시:

- 소형 VM: `2 vCPU / 2GB ~ 4GB`는 `2 ~ 3대` 추가 가능
- 중형 VM: `4 vCPU / 4GB ~ 8GB`는 `1 ~ 2대` 추가 가능
- Kubernetes Worker 추가: `4 vCPU / 6GB ~ 12GB`는 가능하지만 RAM 모니터링 필요

### 최종 평가

`20 cores / 64GB RAM` 기준에서 현재 구성은 DevOps 서비스와 Kubernetes를 함께
운영하기에 균형이 잘 맞는 편입니다.

- CPU 여유: 좋음
- RAM 여유: 다소 타이트하지만 정상 범위
- 확장성: 추가 VM 또는 Worker 증설 여지 있음

## 문서 매핑

- Proxmox 배치 원칙: 이 문서
- 디스크/사설망 확장: `docs/proxmox/storage-and-network-expansion.md`
- GitLab 설치 상세: `docs/gitlab/installation.md`
- Harbor 설치 상세: `docs/harbor/installation.md`
- Jenkins 설치 상세: `docs/jenkins/installation.md`
- Kubernetes 운영: `docs/k8s/operation-guide.md`
