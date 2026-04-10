# RKE2 Installation

## 개요

이 문서는 Proxmox VE 기반 `Ubuntu Server 22.04 LTS` 환경에서
`RKE2` 클러스터를 `control-plane 1대`, `worker 3대` 구성으로
설치하는 표준 절차를 정리합니다.

이번 설치 기준은 다음과 같습니다.

- 모든 VM은 `192.168.0.x` 단일 네트워크를 사용
- VM 레벨의 별도 내부망 `10.10.10.x`는 사용하지 않음
- Pod/Service 네트워크는 RKE2 기본 CNI가 별도로 구성
- `vm-rke2-cp1`에 `rke2-server` 설치
- `vm-rke2-w1`, `vm-rke2-w2`, `vm-rke2-w3`에 `rke2-agent` 조인

이 문서는 단일 control-plane 기준입니다.
따라서 etcd 및 Kubernetes API는 `vm-rke2-cp1`에 집중되며,
control-plane HA는 제공하지 않습니다.

## 사전 조건

- Proxmox VE에서 `Ubuntu Server 22.04 LTS` ISO를 사용할 수 있어야 합니다.
- VM 4대를 생성할 수 있는 CPU, 메모리, 디스크 여유가 있어야 합니다.
- 모든 노드는 서로 통신 가능한 동일 네트워크에 있어야 합니다.
- 각 노드는 고정 IP 또는 DHCP 예약으로 주소가 변하지 않게 준비해야 합니다.
- 관리자 단말에서 각 노드로 `ssh` 접속이 가능해야 합니다.

## 노드 구성 기준

| 노드 | 역할 | vCPU | RAM | 디스크 | IP |
| --- | --- | --- | --- | --- | --- |
| `vm-rke2-cp1` | control-plane | 4 | 8GB | 100GB | `192.168.0.181` |
| `vm-rke2-w1` | worker | 4 | 8GB | 300GB | `192.168.0.191` |
| `vm-rke2-w2` | worker | 4 | 8GB | 300GB | `192.168.0.192` |
| `vm-rke2-w3` | worker | 4 | 8GB | 300GB | `192.168.0.193` |

네트워크 기준:

- Proxmox 브리지: `vmbr0`
- 노드 네트워크: `192.168.0.0/24`
- 게이트웨이 예시: `192.168.0.1`
- DNS 예시: 내부 DNS 또는 게이트웨이 DNS

RKE2 내부 기본 네트워크:

- Pod CIDR: `10.42.0.0/16`
- Service CIDR: `10.43.0.0/16`

즉, 노드 VM은 `192.168.0.x`를 사용하고,
Pod와 Service는 RKE2 내부 네트워크를 따로 사용합니다.

포트 메모:

- `22/tcp`: SSH
- `9345/tcp`: RKE2 registration
- `6443/tcp`: Kubernetes API
- `8472/udp`: Canal VXLAN 기본값
- `10250/tcp`: kubelet metrics/API

## 배치 원칙

- `[모든 노드]`: `vm-rke2-cp1`, `vm-rke2-w1`, `vm-rke2-w2`, `vm-rke2-w3`
- `[cp1 전용]`: `vm-rke2-cp1`
- `[worker 공통]`: `vm-rke2-w1`, `vm-rke2-w2`, `vm-rke2-w3`

운영 기준:

- VM NIC는 각 노드당 1개만 사용합니다.
- 모든 노드는 `vmbr0`에만 연결합니다.
- Proxmox VM 생성 시 네트워크 장치의 `Firewall` 옵션은 체크하지 않습니다.
- Ubuntu 내부 방화벽 `ufw`는 사용하지 않습니다.
- CNI는 RKE2 기본값인 `canal`을 사용합니다.
- Ingress Controller는 RKE2 기본값인 `ingress-nginx`를 유지합니다.
- `kubectl`은 `vm-rke2-cp1`에 기본 설치된 바이너리를 사용합니다.

## 설치 절차

### 1. Proxmox VM 생성

Proxmox 화면에서 선택하는 순서에 맞춰 정리합니다.

공통 기준:

- OS: `Ubuntu Server 22.04 LTS`
- Machine: `q35`
- BIOS: `OVMF (UEFI)`
- SCSI Controller: `VirtIO SCSI single`

