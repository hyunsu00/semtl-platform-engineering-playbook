# Proxmox Operation Guide

## 개요

Proxmox VE 운영 시 자주 수행하는 점검, 계정 조회, 변경 관리 절차를 정리합니다.

## 일일/주간 점검

- 리소스 사용량 확인: CPU/메모리/디스크
- 클러스터/노드 상태 확인: `Datacenter > Summary`, `Node > Summary`
- 백업 성공 여부 확인: `Datacenter > Backup`, PBS 작업 이력

## 계정/권한 운영

### 계정 리스트 확인 방법

Gemini 공유 문서(`Proxmox 계정 리스트 확인 방법`) 기준으로, 현재 계정 확인은
아래 3가지 방법으로 운영합니다.

1. CLI(`pveum`)로 조회 (권장)
1. Web UI에서 조회
1. API(`pvesh`/REST)로 조회

### 1) CLI 조회 (권장)

쉘(CLI) 환경에서는 `pveum`이 가장 빠르고 정확합니다.

```bash
pveum user list
```

추가 점검 명령:

```bash
pveum group list
pveum acl list
pveum realm list
```

운영 확인 포인트:

- `userid` (`<user>@<realm>`) 형식 확인
- 사용자 활성화 여부(`enable`) 확인
- 사용자 실명/이메일 등 메타데이터 누락 여부 확인

### 2) Web UI 조회

1. Proxmox Web UI 로그인
1. `Datacenter` -> `Permissions` -> `Users`
1. 사용자 ID, Realm, Enabled 상태 확인

권한 매핑 점검:

1. `Datacenter` -> `Permissions` -> `ACL`
1. 사용자/그룹별 Role 부여 범위 확인

### 3) API 조회

루트 권한 쉘에서는 `pvesh`로 동일 정보를 조회할 수 있습니다.

```bash
pvesh get /access/users
```

REST API 직접 호출 예시:

```bash
curl -k -b "PVEAuthCookie=<ticket>" \
  "https://<PVE-IP>:8006/api2/json/access/users"
```

참고:

- `root@pam`은 Linux PAM Realm 계정입니다.
- 계정 정의를 직접 볼 때 `/etc/pve/user.cfg`에는 일부 기본 계정 정보가
  기대한 형태로 모두 보이지 않을 수 있으므로, 운영 점검은 `pveum user list`
  기준으로 맞춥니다.

### SSH 접속 정책 확인

이 저장소의 기본 운영 원칙은 SSH를 `semtl` 계정으로만 허용하고,
`root` SSH 접속은 차단하는 것입니다.

1. `PermitRootLogin` 설정 확인
1. `AllowUsers` 설정 확인
1. SSH 데몬/포트 상태 확인
1. `semtl`/`root` 실제 접속 테스트

설정 확인:

```bash
grep -RinE "PermitRootLogin|AllowUsers" /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null
```

결과 해석:

- `PermitRootLogin no`: root SSH 차단
- `AllowUsers semtl`: `semtl`만 SSH 허용

서비스 상태 확인:

```bash
systemctl status ssh
ss -tulpen | rg ':22'
```

실제 접속 테스트:

```bash
ssh semtl@<PVE-IP>
ssh root@<PVE-IP>
```

운영 원칙:

- SSH 로그인 계정은 `semtl`만 사용
- `root`는 로컬 콘솔 또는 `sudo` 승격으로만 사용
- `PermitRootLogin no`는 SSH에만 적용되며 Web UI의 `root@pam` 로그인과는 별개
- Web UI의 `root@pam`은 초기 운영 및 장애 대응을 위한 비상 관리자 계정으로 유지
- 비밀번호 로그인보다 SSH 키 기반 접속을 우선
- 설정 변경 후 `systemctl restart ssh`로 반영하고 재접속으로 검증

### root 로컬 쉘 로그인 가능 여부 확인

Proxmox 쉘에서 `root` 계정 상태를 확인할 때는 잠금 여부, 비밀번호 상태,
로그인 쉘을 함께 확인합니다.

```bash
passwd -S root
getent passwd root
grep '^root:' /etc/shadow
```

확인 포인트:

- `passwd -S root` 결과가 `P`면 비밀번호 설정 상태
- `L`이면 계정 잠금 상태, `NP`면 비밀번호 미설정 상태
- `/etc/passwd`의 쉘이 `/bin/bash` 또는 `/bin/sh`인지 확인
- `/etc/shadow`에서 `!` 또는 `*`가 앞에 붙으면 잠금 상태 여부 재확인

필요 시 조치:

```bash
passwd root
usermod -U root
```

## DNS/hostname 운영 기준

이 저장소의 기본 DNS 토폴로지는 아래 기준으로 운영합니다.

- Gateway: `192.168.0.1`
- 내부 DNS: `192.168.0.2` (Synology `DNS Server`)
- 내부 도메인: `semtl.synology.me`

핵심 원칙:

- `Proxmox VE`/`PBS` 같은 인프라 노드는 short hostname을 우선 사용
- FQDN은 DNS와 `/etc/hosts`에서 실제 관리 IP로 매핑
- Ubuntu DHCP VM은 `/etc/hosts`의 `127.0.1.1` 패턴을 허용

Proxmox Host 예시:

```text
/etc/hosts
127.0.0.1 localhost.localdomain localhost
192.168.0.254 proxmox.semtl.synology.me proxmox
```

정상 예시:

- `hostname` -> `proxmox`
- `hostname -f` -> `proxmox.semtl.synology.me`
- `nslookup proxmox.semtl.synology.me` -> `192.168.0.254`

운영 메모:

- `search semtl.synology.me`는 편의 기능으로 선택 사항
- `search home` 같은 값이 남아 있어도 실제 해석이 정상이면 즉시 장애로
  보지 않음
- DHCP VM에서 `nslookup`은 실제 DNS 결과를, `getent hosts`는 로컬
  `/etc/hosts` 결과를 우선 보여줄 수 있음

상세 기준:

- [Proxmox DNS And Hostname Guide](./dns-and-hostname-guide.md)

## 구성 변경 운영 표준

- 계정 생성/비활성/삭제는 변경 티켓 기준으로 수행
- `root@pam` 직접 사용은 최소화하고 역할 기반 계정 우선
- 변경 후 `pveum user list`, `pveum acl list`로 즉시 검증
- 외부 인증(LDAP/OIDC) 연동 시 Realm 매핑 규칙 문서화

## 백업 및 복구

- 로컬 설정 백업은 [Proxmox 로컬 설정 백업 및 복구](./config-backup-and-restore.md)
  문서를 기준으로 수행
- VM/CT 디스크 백업은 `vzdump` 또는 PBS 기준으로 분리 운영
- 백업 주기: 운영 정책(일일/주간) 기준
- 복구 검증: 월 1회 이상 샘플 복구 테스트

## 장애 대응

1. 증상 확인
2. 로그/메트릭 확인
3. 임시 조치 및 근본 원인 분석

## 참고

- Gemini 공유: `https://gemini.google.com/share/18f4c833b686`
- Proxmox User Manager(`pveum`):
  `https://pve.proxmox.com/pve-docs/pveum.1.html`
- Proxmox API 문서:
  `https://pve.proxmox.com/mediawiki/index.php?title=Proxmox_VE_API`
