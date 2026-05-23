# VM Win11 Installation

## 개요

이 문서는 `Proxmox VE`에서 `vm-win11` Windows 11 VM을 생성하고,
VirtIO 드라이버, QEMU Guest Agent, 원격 접속 기준점까지 구성하는 절차를
정리합니다.

Windows 11 요구사항에 맞춰 `OVMF`, `Q35`, `TPM 2.0` 구성을 포함합니다.

목표:

- VM 이름: `vm-win11`
- 게스트 OS: `Windows 11`
- 운영 계정: `semtl`
- 접속 방식: Proxmox 콘솔, RDP
- 드라이버: VirtIO Storage, VirtIO Network, QEMU Guest Agent
- 기본 리소스: `vCPU 4`, `Memory 16384MiB`, `Disk 120GB`

## 사용 시점

- Windows 11 전용 작업 VM이 필요한 경우
- Proxmox에서 Windows 11 설치 기준을 표준화하려는 경우
- `vm-devtools`와 유사한 리소스 크기로 데스크톱 VM을 만들려는 경우
- 설치 직후 스냅샷을 남기고 이후 도구 설치를 분리하려는 경우

## 최종 성공 기준

- Proxmox에서 Windows 11 VM 생성 완료
- Windows 11 설치 중 VirtIO 디스크 드라이버 로드 완료
- VirtIO Network 드라이버 설치 후 네트워크 연결 가능
- QEMU Guest Agent 설치 및 Proxmox 연동 완료
- Proxmox Summary 화면에서 VM IP 확인 가능
- Windows 원격 데스크톱으로 접속 가능
- 기본 설치 직후 `BASELINE` 스냅샷 생성 완료

예시 운영값:

- hostname: `vm-win11`
- Proxmox VM 이름: `vm-win11`
- IP: `192.168.77.232`

## 사전 조건

- Proxmox VE 설치 및 관리 접속 가능 상태
- Proxmox 노드에 Windows 11 ISO 업로드 완료
- Proxmox 노드에 VirtIO Windows 드라이버 ISO 업로드 완료
- `vmbr0` 등 VM 연결용 브리지 준비 완료
- VM용 스토리지 확보
- Windows 11 라이선스 또는 정품 인증 계획 준비

ISO 예시:

- Windows 11 ISO: `Win11_*.iso`
- VirtIO ISO: `virtio-win.iso`

운영 메모:

- Windows 11 설치 화면에서는 VirtIO 디스크가 기본으로 보이지 않을 수 있습니다.
  설치 중 VirtIO ISO에서 Storage 드라이버를 직접 로드합니다.
- 설치 초기에는 네트워크가 잡히지 않을 수 있으므로, VirtIO ISO를 CD/DVD로
  함께 연결해 둡니다.
- Windows 계정과 제품 키는 문서에 기록하지 않습니다.

## 1. VM 생성

Proxmox Web UI에서 `Create VM`으로 `vm-win11` VM을 생성합니다.

권장 기준:

- Name: `vm-win11`
- OS: `Microsoft Windows`
- Version: `11/2022`
- BIOS: `OVMF (UEFI)`
- Machine Type: `Q35`
- EFI Disk: 추가
- TPM State: 추가
- TPM Version: `v2.0`
- SCSI Controller: `VirtIO SCSI single`
- Display: `Default`
- Disk: `120GB`
- Disk Bus: `SCSI`
- Cache: `Default` 또는 `Write back`
- Discard: 체크
- Network Bridge: `vmbr0`
- Network Model: `VirtIO`
- Agent: `Enabled`
- Auto Start: `No`

권장 리소스:

- vCPU: `4`
- Memory: `16384MiB`
- Minimum memory: `12288MiB`
- Ballooning Device: 체크
- KSM 허용: 체크
- Disk: `120GB`

운영 메모:

- Windows 11은 `TPM 2.0` 요구사항이 있으므로 TPM State를 VM에 추가합니다.
- `Memory 16384MiB`, `Minimum memory 12288MiB` 구성은 데스크톱 사용과
  업데이트 작업에 여유가 있습니다.
- 디스크는 Windows 업데이트, 개발 도구, 임시 파일을 고려해 `120GB`로
  시작합니다.
- 네트워크는 먼저 `DHCP`로 검증한 뒤 필요 시 DHCP 예약이나 고정 IP로
  전환합니다.

## 2. 설치 ISO 연결 확인

설치 전 VM의 `Hardware` 탭에서 ISO가 2개 연결되어 있는지 확인합니다.

- `CD/DVD Drive 1`: Windows 11 ISO
- `CD/DVD Drive 2`: VirtIO Windows 드라이버 ISO

VirtIO ISO가 빠져 있으면 `Add -> CD/DVD Drive`로 추가합니다.

운영 메모:

- Windows 설치 중 디스크 드라이버와 네트워크 드라이버가 필요할 수 있으므로
  VirtIO ISO는 설치가 끝날 때까지 유지합니다.
- 설치 후에도 QEMU Guest Agent 설치를 위해 한 번 더 사용합니다.

## 3. Windows 11 설치

VM을 시작하고 Proxmox 콘솔에서 Windows 11 설치를 진행합니다.

설치 기준:

- Language: 필요한 언어 선택
- Edition: 라이선스에 맞는 Windows 11 Edition 선택
- Installation type: `Custom`
- 설치 대상 디스크: VirtIO 드라이버 로드 후 표시되는 `120GB` 디스크

### 3-1. VirtIO Storage 드라이버 로드

설치 대상 디스크가 보이지 않으면 아래 순서로 드라이버를 로드합니다.

1. `Load driver` 선택
1. VirtIO ISO 선택
1. `vioscsi` 드라이버 경로 선택
1. Windows 11 amd64 드라이버 선택
1. 디스크가 보이면 설치 대상 디스크로 선택

대표 경로:

```text
vioscsi\w11\amd64
```

운영 메모:

- VM 디스크 버스를 `SCSI`로 만들었기 때문에 `vioscsi` 드라이버를 사용합니다.
- `VirtIO Block`으로 만들었다면 `viostor` 계열 드라이버를 사용합니다.
- 드라이버 로드 후 `120GB` 디스크가 보이면 파티션은 Windows 설치 프로그램에
  맡깁니다.

### 3-2. 초기 계정과 hostname 설정

Windows 초기 설정 화면에서 운영 계정과 장치 이름을 구성합니다.

권장 기준:

- Device name: `vm-win11`
- Local account: `semtl`
- Password: `<WINDOWS_PASSWORD>`

운영 메모:

- 실제 계정 비밀번호는 문서에 기록하지 않고 비밀번호 관리자에 보관합니다.
- Microsoft 계정 연동이 필요 없으면 로컬 계정 기준으로 구성합니다.
- 조직 정책상 Microsoft 계정이 필요하면 계정 방식만 별도로 맞춥니다.

## 4. VirtIO 드라이버 설치

Windows 설치가 끝나면 VirtIO ISO 안의 설치 프로그램으로 기본 드라이버를
설치합니다.

실행 파일:

```text
virtio-win-guest-tools.exe
```

설치 대상:

- VirtIO Network
- VirtIO Balloon
- VirtIO Serial
- QXL Display
- QEMU Guest Agent
- 기타 기본 VirtIO 장치 드라이버

설치 후 Windows를 재부팅합니다.

검증:

1. `Device Manager` 실행
1. 알 수 없는 장치가 남아 있는지 확인
1. 네트워크 어댑터가 정상 인식됐는지 확인
1. Proxmox Summary 화면에서 IP가 표시되는지 확인

운영 메모:

- `virtio-win-guest-tools.exe`가 없거나 설치가 누락되면 ISO 안에서 필요한
  드라이버를 수동 설치합니다.