CPU:

- Cores: `4`
- Type: `host`
- NUMA: 기본값 유지

Memory:

- Memory: `8192 MiB`
- Minimum memory: 사용 안 함
- Ballooning Device: 비활성화
- Shares: 기본값 유지
- KSM: 비활성화

Disk:

- Bus/Device: `SCSI`
- Cache: `No cache` 권장
- Discard: 활성화
- IO thread: 활성화
- SSD emulation: 활성화
- Async IO: `io_uring`
- Backup: 활성화
- Replicate skip: 해제
- Read only: 해제

Network:

- Model: `VirtIO`
- Bridge: `vmbr0`
- Firewall: 해제

노드별 생성값:

| VM | CPU | RAM | Disk | IP |
| --- | --- | --- | --- | --- |
| `vm-rke2-cp1` | 4 vCPU | 8GB | 100GB | `192.168.0.181/24` |
| `vm-rke2-w1` | 4 vCPU | 8GB | 300GB | `192.168.0.191/24` |
| `vm-rke2-w2` | 4 vCPU | 8GB | 300GB | `192.168.0.192/24` |
| `vm-rke2-w3` | 4 vCPU | 8GB | 300GB | `192.168.0.193/24` |

생성 후 확인:

- VM 4대가 모두 부팅됨
- 각 VM NIC가 `vmbr0`에 연결됨
- 각 VM CPU Type이 `host`로 설정됨
- 각 VM 메모리가 고정 할당되고 `Ballooning`이 비활성화됨
- 각 VM 디스크가 `SCSI`로 연결되고 `Discard`, `IO thread`, `SSD emulation`이 활성화됨
- 각 노드에 콘솔 또는 `ssh`로 접속 가능

### 2. Ubuntu 22.04 설치 `[모든 노드]`

각 VM에 `Ubuntu Server 22.04 LTS`를 설치합니다.

설치 중 권장값:

- 기본 설치: `Ubuntu Server`
- OpenSSH server: 설치
- 디스크 파티션: 기본 guided layout 사용 가능
- 추가 패키지: 최소화

설치 직후 수행할 작업:

- 패키지 미러와 네트워크가 정상인지 확인
- 로그인 계정으로 `ssh` 접속 가능한지 확인
- 호스트명을 노드 표준명으로 맞춤

호스트명 설정 예시:

```bash
sudo hostnamectl set-hostname vm-rke2-cp1
hostnamectl
```

노드별 호스트명:

- `vm-rke2-cp1`
- `vm-rke2-w1`
- `vm-rke2-w2`
- `vm-rke2-w3`

### 3. Netplan DHCP 설정 `[모든 노드]`

이 문서 기준으로 노드 IP는 VM 내부에서 수동 고정하지 않고,
공유기 또는 DHCP 서버에서 MAC 주소 기준으로 예약합니다.
Ubuntu 기본 설치 상태의 `cloud-init` DHCP 구성을 유지하고,
각 노드가 항상 같은 IP를 받도록 외부 DHCP에서 고정합니다.

먼저 인터페이스 이름을 확인합니다.

```bash
ip -br addr
```

먼저 현재 Netplan 파일을 확인합니다.

```bash
ls -l /etc/netplan
sudo sed -n '1,200p' /etc/netplan/*.yaml
```

기본 설치 상태라면 보통 `50-cloud-init.yaml`에 아래와 비슷한 형태로
`dhcp4: true`가 들어 있습니다.

```yaml
network:
    ethernets:
        enp6s18:
            dhcp4: true
    version: 2
```

DHCP 예약 기준 IP:

- `vm-rke2-cp1`: `192.168.0.181`
- `vm-rke2-w1`: `192.168.0.191`
- `vm-rke2-w2`: `192.168.0.192`
- `vm-rke2-w3`: `192.168.0.193`

권장 순서:

1. 각 VM의 MAC 주소 확인
2. 공유기 또는 DHCP 서버에서 MAC별 예약 등록
3. VM 내부에 별도 static Netplan 파일을 만들지 않음
4. 재부팅 또는 DHCP 갱신 후 예약 IP 수령 확인

MAC 주소 확인 예시:

```bash
ip -br link show enp6s18
```

확인:

```bash
ip -br addr
ip route
```

정상 기준:

