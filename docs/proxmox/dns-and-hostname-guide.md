# Proxmox DNS And Hostname Guide

## 개요

이 문서는 `Proxmox VE`, `PBS`, Ubuntu 기반 VM에서 DNS와 hostname을
일관되게 운영하기 위한 표준을 정리합니다.

이 저장소 기준 기본 전제는 아래와 같습니다.

- Gateway: `192.168.0.1`
- 내부 DNS: `192.168.0.2` (Synology `DNS Server`, Master Zone)
- 내부 도메인: `semtl.synology.me`
- Proxmox Host: `192.168.0.254`

## DNS 토폴로지 기준

권장 DNS 흐름:

```text
VM / Host
  -> Synology DNS (192.168.0.2)
  -> Forwarders (1.1.1.1 / 8.8.8.8)
  -> Public DNS
```

Synology `DNS Server` 확인 항목:

- `Master Zone`: `semtl.synology.me`
- `Forwarders`: `1.1.1.1`, `8.8.8.8`
- Proxmox/서비스 FQDN A 레코드 등록

예시:

- `proxmox.internal.semtl.synology.me -> 192.168.0.254`
- `minio.internal.semtl.synology.me -> 192.168.0.x`
- `pbs.semtl.synology.me -> 192.168.0.253`

## Proxmox Host 표준

`Proxmox VE`와 `PBS`처럼 인프라 노드 역할을 하는 서버는
짧은 hostname과 FQDN을 분리해 운영하는 것을 우선 권장합니다.

예시:

- short hostname: `proxmox`
- FQDN: `proxmox.internal.semtl.synology.me`

권장 정합성:

- `hostname` -> `proxmox`
- `hostname -f` -> `proxmox.internal.semtl.synology.me`
- `/etc/hosts` -> `192.168.0.254 proxmox.internal.semtl.synology.me proxmox`

예시:

```text
127.0.0.1 localhost.localdomain localhost
192.168.0.254 proxmox.internal.semtl.synology.me proxmox
```

검증 명령:

```bash
hostname
hostname -f
getent hosts proxmox.internal.semtl.synology.me
nslookup proxmox.internal.semtl.synology.me
```

주의:

- `hostname`에 FQDN 전체가 직접 들어가도 동작할 수는 있지만,
  `Proxmox VE`에서는 short hostname + FQDN 분리 구성이 더 예측 가능합니다.
- `/etc/hosts`는 반드시 loopback이 아닌 관리 IP를 가리켜야 합니다.

## DHCP Ubuntu VM 표준

`MinIO`, `Jenkins`, `Keycloak`처럼 Ubuntu 기반 DHCP VM은
`127.0.1.1` 매핑을 유지해도 됩니다.

예시:

```text
127.0.0.1 localhost
127.0.1.1 minio.internal.semtl.synology.me vm-minio
```

이 구성의 의미:

- `/etc/hosts`는 VM 내부 hostname 해석용
- 실제 서비스 접근은 Synology DNS가 반환하는 실제 IP 사용

정상 예시:

- `hostname` -> `vm-minio`
- `hostname -f` -> `minio.internal.semtl.synology.me`
- `getent hosts minio.internal.semtl.synology.me` -> `127.0.1.1 ...`
- MinIO VM 자신에서 `nslookup minio.internal.semtl.synology.me` -> `127.0.0.1`
- 다른 PC에서 `nslookup minio.internal.semtl.synology.me` -> `192.168.0.x`

중요:

- `nslookup`은 `/etc/hosts`가 아니라 DNS 서버를 조회합니다.
- MinIO VM 자신에서 `127.0.0.1`을 반환하도록 구성했다면 이는 정상 동작입니다.
- 다른 PC 기준으로는 실제 VM IP가 반환되어야 정상입니다.

## Static IP 인프라 노드 표준

아래 노드는 DHCP보다 실제 IP를 `/etc/hosts`에 명시하는 편이 안전합니다.

- `Proxmox VE`
- `PBS`
- Kubernetes node
- DB/스토리지 cluster node

예시:

```text
192.168.0.253 pbs.semtl.synology.me pbs
192.168.0.171 harbor.semtl.synology.me vm-harbor
```

## DNS 설정 기준

기본 권장:

- Primary DNS: `192.168.0.2`
- Secondary DNS: `1.1.1.1`