- Proxmox에서 IP가 보이지 않으면 QEMU Guest Agent 설치 여부와 VM Options의
  `QEMU Guest Agent` 활성화 여부를 함께 확인합니다.

## 5. Proxmox 콘솔 해상도 설정

Windows 설치 직후 Proxmox 콘솔에서 해상도 변경이 제한될 수 있습니다.
이 경우 VM의 가상 디스플레이 장치와 Windows 디스플레이 드라이버를 함께
확인합니다.

권장 기준:

- VM Display: `SPICE`
- Windows Display driver: `QXL Display`
- 일반 운영 접속: RDP

### 5-1. VM Display를 SPICE로 변경

VM을 종료한 뒤 Proxmox Web UI에서 Display 장치를 변경합니다.

1. `vm-win11` VM 선택
1. `Hardware`
1. `Display`
1. `Edit`
1. Graphic card를 `SPICE`로 변경
1. VM 시작

운영 메모:

- `Default` 디스플레이로도 설치는 가능하지만, Windows 콘솔 해상도 조정은
  제한될 수 있습니다.
- SPICE를 사용하면 Windows에서 QXL 디스플레이 드라이버를 사용할 수 있습니다.
- 실제 운영은 Proxmox 콘솔보다 RDP 접속을 기준으로 합니다.

### 5-2. QXL Display 드라이버 확인

`virtio-win-guest-tools.exe` 설치 후 `Device Manager`에서 디스플레이 어댑터를
확인합니다.

기대 결과:

```text
Red Hat QXL controller
```

수동 설치가 필요하면 VirtIO ISO에서 아래 경로를 사용합니다.

```text
qxldod\w11\amd64
```

운영 메모:

- `Microsoft Basic Display Adapter`로 남아 있으면 해상도 선택지가 제한될 수
  있습니다.
- 드라이버 설치 후 Windows를 재부팅하고 해상도 변경 메뉴를 다시 확인합니다.
- SPICE 콘솔을 로컬 PC에서 직접 열려면 SPICE 클라이언트가 필요합니다.

### 5-3. RDP 기준 해상도

RDP 접속은 Proxmox 콘솔의 가상 그래픽 드라이버와 별도로 동작합니다.
Windows 설치와 드라이버 설치가 끝난 뒤 RDP를 활성화하면, 관리 PC의 RDP
클라이언트에서 원하는 해상도로 접속할 수 있습니다.

운영 메모:

- Windows 작업은 가능하면 RDP 기준으로 진행합니다.
- Proxmox 콘솔은 설치, 장애 대응, 네트워크 복구용으로 사용합니다.

## 6. Windows 기본 설정

설치 직후 아래 항목을 먼저 정리합니다.

### 6-1. Windows Update

`Settings -> Windows Update`에서 업데이트를 설치하고 재부팅합니다.

권장 기준:

- 누적 업데이트 설치 완료
- 드라이버 업데이트 확인
- 재부팅 후 추가 업데이트가 없는지 재확인

### 6-2. 시간과 표준 시간대 확인

`Settings -> Time & language -> Date & time`에서 시간을 확인합니다.

권장 기준:

- Set time automatically: `On`
- Set time zone automatically: 필요 시 `Off`
- Time zone: 운영 위치에 맞게 설정

PowerShell 확인:

```powershell
Get-TimeZone
Get-Date
```

### 6-3. 컴퓨터 이름 확인

PowerShell에서 hostname을 확인합니다.

```powershell
hostname
```

기대 결과:

```text
vm-win11
```

필요 시 이름을 변경하고 재부팅합니다.

```powershell
Rename-Computer -NewName "vm-win11" -Restart
```

## 7. RDP 접속 활성화

Windows 11 Pro 이상에서 원격 데스크톱을 활성화합니다.

GUI 경로:

1. `Settings`
1. `System`
1. `Remote Desktop`
1. `Remote Desktop` 활성화

방화벽 확인:

