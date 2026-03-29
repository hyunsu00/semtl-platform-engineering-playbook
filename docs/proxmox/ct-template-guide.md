# Proxmox CT Template Guide

## 개요

이 문서는 Proxmox에서 LXC 컨테이너를 표준 템플릿으로 준비하고,
필요한 CT를 반복 생성하는 절차를 정리합니다.

이 저장소 기준으로 CT는 주로 다음 용도로 사용합니다.

- `ct-lb1`, `ct-lb2` 같은 경량 인프라 CT
- 운영 보조용 `ct-devtools`
- SSH, `sudo`, 기본 패키지가 포함된 공통 베이스 CT

운영 기준으로는 템플릿 원본 CT를 먼저 정리한 뒤 `Template`로 변환하고,
실제 운영 CT는 `Full Clone`으로 생성해야 합니다.

## 사용 시점

- 동일한 Ubuntu 기반 CT를 여러 개 반복 생성해야 하는 경우
- `root` 직접 SSH 대신 운영 계정 + `sudo` 기준으로 표준화해야 하는 경우
- LB, 유틸리티, 경량 서비스 CT를 빠르게 배포해야 하는 경우

## 사전 조건

- Proxmox 설치와 기본 네트워크 검증 완료
- `vmbr0` 등 기본 브리지 준비 완료
- Proxmox 노드에서 LXC 템플릿 다운로드 가능
- 템플릿 원본 CT를 만들 스토리지 확보

## 1. LXC 템플릿 다운로드

Ubuntu 22.04 기준 템플릿을 먼저 받아야 합니다.

CLI 예시:

```bash
pveam update
pveam available | grep ubuntu-22.04
pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst
```

운영 메모:

- 이 저장소에서는 CT 예시를 주로 `Ubuntu 22.04` 기준으로 정리합니다.
- 템플릿 파일은 보통 `local` 스토리지의 `vztmpl`에 저장됩니다.

## 2. 템플릿 원본 CT 생성

템플릿 원본은 일반 CT로 먼저 생성한 뒤 내부 정리를 마치고 `Template`로 변환해야 합니다.

권장 기준:

- CT ID 예시: `9001`
- 이름 예시: `ct-template-ubuntu-2204`
- OS Template: `ubuntu-22.04-standard`
- Unprivileged CT: 사용
- Nesting: 기본 비활성
- 네트워크: `vmbr0`
- IP: DHCP 또는 임시 고정 IP

권장 리소스:

- vCPU: `1`
- RAM: `512MB`
- Root Disk: `8GB`

운영 메모:

- `Docker`, `Kubernetes`, `fuse` 등 특수 요구가 없으면 `nesting=1`은 열지 않아야 합니다.
- 운영 템플릿은 가능한 한 경량 상태로 유지해야 합니다.
- LXC CT는 VM이 아니므로 `qemu-guest-agent` 설치 대상이 아닙니다.

## 3. 템플릿 원본 CT 기본 설정

Proxmox 콘솔 또는 임시 SSH로 원본 CT에 접속한 뒤 기본 패키지를 정리해야 합니다.

```bash
apt update
apt install -y sudo openssh-server ca-certificates curl
systemctl enable --now ssh
```

운영 계정 생성:

```bash
adduser semtl
usermod -aG sudo semtl
id semtl
```

운영 기준:

- 이후 운영 CT는 `semtl` 계정 + `sudo` 기준으로 사용해야 합니다.
- 템플릿 원본에서도 `root` 직접 SSH 접근을 기본 운영 경로로 보지 않아야 합니다.

필요 시 접속 확인:

```bash
ssh semtl@<CT-IP>
sudo whoami
```

## 4. 템플릿 정리

템플릿 변환 전에는 머신 고유값과 임시 파일을 정리해야 합니다.

```bash
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id
apt clean
rm -rf /tmp/* /var/tmp/*
rm -f /root/.bash_history
rm -f /home/semtl/.bash_history
history -c
poweroff
```

정리 목적:

- 클론 시 머신 고유값 충돌 방지
- 임시 파일과 셸 히스토리 제거
- 표준 초기 상태로 템플릿 유지

## 5. CT 템플릿으로 변환

원본 CT가 `stopped` 상태인지 확인한 뒤 템플릿으로 변환해야 합니다.

Web UI:

1. 템플릿 원본 CT 선택
1. 상태가 `stopped`인지 확인
1. `More`
1. `Convert to template`

확인 기준:

- 좌측 트리에서 CT 아이콘이 템플릿 형태로 표시되어야 합니다.
- 일반 CT가 아니라 `Template`로 보여야 합니다.

운영 메모:

- 템플릿으로 변환한 뒤에도 다시 일반 CT로 되돌려 수정할 수 있습니다.
- 다만 운영 기준으로는 템플릿 원본을 반복 수정하기보다 새 버전 템플릿을 다시 만드는 편이 안전합니다.
- 실제 운영 CT 수정이 목적이면 템플릿을 직접 건드리기보다 `Full Clone` 후 조정해야 합니다.

## 6. 템플릿에서 CT 복제

운영 CT는 템플릿에서 `Full Clone`으로 생성해야 합니다.

Web UI:

1. 템플릿 선택
1. `Clone`
1. 새 CT ID 입력
1. 이름 입력
1. `Mode`에서 `Full Clone` 선택
1. 대상 스토리지 확인 후 생성

예시:

- `121` `ct-lb1`
- `122` `ct-lb2`
- `131` `ct-devtools`

## 7. 클론 후 초기 보정

복제 후에는 hostname, IP, SSH 접속, `sudo` 동작을 확인해야 합니다.

확인 예시:

```bash
hostnamectl
ip -br a
ip route
ssh semtl@<CT-IP>
sudo whoami
```

운영 메모:

- `ct-lb1`, `ct-lb2`처럼 Keepalived를 사용하는 CT는 동일 브리지와 동일 대역에 있어야 합니다.
- 클론 후 고정 IP를 사용할 경우 `/etc/netplan/` 또는 Proxmox CT 네트워크 설정에서 최종 주소를 확인해야 합니다.
- 템플릿에 서비스별 설정까지 넣기보다 OS 기본 상태까지만 포함하는 편이 유지보수에 유리합니다.

## 참고

- Proxmox 설치 본문: [Proxmox Installation](./installation.md)
- Proxmox 개요: [Proxmox Overview](./overview.md)
- VM 템플릿 문서: [Proxmox VM Template Guide](./vm-template-guide.md)