`8.8.8.8`를 써도 동작에는 문제가 없습니다. 문서에서는 일관성을 위해
`1.1.1.1`을 기본 예시로 사용합니다.

`search` domain:

- `search semtl.synology.me`는 선택 사항입니다.
- 있으면 `ping minio`처럼 짧은 이름 사용이 편리합니다.
- 없어도 FQDN을 직접 쓰면 동작합니다.

`search home` 같은 값이 남아 있다고 해서 그 자체가 오류는 아닙니다.
문제가 있으면 실제 DNS 해석 결과를 기준으로 판단합니다.

## /etc/resolv.conf 운영 원칙

가장 중요한 원칙은 `한 서버에서 한 방식만 사용`하는 것입니다.

대표 패턴:

1. static file
2. `systemd-resolved` stub
3. `cloud-init` 또는 netplan 관리

판별 명령:

```bash
ls -l /etc/resolv.conf
resolvectl status
cat /etc/network/interfaces
ls /etc/netplan
```

운영 기준:

- Proxmox Host는 보통 `ifupdown` + `dns-nameservers` 기준으로 관리
- Ubuntu DHCP VM은 `systemd-resolved` 또는 netplan 기본 구조를 유지
- `static`, `stub`, `cloud-init` 방식을 섞지 않음

주의:

- DHCP VM에서 `/etc/resolv.conf`에 `chattr +i`를 무조건 적용하지 않습니다.
- 해당 파일을 고정할 경우 `cloud-init`, `systemd-resolved`, netplan과
  충돌할 수 있습니다.
- `immutable`은 운영자가 DNS를 정적으로 직접 관리하기로 확정한 서버에만
  제한적으로 사용합니다.

## DNS 장애 복구 절차

### 1) 소유자 확인

먼저 `/etc/resolv.conf`를 누가 관리하는지 확인합니다.

```bash
ls -l /etc/resolv.conf
resolvectl status
```

### 2) systemd-resolved 기반 VM 복구

`/etc/resolv.conf`가 stub symlink여야 하는 Ubuntu VM이라면:

```bash
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
sudo systemctl restart systemd-resolved
```

그 다음 netplan 또는 `resolved.conf`에 DNS uplink가 실제로 들어있는지
재확인합니다.

```bash
resolvectl status
```

### 3) static DNS 서버 복구

운영자가 정적으로 관리하는 서버라면 `/etc/resolv.conf`를 재작성합니다.

```text
nameserver 192.168.0.2
nameserver 1.1.1.1
```

단, 이 경우에도 netplan/cloud-init이 해당 파일을 덮어쓰지 않는지
먼저 확인해야 합니다.

### 4) Synology DNS 확인

```bash
nslookup proxmox.internal.semtl.synology.me 192.168.0.2
nslookup google.com 192.168.0.2
```

확인 포인트:

- 내부 FQDN이 실제 IP로 해석되는지
- 외부 도메인이 forwarder를 통해 조회되는지

### 5) 재부팅의 의미

`Proxmox VE` 재부팅 후 DNS가 살아나는 경우가 있습니다.

가능한 이유:

- bridge 재초기화
- routing/ARP cache 재초기화
- 일시적 네트워크 경로 복구

하지만 재부팅만으로 종료하지 말고,
`/etc/resolv.conf`, Synology forwarder, VM DNS 경로를 다시 확인해야 합니다.

## 확인 명령 세트

Proxmox Host:

```bash
hostname
hostname -f
cat /etc/resolv.conf
cat /etc/network/interfaces
cat /etc/hosts
nslookup proxmox.internal.semtl.synology.me
```

DHCP VM:

```bash
hostname
hostname -f
hostname -I
cat /etc/resolv.conf
cat /etc/hosts
getent hosts "$(hostname -f)"
nslookup "$(hostname -f)"
nslookup google.com
```

의도한 결과:

- `hostname`은 short hostname
- `hostname -f`는 FQDN
- `getent hosts`는 로컬 정책에 따라 `127.0.1.1` 또는 실제 IP
- `nslookup`은 항상 실제 DNS 서버 기준 결과

## 참고

- Proxmox Host 운영 절차: `./operation-guide.md`
- PBS 설치 시 DNS 기준: `../pbs/installation.md`
- DHCP MinIO VM 설치 예시: `../minio/installation.md`