```powershell
Get-NetFirewallRule -DisplayGroup "Remote Desktop" |
  Select-Object DisplayName, Enabled, Direction, Action
```

관리 PC에서 접속을 확인합니다.

```text
mstsc /v:192.168.77.232
```

운영 메모:

- Windows 11 Home은 RDP 서버 기능을 제공하지 않으므로 Pro 이상을 권장합니다.
- RDP 접속 계정은 `semtl` 로컬 계정 또는 운영 정책에 맞는 계정을 사용합니다.
- 외부 인터넷에 RDP를 직접 노출하지 않습니다.

## 8. 기본 설치 직후 스냅샷

Windows Update, VirtIO 드라이버, QEMU Guest Agent, RDP 확인이 끝나면
기본 기준점 스냅샷을 생성합니다.

### 8-1. 임시 파일 정리

Windows에서 디스크 정리를 실행합니다.

권장 정리 항목:

- Temporary files
- Windows Update cleanup
- Delivery Optimization files
- Recycle Bin

PowerShell 예시:

```powershell
Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
```

### 8-2. Proxmox 스냅샷 생성

1. `vm-win11` VM 선택
1. `Snapshots`
1. `Take Snapshot`
1. 스냅샷 이름과 설명 입력 후 생성

- 권장 이름: `BASELINE`

권장 설명:

```text
- Windows 11 기본 설치 완료
- hostname: vm-win11
- VirtIO 드라이버 설치 완료
- QEMU Guest Agent 설치 및 Proxmox IP 표시 확인
- Windows Update 적용
- RDP 접속 확인
```

## 9. 운영 체크리스트

정기적으로 아래 항목을 확인합니다.

- Windows Update가 정상 적용되는지 확인
- Proxmox Summary 화면에서 IP가 표시되는지 확인
- QEMU Guest Agent 서비스가 실행 중인지 확인
- RDP 접속 계정과 비밀번호 정책 확인
- 디스크 여유 공간 확인
- 주요 도구 설치 전후로 스냅샷 생성

QEMU Guest Agent 서비스 확인:

```powershell
Get-Service QEMU-GA
```

디스크 확인:

```powershell
Get-PSDrive C
```

## 10. 트러블슈팅

### 설치 디스크가 보이지 않음

확인할 항목:

- VM 디스크 버스가 `SCSI`인지 확인
- VirtIO ISO가 CD/DVD로 연결되어 있는지 확인
- `vioscsi\w11\amd64` 드라이버를 로드했는지 확인

### 네트워크가 잡히지 않음

확인할 항목:

- VM Network Model이 `VirtIO`인지 확인
- VirtIO Network 드라이버가 설치됐는지 확인
- Proxmox 브리지가 `vmbr0` 등 올바른 네트워크에 연결됐는지 확인
- DHCP 서버에서 IP를 할당했는지 확인

### Proxmox에 IP가 표시되지 않음

확인할 항목:

- VM Options에서 `QEMU Guest Agent`가 `Enabled`인지 확인
- Windows에서 `QEMU Guest Agent`가 설치됐는지 확인
- `QEMU-GA` 서비스가 실행 중인지 확인
- VM을 완전히 종료한 뒤 다시 시작했는지 확인

### RDP 접속이 되지 않음

확인할 항목:

- Windows Edition이 Pro 이상인지 확인
- Remote Desktop이 활성화됐는지 확인
- Windows 방화벽의 Remote Desktop 규칙이 활성화됐는지 확인
- 관리 PC에서 `192.168.77.232:3389`로 접근 가능한지 확인
- 계정 비밀번호가 비어 있지 않은지 확인

### 해상도 변경이 제한됨

확인할 항목:

- VM Display가 `SPICE`인지 확인
- Windows 디스플레이 어댑터가 `Red Hat QXL controller`인지 확인
- `Microsoft Basic Display Adapter`로 남아 있으면 QXL 드라이버 수동 설치
- RDP 접속 시에는 RDP 클라이언트의 해상도 설정을 확인