- 각 노드가 예약된 IP로 올라옴
- 기본 게이트웨이가 DHCP를 통해 정상 수신됨
- 외부 저장소와 내부 노드 모두 통신 가능

### 4. 기본 패키지 설치 `[모든 노드]`

이 문서는 이후 `Longhorn` 사용을 전제로 하므로
모든 노드에 `nfs-common`, `open-iscsi`를 설치하고
`iscsid` 서비스를 활성화합니다.
`qemu-guest-agent`는 VM 준비 단계에서 이미 설치되어 있다고 가정합니다.

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y nfs-common open-iscsi
sudo systemctl enable --now iscsid
```

시간 동기화 확인:

```bash
timedatectl status
```

정상 기준:

- `System clock synchronized: yes`
- `iscsid.service`가 `active (running)`

추가 확인:

```bash
systemctl status iscsid --no-pager
systemctl is-enabled iscsid
```

### 5. 내부 DNS 확인 `[모든 노드]`

이 문서는 내부 DNS에서 각 노드 FQDN이 조회되는 구성을 전제로 합니다.

예시:

- `rke2-cp1.internal.semtl.synology.me` -> `192.168.0.181`
- `rke2-w1.internal.semtl.synology.me` -> `192.168.0.191`
- `rke2-w2.internal.semtl.synology.me` -> `192.168.0.192`
- `rke2-w3.internal.semtl.synology.me` -> `192.168.0.193`

확인:

```bash
ping -c 2 rke2-cp1.internal.semtl.synology.me
ping -c 2 rke2-w1.internal.semtl.synology.me
ping -c 2 rke2-w2.internal.semtl.synology.me
ping -c 2 rke2-w3.internal.semtl.synology.me
```

### 6. 커널 및 sysctl 사전 설정 `[모든 노드]`

RKE2 동작에 필요한 커널 모듈과 sysctl 값을 적용합니다.

```bash
cat <<'EOF' | sudo tee /etc/modules-load.d/rke2.conf
br_netfilter
overlay
EOF

sudo modprobe br_netfilter
sudo modprobe overlay

cat <<'EOF' | sudo tee /etc/sysctl.d/90-rke2.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system
```

검증:

```bash
lsmod | grep -E 'br_netfilter|overlay'
sysctl net.ipv4.ip_forward
```

### 7. Swap 비활성화 `[모든 노드]`

```bash
sudo swapoff -a
sudo sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab
free -h
```

정상 기준:

- `Swap: 0B`

### 8. 방화벽 미사용 기준 확인 `[모든 노드]`

이 문서 기준으로는 방화벽을 별도로 사용하지 않습니다.

- Proxmox VM 생성 시 네트워크 장치의 `Firewall` 옵션을 체크하지 않습니다.
- Ubuntu 내부 `ufw`는 설치 또는 활성화하지 않습니다.

확인:

```bash
sudo ufw status
```

정상 기준:

- `Status: inactive`

메모:

- 초기 설치 단계에서는 네트워크 경로를 단순하게 유지하는 것이 중요합니다.
- 방화벽 정책은 RKE2 설치 완료 후 별도 운영 기준이 정리되면 추가합니다.

### 9. 선행 통신 점검 `[모든 노드]`

RKE2 설치 전에 노드 간 통신이 정상인지 먼저 확인합니다.

```bash
ping -c 2 192.168.0.181
ping -c 2 192.168.0.191
ping -c 2 192.168.0.192
ping -c 2 192.168.0.193
```

필요 시 `cp1`에서:

```bash
ssh semtl@192.168.0.191 hostname
ssh semtl@192.168.0.192 hostname
ssh semtl@192.168.0.193 hostname
```

정상 기준:

- 모든 노드가 IP 기준으로 서로 도달 가능
- 관리자 단말에서도 SSH 접속 가능

### 10. 서버 토큰 준비 `[cp1 전용]`

```bash
sudo mkdir -p /etc/rancher/rke2
openssl rand -hex 24
```

출력된 값을 `RKE2_TOKEN`으로 사용합니다.

예시:

```text
e85fb33d3937a002aaed8d60504f97e879b91733b40904ce
```

### 11. `rke2-server` 설정 `[cp1 전용]`

`vm-rke2-cp1`에서 `/etc/rancher/rke2/config.yaml`을 생성합니다.

```bash
sudo mkdir -p /etc/rancher/rke2

