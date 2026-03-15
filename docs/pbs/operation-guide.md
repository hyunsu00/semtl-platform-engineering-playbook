# Proxmox Backup Server Operation Guide

## 개요

이 문서는 설치가 완료된 `Proxmox Backup Server (PBS)`를 Proxmox VE에
연결하고, 백업 작업을 생성하며, 자주 만나는 문제를 점검하는 절차를 정리합니다.

기본 설치와 초기 계정/DNS 설정은 [PBS 설치 가이드](./installation.md)를
먼저 완료한 뒤 진행합니다.

## 1) Proxmox VE에 PBS 연결

Proxmox Web UI에서 PBS를 Storage로 등록합니다.

1. `Datacenter` -> `Storage` -> `Add` -> `Proxmox Backup Server`
1. 서버/Datastore/계정 입력
1. 등록 후 상태 확인

예시 입력값:

- `ID`: `pbs`
- `Server`: `pbs.internal.semtl.synology.me`
- `Datastore`: 사전에 생성한 PBS Datastore 이름
- `Username`: `root@pam`
- `Password`: PBS `root` 비밀번호

## 2) 백업 작업 생성 및 검증

1. `Datacenter` -> `Backup` -> `Add`
1. 백업 대상 VM/CT 선택
1. 스케줄 설정 후 저장
1. 수동 백업 1회 실행

검증 체크리스트:

- PBS UI 접속 가능 (`https://pbs.internal.semtl.synology.me:8007`)
- `hostname` 결과가 `vm-pbs`
- `hostname -f` 결과가 `pbs.internal.semtl.synology.me`
- `nslookup pbs.internal.semtl.synology.me` 결과가 `192.168.0.253`
- `nslookup google.com` 정상 응답
- Datastore 상태 정상
- Proxmox에서 PBS Storage 접근 가능
- 테스트 백업 성공 및 복구 가능

## 트러블슈팅

### 내부 DNS가 안 풀리거나 외부 조회가 느림

- 확인: PBS의 DNS가 `192.168.0.2`를 우선 참조하는지 확인
- 확인: Synology `DNS Server > 해상도`에서 전달자가 `8.8.8.8`,
  `1.1.1.1`로 설정되었는지 확인
- 확인: 공유기 DHCP가 Synology DNS를 배포하는지 확인
- 조치: Synology 전달자에 공유기 IP(`192.168.0.1`)를 넣지 않음

### PBS 설치 후 DNS를 잘못 입력함

- 증상: `pbs.internal.semtl.synology.me` 조회 실패, GUI 접속은 IP로만 가능
- 원인: 설치 중 `DNS Server`를 공유기로 입력
- 조치: `/etc/network/interfaces`와 `/etc/resolv.conf`를 점검하여
  `192.168.0.2`로 보정 후 재검증

### FQDN/hostname 불일치

- 확인: `hostname`, `hostname -f`, `/etc/hosts`
- 조치: `hostnamectl set-hostname vm-pbs`
- 조치: `/etc/hosts`에
  `192.168.0.253 pbs.internal.semtl.synology.me vm-pbs` 반영

### PBS ACL 명령 옵션 오류

- 증상: `parameter verification failed - 'userid'`
- 원인: `proxmox-backup-manager acl update`에 `--userid` 사용
- 조치: `--auth-id`로 변경

```bash
proxmox-backup-manager acl update / Admin --auth-id admin@pbs
```

### PBS UI 접속 실패 (`:8007`)

- 확인: 브라우저 주소가 `https://`인지 확인
- 확인: PBS IP/Gateway/DNS
- 확인: `systemctl status proxmox-backup-proxy`
- 확인: `ss -tulpen | grep ':8007'`
- 조치: 네트워크 경로 및 방화벽 정책 수정

### Proxmox에서 PBS 인증 실패

- 확인: `root@pam` 계정/비밀번호
- 확인: PBS 시간 동기화 상태
- 조치: 계정 정보 재입력 또는 API Token 방식으로 전환

## 참고

- [PBS 설치 가이드](./installation.md)
- [시놀로지 설치 가이드](../synology/installation.md)
- [Proxmox 운영 가이드](../proxmox/operation-guide.md)
