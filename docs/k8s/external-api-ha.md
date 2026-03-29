# Kubernetes External API HA

## 개요

이 문서는 `vm-admin` 같은 외부 운영 노드에서 Kubernetes API를 고가용성으로
접근하기 위한 외부 API Endpoint HA 구성을 정리합니다.

`ct-lb1`, `ct-lb2` 자체는 `HAProxy + Keepalived` 기반 범용 LB 노드로도 활용할 수 있습니다.
다만 이 문서는 그중 Kubernetes API 전용 구성을 기준으로 정리합니다.

이 저장소 기준 외부 API HA는 아래 구조를 사용합니다.

```text
VM-ADMIN (192.168.0.41)
        |
        v
K8s API VIP (192.168.0.180:6443)
        |
   +----+----+
   |         |
CT-LB1    CT-LB2
192.168.0.161
192.168.0.162
(HAProxy + Keepalived)
        |
        v
CP1 192.168.0.181:6443
CP2 192.168.0.182:6443
CP3 192.168.0.183:6443
```

구성 원칙:

- `kube-vip`는 control-plane 내부 API HA용입니다.
- `CT-LB1/CT-LB2 + Keepalived + HAProxy`는 외부 운영 접속용입니다.
- `vm-admin`의 kubeconfig는 최종적으로 `192.168.0.180:6443`를 사용해야 합니다.
- 외부망 VIP `192.168.0.180`은 apiserver `certSANs`에 포함되어 있어야 합니다.

## 1. CT 권장 리소스

- OS: `Ubuntu 22.04`
- vCPU: `1`
- RAM: `512MB`
- Disk: `8GB`
- NIC: 외부망 `192.168.0.x`

예시:

- `ct-lb1`: `192.168.0.161`
- `ct-lb2`: `192.168.0.162`
- API VIP: `192.168.0.180`

## 2. Proxmox CT 생성

Proxmox에서 Ubuntu 22.04 LXC 템플릿을 준비한 뒤 CT 2개를 생성해야 합니다.

예시:

- `ct-lb1`
  - CT ID: `121`
  - Hostname: `ct-lb1`
  - IP: `192.168.0.161/24`
  - Gateway: 외부망 기본 게이트웨이
- `ct-lb2`
  - CT ID: `122`
  - Hostname: `ct-lb2`
  - IP: `192.168.0.162/24`
  - Gateway: 외부망 기본 게이트웨이

권장 옵션:

- Unprivileged CT 사용
- `nesting=1` 불필요
- 방화벽 사용 시 `6443`, VRRP, 관리 SSH 경로 확인
- 두 CT 모두 같은 브리지(`vmbr0`)에 연결

생성 후 공통 확인:

```bash
hostnamectl
ip -br a
ip route
ping -c 2 192.168.0.181
ping -c 2 192.168.0.182
ping -c 2 192.168.0.183
```

## 3. CT 공통 초기 설정

Proxmox CT는 기본 상태에서 `root` SSH 접근이 제한될 수 있습니다.
따라서 콘솔로 먼저 접속한 뒤 운영 계정 `semtl`을 만들고 `sudo` 권한을 부여해야 합니다.

운영 계정 생성:

```bash
apt update
apt install -y sudo openssh-server
adduser semtl
usermod -aG sudo semtl
id semtl
```

운영 기준:

- 이후 SSH 접속과 운영 명령은 `semtl` 계정 기준으로 진행해야 합니다.
- `root` 직접 SSH 접속을 열기보다 `semtl` + `sudo` 조합으로 운영해야 합니다.

이름 기준 예시:

- Proxmox UI 표시명: `ct-lb1`, `ct-lb2`
- CT 내부 FQDN: `lb1.internal.semtl.synology.me`, `lb2.internal.semtl.synology.me`

즉 Proxmox UI에서는 CT 역할이 보이도록 관리하고,
CT 내부에서는 실제 내부 DNS/FQDN 체계에 맞는 이름을 사용하는 방식을 권장합니다.

필요 시 SSH 서비스 확인:

```bash
systemctl enable --now ssh
systemctl status ssh --no-pager
```

접속 확인 예시:

```bash
ssh semtl@192.168.0.161
ssh semtl@192.168.0.162
sudo whoami
```

필요 시 hostname/FQDN 보정:

```bash
sudo hostnamectl set-hostname ct-lb1
sudo vi /etc/hosts
hostname
hostname -f
```