cat <<'EOF' | sudo tee /etc/rancher/rke2/config.yaml
token: "<RKE2_TOKEN_VALUE>"
tls-san:
  - "rke2-cp1.internal.semtl.synology.me"
  - "192.168.0.181"
write-kubeconfig-mode: "0644"
cni: "canal"
node-name: "vm-rke2-cp1"
node-ip: "192.168.0.181"
EOF
```

주의:

- `<RKE2_TOKEN_VALUE>`는 실제 토큰으로 교체합니다.
- `tls-san`에는 운영자가 실제로 접속할 FQDN/IP를 넣습니다.
- 단일망 기준이므로 `node-ip`는 `192.168.0.181`을 사용합니다.

### 12. `rke2-server` 설치 및 기동 `[cp1 전용]`

```bash
curl -sfL https://get.rke2.io | sudo sh -
sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service
```

확인:

```bash
sudo systemctl status rke2-server --no-pager
sudo journalctl -u rke2-server -f
```

정상 기준:

- `Active: active (running)`
- 로그에 fatal error가 없음
- `/var/lib/rancher/rke2/server/node-token` 파일 생성

### 13. `kubectl` 사용 준비 `[cp1 전용]`

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
sudo chown "$(id -u)":"$(id -g)" ~/.kube/config
echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' >> ~/.bashrc
export PATH=$PATH:/var/lib/rancher/rke2/bin
```

확인:

```bash
kubectl get nodes
kubectl get pods -A
```

초기에는 `vm-rke2-cp1`만 보이거나 잠시 `NotReady`일 수 있습니다.
잠시 기다린 뒤 다시 확인합니다.

### 14. Worker 설정 파일 작성 `[worker 공통]`

각 worker에서 `/etc/rancher/rke2/config.yaml`을 생성합니다.

`vm-rke2-w1`

```bash
sudo mkdir -p /etc/rancher/rke2

cat <<'EOF' | sudo tee /etc/rancher/rke2/config.yaml
server: "https://192.168.0.181:9345"
token: "<RKE2_TOKEN_VALUE>"
node-name: "vm-rke2-w1"
node-ip: "192.168.0.191"
EOF
```

`vm-rke2-w2`

```bash
sudo mkdir -p /etc/rancher/rke2

cat <<'EOF' | sudo tee /etc/rancher/rke2/config.yaml
server: "https://192.168.0.181:9345"
token: "<RKE2_TOKEN_VALUE>"
node-name: "vm-rke2-w2"
node-ip: "192.168.0.192"
EOF
```

`vm-rke2-w3`

```bash
sudo mkdir -p /etc/rancher/rke2

cat <<'EOF' | sudo tee /etc/rancher/rke2/config.yaml
server: "https://192.168.0.181:9345"
token: "<RKE2_TOKEN_VALUE>"
node-name: "vm-rke2-w3"
node-ip: "192.168.0.193"
EOF
```

### 15. `rke2-agent` 설치 및 조인 `[worker 공통]`

각 worker에서 실행합니다.

```bash
curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_TYPE="agent" sh -
sudo systemctl enable rke2-agent.service
sudo systemctl start rke2-agent.service
```

확인:

```bash
sudo systemctl status rke2-agent --no-pager
sudo journalctl -u rke2-agent -f
```

정상 기준:

- `Active: active (running)`
- `server https://192.168.0.181:9345` 연결 오류가 지속되지 않음

### 16. 클러스터 상태 검증 `[cp1 전용]`

모든 worker 기동 후 `vm-rke2-cp1`에서 확인합니다.

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
```

정상 기준:

- 노드 4대가 모두 `Ready`
- 모든 노드의 `INTERNAL-IP`가 `192.168.0.x`로 표시
- `kube-system` 네임스페이스의 핵심 파드가 `Running`
- `rke2-ingress-nginx`, `canal`, `coredns`, `metrics-server`가 정상 기동

예상 출력 예시:

```text
NAME         STATUS   ROLES                       AGE   VERSION
vm-rke2-cp1  Ready    control-plane,etcd,master  10m   v1.31.x+rke2r1
vm-rke2-w1   Ready    <none>                      5m   v1.31.x+rke2r1
vm-rke2-w2   Ready    <none>                      4m   v1.31.x+rke2r1
vm-rke2-w3   Ready    <none>                      4m   v1.31.x+rke2r1
```

### 17. 설치 후 기본 점검 `[cp1 전용]`

```bash
kubectl version
kubectl cluster-info
```

노드 리소스 확인:

```bash
kubectl top nodes
```

메모:

- `kubectl cluster-info`에서 control plane 주소가 `https://127.0.0.1:6443`로
  보이는 것은 `cp1` 로컬 kubeconfig 기준이므로 정상입니다.
