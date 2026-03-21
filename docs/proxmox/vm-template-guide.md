# Proxmox VM Template Guide

## 개요

이 문서는 Proxmox에서 기본 VM을 `Cloud-Init` 기반 템플릿으로 등록하고,
필요한 VM을 반복 생성하는 참고 절차를 정리합니다.

운영 환경에서는 일반적으로 `Full Clone`을 사용하고, 네트워크는 `Cloud-Init`
에서 DHCP로 맞춥니다. hostname은 VM 이름이 첫 부팅 시 반영되는지 먼저
확인하는 방식을 권장합니다.

## 사용 시점

- Ubuntu 계열 VM을 반복 생성해야 하는 경우
- VM마다 hostname을 다르게 적용해야 하는 경우
- Kubernetes 노드, GitLab Runner, 일반 서비스 VM을 표준 이미지로 배포해야 하는 경우

## 사전 조건

- Proxmox 설치와 기본 네트워크 검증 완료
- 템플릿으로 만들 VM의 OS 설치 완료
- VM 내부에 `cloud-init`, `qemu-guest-agent` 설치 가능

## 1. 기본 VM 준비

템플릿 원본 VM은 일반 VM으로 먼저 설치합니다.

권장 기준:

- VM ID 예시: `9000`
- 이름 예시: `vm-template`
- 디스크는 `scsi0` 사용 권장
- 네트워크는 기본적으로 `vmbr0` 연결

Ubuntu 예시 (`sudo` 권한이 있는 사용자 기준):

```bash
sudo apt update
sudo apt install -y cloud-init qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent
sudo cloud-init clean
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
sudo ln -s /etc/machine-id /var/lib/dbus/machine-id
sudo rm -rf /tmp/* /var/tmp/*
rm -f ~/.bash_history
history -c
sudo shutdown -h now
```

정리 목적:

- 기존 인스턴스의 머신 고유값 초기화
- 임시 파일과 사용자 히스토리 제거
- 클론 시 `cloud-init`이 첫 부팅 초기화 작업을 다시 수행하도록 준비

운영 메모:

- 템플릿 VM에는 애플리케이션별 설정을 최소화하고 OS 기본 상태만 남깁니다.
- 네트워크는 DHCP 기준으로 두고, 템플릿 안에 고정 IP를 직접 넣지 않는 구성을 권장합니다.

## 2. Cloud-Init 디스크 추가

이 문서는 Proxmox UI 기준으로 작업하는 흐름을 우선 사용합니다.
템플릿 원본 VM에 `cloud-init` 디스크를 추가할 때도 먼저 UI에서 진행합니다.
앞 단계 정리 명령을 실행한 뒤 게스트 내부에서 종료한 상태를 기준으로 진행합니다.

Web UI 경로:

1. 템플릿 원본 VM 선택
1. VM 상태가 `stopped`인지 확인
1. `Hardware`
1. `Add`
1. `CloudInit Drive`
1. 스토리지로 `vmct-service` 선택
1. 추가 후 `Options`에서 `Boot Order`를 `scsi0` 우선으로 확인

주의:

- `CloudInit Drive` 추가와 템플릿 변환 전에는 VM을 종료 상태로 맞추는 것을 권장합니다.
- `CloudInit Drive`는 비어 있는 IDE 슬롯에 자동으로 붙을 수 있습니다.
- `ide0`, `ide1`, `ide2`처럼 번호가 달라도 정상입니다.
- Proxmox UI 기본 콘솔 화면을 사용할 계획이면 시리얼 콘솔 설정은 추가하지 않습니다.
- 기본 화면이 보여야 하는 운영 기준에서는 Display 기본값을 유지합니다.

## 3. 템플릿으로 변환

템플릿 변환은 Web UI 기준으로 수행합니다.

Web UI:

1. 템플릿 원본 VM 선택
1. VM 상태가 `stopped`인지 확인
1. `More`
1. `Convert to template`

확인 기준:

- 좌측 트리에서 VM 아이콘이 템플릿 형태로 표시됨
- 템플릿 원본 VM이 일반 VM이 아니라 Template로 표시됨

## 4. 템플릿에서 VM 복제

운영용 VM은 `Full Clone`을 권장합니다.

테스트/임시 VM은 필요 시 `Linked Clone`도 가능하지만, 원본 템플릿 의존성이
있으므로 운영 기본값으로 사용하지 않습니다.

Web UI 경로:

1. 템플릿 선택
1. `Clone`
1. 새 VM ID 입력
1. 이름 입력
1. `Mode`에서 `Full Clone` 선택
1. 대상 스토리지 확인 후 생성

## 5. 클론 후 네트워크 및 hostname 설정

클론 생성 후에는 `Cloud-Init` 탭에서 네트워크를 DHCP로 맞춥니다.
이 환경의 UI에는 별도 `Hostname` 입력 항목이 없으므로, 먼저 VM 이름이
게스트 OS hostname으로 반영되는지 확인합니다.

Web UI 예시:

1. 클론한 VM 선택
1. `Cloud-Init`
1. `IP Config (net0)`는 `DHCP` 유지
1. 필요 시 SSH 공개키만 입력
1. `Regenerate Image` 실행
1. VM 부팅 후 hostname과 `/etc/hosts` 반영 상태 확인

운영 메모:

- MAC 주소는 클론 생성 시 Proxmox가 보통 자동으로 새 값으로 할당합니다.
- 기존 로그인 계정을 계속 사용할 계획이면 `ciuser`는 별도로 지정하지 않습니다.
- VM 이름이 `vm-test`라면 첫 부팅 후 `hostname`, `/etc/hosts`에 같은 값이 반영되는지 확인합니다.
- IP는 DHCP에서 할당받도록 유지합니다.
- 첫 부팅 전에 `Regenerate Image`를 적용해야 최신 `Cloud-Init` 설정이 반영됩니다.

## 참고

- Proxmox 설치 본문: [Proxmox Installation](./installation.md)