`hostname -f`는 `/etc/hosts`만으로 결정되지 않을 수 있으므로
`/etc/hostname`과 `/etc/hosts`를 함께 맞춰야 합니다.
예를 들어 `/etc/hosts`에는 아래처럼 FQDN과 short hostname을 함께 두는 편이 좋습니다.

```text
127.0.0.1 localhost
127.0.1.1 lb1.internal.semtl.synology.me ct-lb1
```

두 CT 모두 아래 패키지를 설치해야 합니다.

```bash
sudo apt update
sudo apt install -y haproxy keepalived curl netcat-openbsd
```

권장 추가 확인:

```bash
haproxy -v
keepalived --version
nc -vz 192.168.0.181 6443
nc -vz 192.168.0.182 6443
nc -vz 192.168.0.183 6443
```

정상 기준:

- 세 control-plane의 `6443` 포트가 두 CT에서 모두 열려 있어야 합니다.
- 이 단계에서 연결이 안 되면 HAProxy/Keepalived 설정 전 네트워크를 먼저 수정해야 합니다.

## 4. HAProxy 설정

두 CT 모두 `/etc/haproxy/haproxy.cfg`의 기존 `defaults` 블록 아래에
아래 내용을 복붙해서 추가해야 합니다.

```bash
sudo tee -a /etc/haproxy/haproxy.cfg >/dev/null <<'EOF'

frontend k8s_api
  bind *:6443
  mode tcp
  option tcplog
  default_backend k8s_api_back

backend k8s_api_back
  mode tcp
  option tcp-check
  balance roundrobin
  default-server inter 2s fall 2 rise 2
  server cp1 192.168.0.181:6443 check
  server cp2 192.168.0.182:6443 check
  server cp3 192.168.0.183:6443 check
EOF
```

적용:

```bash
sudo systemctl enable --now haproxy
sudo systemctl restart haproxy
sudo systemctl status haproxy --no-pager
```

백엔드 연결 확인:

```bash
nc -vz 192.168.0.181 6443
nc -vz 192.168.0.182 6443
nc -vz 192.168.0.183 6443
```

세 개 모두 `succeeded`가 나와야 정상입니다.

## 5. Keepalived 설정

`ct-lb1`는 `MASTER`, `ct-lb2`는 `BACKUP`으로 구성해야 합니다.

인터페이스 확인:

```bash
ip -br a
```

아래 예시에서는 `eth0`를 사용합니다. 실제 인터페이스 이름이 다르면 해당 이름으로 바꿔야 합니다.

헬스체크 스크립트는 두 CT에 동일하게 배치해야 합니다.

```bash
sudo tee /usr/local/bin/check_haproxy.sh >/dev/null <<'EOF'
#!/bin/sh
systemctl is-active --quiet haproxy
EOF
sudo chmod +x /usr/local/bin/check_haproxy.sh
```

`ct-lb1`에서는 아래 내용을 그대로 복붙해야 합니다.

```bash
sudo tee /etc/keepalived/keepalived.conf >/dev/null <<'EOF'
global_defs {
  script_user root
  enable_script_security
}

vrrp_script chk_haproxy {
  script "/usr/local/bin/check_haproxy.sh"
  interval 2
  fall 2
  rise 2
}

vrrp_instance VI_K8S_API {
  state MASTER
  interface eth0
  virtual_router_id 51
  priority 120
  advert_int 1
  unicast_src_ip 192.168.0.161
  unicast_peer {
    192.168.0.162
  }
  authentication {
    auth_type PASS
    auth_pass K8sVip51!
  }
  virtual_ipaddress {
    192.168.0.180/24
  }
  track_script {
    chk_haproxy
  }
}
EOF
```

`ct-lb2`에서는 아래 내용을 그대로 복붙해야 합니다.

```bash
sudo tee /etc/keepalived/keepalived.conf >/dev/null <<'EOF'
global_defs {
  script_user root
  enable_script_security
}

vrrp_script chk_haproxy {
  script "/usr/local/bin/check_haproxy.sh"
  interval 2
  fall 2
  rise 2
}

vrrp_instance VI_K8S_API {
  state BACKUP
  interface eth0
  virtual_router_id 51
  priority 110
  advert_int 1
  unicast_src_ip 192.168.0.162
  unicast_peer {
    192.168.0.161
  }
  authentication {
    auth_type PASS
    auth_pass K8sVip51!
  }
  virtual_ipaddress {
    192.168.0.180/24
  }
  track_script {
    chk_haproxy
  }
}
EOF
```

적용:

```bash
sudo systemctl enable --now keepalived
sudo systemctl restart keepalived
sudo systemctl status keepalived --no-pager
```

## 6. 외부 API VIP 확인