- `kubectl top nodes`는 `metrics-server` 기동 후 응답이 나옵니다.
- 설치 직후 1~2분 정도는 지표 수집이 지연될 수 있습니다.

선택 사항:

- `crictl`은 설치 자체에 필수는 아니며, 노드 런타임 장애 분석이나
  컨테이너/이미지 상태를 직접 확인할 때 사용합니다.
- `crictl`을 사용할 경우 기본 endpoint 탐색 시 실패할 수 있으므로 RKE2 전용
  containerd 소켓인 `unix:///run/k3s/containerd/containerd.sock`를 지정합니다.

일회성 확인 예시:

```bash
sudo /var/lib/rancher/rke2/bin/crictl \
  --runtime-endpoint unix:///run/k3s/containerd/containerd.sock info
```

반복 사용 시에만 `/etc/crictl.yaml`을 만들어 두는 편이 편합니다.

```bash
cat <<'EOF' | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/k3s/containerd/containerd.sock
image-endpoint: unix:///run/k3s/containerd/containerd.sock
timeout: 10
debug: false
EOF
```

설정 후 확인 예시:

```bash
sudo /var/lib/rancher/rke2/bin/crictl info
sudo /var/lib/rancher/rke2/bin/crictl ps
sudo /var/lib/rancher/rke2/bin/crictl images
```

### 18. 설치 직후 후속 작업

이 문서 기준으로 `RKE2` 기본 구성만 끝난 상태에서는
`Ingress` 외부 IP가 아직 없습니다.

운영 기준 권장 순서:

1. `RKE2` 노드와 기본 애드온 상태 확인
2. `MetalLB` 설치
3. `192.168.0.200-192.168.0.220` IP 풀 구성
4. `ingress-nginx` 서비스를 `LoadBalancer`로 전환
5. `Argo CD`, `Grafana`, `Prometheus`, `Rancher` 같은 후속 서비스 설치

후속 문서:

- [`MetalLB 설치`](../metallb/installation.md)

## 검증 방법

### 서비스 상태

`cp1`:

```bash
sudo systemctl is-enabled rke2-server
sudo systemctl is-active rke2-server
```

`worker`:

```bash
sudo systemctl is-enabled rke2-agent
sudo systemctl is-active rke2-agent
```

정상 기준:

- 모두 `enabled`
- 모두 `active`

### kubeconfig 동작 확인 `[cp1 전용]`

`kubectl`이 설정된 `vm-rke2-cp1`에서 실행합니다.

```bash
kubectl get nodes
kubectl get ns
kubectl get ingressclass
```

정상 기준:

- `default`, `kube-system` 등 기본 네임스페이스 조회 가능
- `nginx` IngressClass 존재

### 재부팅 후 확인 `[cp1 전용]`

노드를 한 대씩 순차 재부팅한 뒤, `vm-rke2-cp1`에서 아래를 다시 확인합니다.

```bash
kubectl get nodes
kubectl get pods -A
```

단일 control-plane 구조에서는 `vm-rke2-cp1` 재부팅 동안 API가 일시 중단됩니다.

## 초기 설치 완료 후 스냅샷 생성

기본 설치, 클러스터 조인, `kubectl` 검증, 순차 재부팅 확인이 끝났으면
Proxmox에서 각 `RKE2` VM의 초기 기준점을 남기기 위해 스냅샷을 생성합니다.

스냅샷은 반드시 불필요 파일(찌꺼기) 정리 후 생성합니다.

### 불필요 파일 정리 `[모든 노드]`

각 노드에서 아래 정리 작업을 먼저 수행합니다.

