# Synology Installation

## 개요

이 문서는 DSM 기반 Synology NAS에서 플랫폼 공통 기반으로 사용하는 내부
DNS, 공유기 DHCP DNS 배포, Proxmox Backup Server(PBS)용 NFS Export
준비 절차를 정리합니다.

이 문서를 먼저 완료한 뒤 PBS 설치는
[PBS 설치 가이드](../pbs/installation.md)로 이어갑니다.

## 아키텍처와 예시 값

- 내부 도메인: `semtl.synology.me`
- Synology DNS Server IP: `192.168.0.2`
- Gateway: `192.168.0.1`
- PBS FQDN: `pbs.semtl.synology.me`
- PBS IP: `192.168.0.253`
- PBS NFS Export: `192.168.0.2:/volume2/lab-data`

## 사전 조건

- DSM 관리자 권한
- `DNS Server` 패키지 설치 가능 상태
- 공유기 DHCP DNS 배포 설정 권한
- PBS용 NFS 공유 폴더 생성 권한

## 1) `DNS Server` 패키지 설치

1. DSM 로그인
1. `패키지 센터`에서 `DNS Server` 설치
1. 패키지가 DSM 방화벽 규칙 추가를 요청하면 DNS 관련 규칙 허용

## 2) 정방향 영역(Master Zone) 생성

예시:

- Zone: `semtl.synology.me`
- Master DNS Server: `192.168.0.2`

## 3) PBS A 레코드 생성

예시:

- Name: `pbs`
- FQDN: `pbs.semtl.synology.me`
- IP: `192.168.0.253`

## 4) 해상도(Resolution)와 전달자 설정

필수 설정:

- `해상도 서비스 활성화`
- `전달자 활성화`
- Forwarder 1: `8.8.8.8`
- Forwarder 2: `1.1.1.1`
- 전달 정책: `먼저 전달`

주의:

- Synology DNS의 전달자에 공유기 IP(`192.168.0.1`)를 넣지 않습니다.
- 공유기가 다시 Synology를 DNS로 광고하는 구조와 겹치면 DNS 질의가
  우회/반복되어 지연 또는 루프처럼 보이는 현상이 생길 수 있습니다.

## 5) 공유기 DHCP DNS 배포

공유기 DHCP에서 모든 VM이 Synology DNS를 자동으로 받도록 설정합니다.

ASUS 공유기 예시:

- Primary DNS: `192.168.0.2`
- Secondary DNS: `8.8.8.8`
- `Advertise router's IP in addition to user-specified DNS`: `No`

운영 메모:

- DHCP를 사용하는 새 VM은 재연결 또는 재부팅 후 DNS 설정을 자동 상속합니다.
- 고정 IP로 운영하는 PBS/기존 VM은 네트워크 설정 파일에서 직접 DNS를 맞춰야
  합니다.

## 6) PBS용 NFS Export 준비

1. DSM에서 PBS 백업용 공유 폴더를 준비합니다.
1. `제어판`에서 NFS 서비스를 활성화합니다.
1. 공유 폴더의 `NFS 권한`에서 PBS IP에 쓰기 가능한 Export를 추가합니다.

예시:

- 공유 폴더: `lab-data`
- Export 경로: `/volume2/lab-data`
- 허용 클라이언트: `192.168.0.253`
- 권한: `Read/Write`

확인 포인트:

- Squash/매핑 정책이 PBS 쓰기를 막지 않는지 확인
- DSM 방화벽 또는 네트워크 ACL이 NFS를 차단하지 않는지 확인

## 검증

DNS 검증:

```bash
nslookup pbs.semtl.synology.me 192.168.0.2
nslookup google.com 192.168.0.2
```

NFS Export 검증:

```bash
showmount -e 192.168.0.2
```

정상 기준:

- `pbs.semtl.synology.me`가 `192.168.0.253`으로 응답
- 외부 도메인 조회도 Synology DNS를 통해 정상 응답
- PBS IP가 NFS Export 허용 목록에 포함

## 참고

- [PBS 설치 가이드](../pbs/installation.md)
- [Proxmox DNS/Hostname 가이드](../proxmox/dns-and-hostname-guide.md)
