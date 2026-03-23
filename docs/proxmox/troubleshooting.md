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

## 에스컬레이션 기준

- 15분 이상 서비스 영향 지속
- 데이터 손실 가능성 존재

## 참고

- DNS/hostname 상세 기준: `./dns-and-hostname-guide.md`