```bash
# /tmp 전체 삭제
sudo rm -rf /tmp/*

# /var/tmp 전체 삭제
sudo rm -rf /var/tmp/*

# 미사용 패키지 정리
sudo apt autoremove -y

# APT 캐시 정리
sudo apt clean

# journal 로그 전체 정리
sudo journalctl --vacuum-time=1s

# 현재 사용자 bash 히스토리 비우기
cat /dev/null > ~/.bash_history && history -c
```

### Proxmox 스냅샷 생성

권장 시점:

- `vm-rke2-cp1`, `vm-rke2-w1`, `vm-rke2-w2`, `vm-rke2-w3`가 모두 `Ready`
- `kubectl get pods -A` 기준으로 핵심 파드가 모두 `Running`
- `kubectl top nodes`가 정상 응답
- 노드 순차 재부팅 후 클러스터가 정상 복귀하는 것까지 확인 완료
- `MetalLB`, `Argo CD`, `Grafana`, `Prometheus`, `Rancher` 같은 후속 구성 적용 전
- Ubuntu 기본 설치, hostname 설정, 네트워크 기본 설정 스냅샷 이후
- 즉, `RKE2` 설치와 클러스터 검증이 끝난 상태부터 기준점으로 남길 때

Proxmox Web UI 절차:

1. 대상 VM 선택
1. `스냅샷`
1. `스냅샷 생성`
1. 이름과 설명 입력 후 생성

권장 대상:

- `vm-rke2-cp1`
- `vm-rke2-w1`
- `vm-rke2-w2`
- `vm-rke2-w3`

권장 예시:

- `Name`: `rke2-install-clean-v1`
- 설명은 노드 역할이 드러나도록 VM별로 다르게 기록합니다.

VM별 권장 설명:

- `vm-rke2-cp1`:
  `[설치]`
  `- rke2 : v1.34.6+rke2r1`
  `- role : control-plane`
  `- hostname : vm-rke2-cp1`
  `- node ip : 192.168.0.181`
  `- bootstrap : rke2-server 설치 및 초기 클러스터 구성 완료`
  `- kubectl : configured`
  `- addons : canal, ingress-nginx, coredns, metrics-server`
  `- status : kubectl get nodes 기준 Ready`
- `vm-rke2-w1`:
  `[설치]`
  `- rke2 : v1.34.6+rke2r1`
  `- role : worker-1`
  `- hostname : vm-rke2-w1`
  `- node ip : 192.168.0.191`
  `- join : rke2-agent join 완료`
  `- cni : canal ready`
  `- metrics : kubectl top nodes 확인 가능`
  `- status : kubectl get nodes 기준 Ready`
- `vm-rke2-w2`:
  `[설치]`
  `- rke2 : v1.34.6+rke2r1`
  `- role : worker-2`
  `- hostname : vm-rke2-w2`
  `- node ip : 192.168.0.192`
  `- join : rke2-agent join 완료`
  `- cni : canal ready`
  `- metrics : kubectl top nodes 확인 가능`
  `- status : kubectl get nodes 기준 Ready`
- `vm-rke2-w3`:
  `[설치]`
  `- rke2 : v1.34.6+rke2r1`
  `- role : worker-3`
  `- hostname : vm-rke2-w3`
  `- node ip : 192.168.0.193`
  `- join : rke2-agent join 완료`
  `- cni : canal ready`
  `- metrics : kubectl top nodes 확인 가능`
  `- status : kubectl get nodes 기준 Ready`

운영 메모:

- 이 스냅샷은 `RKE2` 초기 설치 직후 기준점으로 사용합니다.
- 스냅샷 이름은 4대 VM 모두 동일하게 `rke2-install-clean-v1`로 맞추는 것을 권장합니다.
- 단일 control-plane 구조에서는 특히 `vm-rke2-cp1` 스냅샷이 중요합니다.
- 실제 운영 워크로드와 데이터가 쌓이기 시작한 뒤에는 오래된 스냅샷을 장기 보관하지
  말고, 변경 작업 직전에만 짧게 사용하는 편이 좋습니다.

## 참고

- [Proxmox VM Template Guide](../proxmox/vm-template-guide.md)
- [Proxmox Storage And Network Expansion](../proxmox/storage-and-network-expansion.md)
- [MetalLB Installation](../metallb/installation.md)