VIP는 두 CT 중 한 대에만 보여야 합니다.

```bash
ip a | grep 192.168.0.180
```

`vm-admin`에서 VIP 포트 확인:

```bash
nc -vz 192.168.0.180 6443
```

정상 기준:

- `192.168.0.180` VIP가 `ct-lb1` 또는 `ct-lb2` 한 대에만 바인딩됨
- `nc -vz 192.168.0.180 6443` 연결 성공

## 7. `vm-admin` kubeconfig 전환

외부 운영 접속은 VIP 기준으로 통일해야 합니다.

```bash
cp ~/.kube/config ~/.kube/config.bak
sed -i \
  's#server: https://.*:6443#server: https://192.168.0.180:6443#g' \
  ~/.kube/config
grep server ~/.kube/config
kubectl get nodes -o wide
```

`x509` 오류가 발생하면 apiserver 인증서 SAN에 `192.168.0.180`이 포함되어 있는지 확인해야 합니다.
상세 절차는
[Kubernetes Installation](./installation.md)의
`apiserver SAN 변경 반영` 섹션을 따라야 합니다.

## 8. 장애 시 기대 동작

- `ct-lb1` 장애:
  VIP가 `ct-lb2`로 이동해야 합니다.
- `cp1` 장애:
  HAProxy가 `cp2/cp3`로 트래픽을 전달해야 합니다.
- `ct-lb1/ct-lb2` 동시 장애:
  클러스터는 계속 동작하지만 외부 `kubectl` 접속은 불가합니다.

## 9. 설정 완료 후 스냅샷

`lb1`, `lb2` 설정이 끝나고 최종 검증까지 완료되면 Proxmox에서 CT 스냅샷을 생성해야 합니다.

권장 사항:

- 운영용 베이스라인 스냅샷은 `haproxy`, `keepalived`, VIP 검증까지 끝난 상태로 생성해야 합니다.
- 이렇게 하면 복원 직후 외부 API VIP와 LB 동작을 바로 점검할 수 있습니다.
- 초기 설치 상태만 보존하려는 목적이면 HA 설정 직전 스냅샷을 별도로 남겨도 됩니다.

스냅샷 생성 전 아래 조건을 먼저 확인해야 합니다.

- `haproxy`, `keepalived` 서비스가 정상 실행 중임
- `192.168.0.180` VIP가 한쪽 CT에 정상 바인딩됨
- `vm-admin`에서 `nc -vz 192.168.0.180 6443` 연결 성공

스냅샷 생성 전 아래 정리 작업을 먼저 수행합니다.

```bash
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*
sudo apt autoremove -y
sudo apt clean
sudo journalctl --vacuum-time=1s
cat /dev/null > ~/.bash_history && history -c
```

권장 스냅샷 이름:

- `lb-ha-keepalived-k8s-api-v1`

권장 적용 방식:

- 스냅샷 이름은 `lb1`, `lb2` 모두 동일하게
  `lb-ha-keepalived-k8s-api-v1`로 맞춥니다.
- 설명(description)은 CT 역할이 드러나도록 CT별로 다르게 기록합니다.

CT별 권장 설명:

- `ct-lb1`:
  `[설치]`
  `- role : lb-1`
  `- hostname : ct-lb1`
  `- vip : 192.168.0.180`
  `- backend : 192.168.0.181, 192.168.0.182, 192.168.0.183`
  `- haproxy : configured`
  `- keepalived : master configured`
  `- k8s api : external access verified`
- `ct-lb2`:
  `[설치]`
  `- role : lb-2`
  `- hostname : ct-lb2`
  `- vip : 192.168.0.180`
  `- backend : 192.168.0.181, 192.168.0.182, 192.168.0.183`
  `- haproxy : configured`
  `- keepalived : backup configured`
  `- k8s api : external access verified`

Proxmox Web UI 예시:

1. `ct-lb1` 선택
1. `Snapshots`
1. `Take Snapshot`
1. 이름과 설명 입력 후 생성
1. `ct-lb2`에도 동일하게 생성

운영 메모:

- 설정 완료 직후 스냅샷을 남겨야 이후 변경이나 장애 대응 시 빠르게 되돌릴 수 있습니다.
- LB 설정 변경 전에도 별도 사전 스냅샷을 남기는 편이 안전합니다.

## 참고

- 설치 본문: [Kubernetes Installation](./installation.md)
- 운영 관리 노드: [VM-ADMIN Installation](../vm-admin/installation.md)
- CT 템플릿: [Proxmox CT Template Guide](../proxmox/ct-template-guide.md)
