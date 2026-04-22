# Proxmox Storage And Network Expansion

## 개요

이 문서는 Proxmox 설치 후 아래 작업을 가장 단순한 순서로 정리합니다.

- `local-lvm` 제거
- `1TB NVMe`를 `k8s-service`로 재생성
- `2TB SSD`를 `vmct-service`로 재생성
- Kubernetes 내부망 `10.10.10.x`용 `vmbr1` 준비

현재 디스크 기준:

- OS 디스크: `/dev/nvme0n1`
- Kubernetes 용 디스크: `/dev/nvme1n1`
- VM/CT 용 디스크: `/dev/sda`

주의:

- `/dev/nvme0n1`은 OS 디스크이므로 초기화하지 않습니다.
- 추가 디스크에 기존 LVM/Thin 구성이 남아 있으면 바로 `디스크 초기화`가
  되지 않을 수 있습니다.

## 1) `local-lvm` 제거

1. `Datacenter` -> `Storage`
1. `local-lvm` 선택
1. 사용 중 디스크가 없는지 확인
1. `Remove`
1. Proxmox Shell 또는 SSH 접속
1. `pve-data` thinpool 제거
1. 남은 VG 여유 공간을 `pve-root`로 확장
1. 파일시스템 확장

CLI 절차:

```bash
# local-lvm에 연결된 thinpool 제거
lvremove /dev/pve/data

# 남은 VG 전체 공간을 root에 추가
lvextend -l +100%FREE /dev/pve/root

# ext4 기본 구성 기준 파일시스템 확장
resize2fs /dev/mapper/pve-root
```

확인 명령:

```bash
lvs
df -h /
```

결과:

- OS 영역 저장소는 `local`만 남음
- `pve-data`가 제거됨
- 남은 OS 디스크 공간이 `pve-root`로 확장됨
- `local`(`/var/lib/vz`)가 더 큰 root 파일시스템 공간을 사용함

주의:

- 위 파일시스템 확장 명령은 기본 `ext4` 구성 기준입니다.
- 만약 root 파일시스템이 `xfs`라면 `resize2fs` 대신 `xfs_growfs /`를 사용합니다.

## 2) `1TB NVMe`를 `k8s-service`로 재생성

대상 디스크: `/dev/nvme1n1`

먼저 기존 스토리지 등록이 남아 있으면 제거합니다.

1. `Datacenter` -> `Storage`
1. `vm-data`, `nvme-vg`, `k8s-service` 같은 관련 항목이 있으면 `Remove`

그다음 Proxmox Shell 또는 SSH에서 아래 명령을 실행합니다.

```bash
# 기존 시그니처 정리
wipefs -a /dev/nvme1n1

# PV/VG 생성
pvcreate /dev/nvme1n1
vgcreate nvme-vg /dev/nvme1n1

# Thinpool 생성(전체 용량 사용)
lvcreate -l 100%FREE -T -n k8s-service nvme-vg
```

생성 후 Web UI에서 스토리지를 등록합니다.

1. `Datacenter` -> `Storage` -> `Add` -> `LVM-Thin`
1. ID: `k8s-service`
1. Volume group: `nvme-vg`
1. Thin Pool: `k8s-service`

결과:

- `1TB NVMe`가 `k8s-service` 스토리지로 생성됨

확인 명령:

```bash
pvs
vgs
lvs
```

정상 예시:

- PV: `/dev/nvme1n1`
- VG: `nvme-vg`
- Thinpool LV: `k8s-service`

## 3) `2TB SSD`를 `vmct-service`로 재생성

대상 디스크: `/dev/sda`

먼저 기존 스토리지 등록이 남아 있으면 제거합니다.

1. `Datacenter` -> `Storage`
1. `vmct-data`, `ssd-vg`, `vmct-service` 같은 관련 항목이 있으면 `Remove`

그다음 Proxmox Shell 또는 SSH에서 아래 명령을 실행합니다.

```bash
# 기존 시그니처 정리
wipefs -a /dev/sda

# PV/VG 생성
pvcreate /dev/sda
vgcreate ssd-vg /dev/sda

# Thinpool 생성(전체 용량 사용)
lvcreate -l 100%FREE -T -n vmct-service ssd-vg
```

생성 후 Web UI에서 스토리지를 등록합니다.

1. `Datacenter` -> `Storage` -> `Add` -> `LVM-Thin`
1. ID: `vmct-service`
1. Volume group: `ssd-vg`
1. Thin Pool: `vmct-service`

결과:

- `2TB SSD`가 `vmct-service` 스토리지로 생성됨

확인 명령:

```bash
pvs
vgs
lvs
```

정상 예시:

- PV: `/dev/sda`
- VG: `ssd-vg`
- Thinpool LV: `vmct-service`

## 4) Kubernetes 내부망 `vmbr1` 준비

현재 적용 기준:

- 외부/관리 브리지: `vmbr0`
- `vmbr0` 주소: `192.168.0.253/24`
- `vmbr0` 게이트웨이: `192.168.0.1`
- `vmbr0` 포트: `eth1`
- 내부 브리지: `vmbr1`
- `vmbr1` 주소: `10.10.10.1/24`
- `vmbr1` 설명: `k8s internal network`

1. 노드 선택 -> `Network`
1. `Create` -> `Linux Bridge`

캡처 화면 기준 입력값:

- 이름: `vmbr1`
- IPv4/CIDR: `10.10.10.1/24`
- 게이트웨이(IPv4): 비움
- IPv6/CIDR: 비움
- 게이트웨이(IPv6): 비움
- 자동시작: 체크
- VLAN 감지: 미체크
- 브릿지 포트: 비움
- 설명: `k8s internal network`
- MTU: `1500`

운영 메모:

- 내부 전용망이면 외부 NIC를 연결하지 않습니다.
- Kubernetes 노드 VM은 보통 `vmbr0`와 `vmbr1` 두 개 NIC를 사용합니다.
- 현재 호스트 기본 게이트웨이는 `vmbr0`에만 설정합니다.
- `vmbr1`에는 게이트웨이를 넣지 않습니다.

## 5) 최종 확인

- `Datacenter -> Storage`에 `local-lvm`이 없어짐
- `k8s-service` 스토리지가 생성됨
- `vmct-service` 스토리지가 생성됨
- `vmbr0`가 `192.168.0.253/24`, gateway `192.168.0.1`, port `eth1`로 설정됨
- `vmbr1`가 생성됨

## 참고

- [Proxmox 설치 가이드](./installation.md)
- [Proxmox 개요](./overview.md)
- [RKE2 설치 가이드](../rke2/installation.md)
