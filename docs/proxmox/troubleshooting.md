# Proxmox Troubleshooting

## 개요

Proxmox 주요 장애 사례와 해결 절차를 정리합니다.

## 공통 점검 절차

1. 서비스 상태 확인
2. 최근 변경 사항 확인
3. 로그 수집 및 원인 범위 축소

## 자주 발생하는 이슈

### 이슈 1: 서비스 시작 실패

- 증상: 프로세스가 재시작 반복
- 원인: 설정 오류 또는 포트 충돌
- 해결: 설정 검증 후 재시작

### 이슈 2: 접속 불가

- 증상: UI/API 타임아웃
- 원인: 네트워크/DNS/방화벽 설정 이슈
- 해결: 경로별 네트워크 확인 후 정책 수정

### 이슈 3: hostname/FQDN 변경 후 경고 또는 인증서 이상

- 증상: `hostname resolves to loopback`, `pveproxy` 인증서 경고,
  노드명이 기대와 다르게 표시됨
- 원인: short hostname, FQDN, `/etc/hosts`가 서로 불일치
- 확인:

  ```bash
  hostname
  hostname -f
  getent hosts "$(hostname -f)"
  cat /etc/hosts
  ```

- 조치:
  - `hostname`은 short hostname으로 정리
  - `/etc/hosts`는 관리 IP + FQDN + short hostname 순서 유지
  - 필요 시 `systemctl restart pveproxy pvedaemon`

### 이슈 4: Ubuntu VM에서 DNS가 갑자기 실패

- 증상: `Temporary failure in name resolution`,
  `/etc/resolv.conf` 누락 또는 `127.0.0.53`만 보임
- 원인:
  - `systemd-resolved` stub 구조 손상
  - netplan/cloud-init과 수동 DNS 수정 혼용
  - Proxmox 측 네트워크 변경 후 VM DNS 경로 재수립 실패
- 확인:

  ```bash
  ls -l /etc/resolv.conf
  resolvectl status
  cat /etc/hosts
  hostname -f
  ```

- 조치:
  - systemd-resolved 기반이면 symlink 복구 후 서비스 재시작
  - static DNS 기반이면 `/etc/resolv.conf`를 재작성
  - Synology DNS(`192.168.0.2`)와 forwarder 설정 재검증
  - DHCP VM에 `chattr +i /etc/resolv.conf`를 즉시 적용하지 않음

### 이슈 5: Proxmox 재부팅 후 VM DNS가 살아남

- 증상: Proxmox Host를 재부팅하니 VM의 DNS 조회가 다시 정상화됨
- 해석:
  - bridge/routing/ARP 상태가 재초기화되며 일시 장애가 해소된 경우
  - 근본 원인 확인 없이 넘어가면 재발 가능
- 후속 확인:

  ```bash
  cat /etc/network/interfaces
  cat /etc/resolv.conf
  nslookup proxmox.internal.semtl.synology.me 192.168.0.2
  nslookup google.com 192.168.0.2
  ```

### 이슈 6: Proxmox Host는 정상인데 Intel AMT만 죽음

- 증상:
  - Proxmox Web UI, SSH, VM은 정상
  - Intel AMT Web UI만 간헐적으로 접속 불가
  - 재부팅 후 일시 복구
- 원인:
  - C-State, PCIe ASPM, Intel ME firmware 계열 이슈 가능성이 높음
  - Proxmox Host 자기 자신에서 자기 AMT를 점검하면 오탐 가능
- 해결:
  - GRUB에서 `intel_idle.max_cstate=1 processor.max_cstate=1 pcie_aspm=off`
    적용
  - 외부 장비(Synology NAS)에서 AMT 포트 감시
  - DSM 로그 및 Telegram 알림 구성
- 상세 문서:
  - [Intel AMT Watchdog And Alerting](./amt-watchdog-and-alerting.md)

### 이슈 7: Proxmox Host의 `vmbr0` IP는 살아 있는데 같은 대역 통신이 모두 실패함

- 증상:
  - AMT 콘솔로는 Proxmox Host 접속 가능
  - `ip -br addr` 기준 `vmbr0`에 관리 IP가 정상 설정됨
  - `ethtool nic0` 기준 `Link detected: yes`
  - 그런데 `ping 192.168.0.1`, `ping 192.168.0.2` 같은 같은 대역 통신이 모두 실패
  - `ip neigh`에 `192.168.0.x dev vmbr0 FAILED`가 반복됨
- 가장 가능성 높은 원인:
  - Proxmox Host의 `vmbr0`/`nic0` ARP 또는 L2 상태가 일시적으로 꼬인 경우
  - 스위치 포트/VLAN/포트 보안 문제 가능성도 함께 고려
  - Longhorn, NFS StorageClass 설치 같은 Kubernetes 내부 작업이 직접 원인일 가능성은 낮음
  - 이유: 이번 증상은 Proxmox Host 자체가 같은 LAN에서 ARP 해석을 못 하는 상태였기 때문
- 확인:

  ```bash
  ip -br addr
  ip route
  ip -br link
  bridge link
  cat /etc/network/interfaces
  ethtool nic0
  ip neigh
  ping -c 2 192.168.0.1
  ping -c 2 192.168.0.2
  ```

- 판단 포인트:
  - `nic0`가 `UP`, `LOWER_UP`이고 `ethtool`에서 `Link detected: yes`면 물리 링크는 살아 있음
  - `vmbr0`에 관리 IP와 gateway가 정상인데 `ip neigh`가 `FAILED`면 L2/ARP 문제 가능성이 큼
  - `/etc/network/interfaces`에서 `bridge-ports nic0`가 정상이면
    Proxmox 설정 자체 문제 가능성은 낮아짐
- 즉시 조치:

  ```bash
  ifreload -a
  systemctl restart networking
  ip link set nic0 down
  ip link set nic0 up
  ip link set vmbr0 down
  ip link set vmbr0 up
  ip neigh flush all
  ping -c 2 192.168.0.1
  ping -c 2 192.168.0.2
  ip neigh
  ```

- 이번 사례 결과:
  - 위 조치 후 `192.168.0.1`, `192.168.0.2` ping이 즉시 복구됨
  - `ip neigh` 상태도 `FAILED`에서 `REACHABLE`로 전환됨
  - 따라서 근본 원인은 Kubernetes 스토리지 설치보다는 Proxmox Host 네트워크 상태 꼬임 쪽으로 판단
- 후속 점검:
  - 스위치 포트 VLAN/native VLAN 설정 확인
  - 포트 보안, MAC 제한, err-disabled 여부 확인
  - 재발 시 아래 로그를 함께 수집

  ```bash
  journalctl -b | grep -Ei "nic0|vmbr0|bridge|link|network"
  dmesg -T | grep -Ei "nic0|link|reset|timeout|bridge"
  ```

## 에스컬레이션 기준

- 15분 이상 서비스 영향 지속
- 데이터 손실 가능성 존재

## 참고

- DNS/hostname 상세 기준: `./dns-and-hostname-guide.md`
