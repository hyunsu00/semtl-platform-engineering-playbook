# RKE2 Installation

## 개요

이 문서는 Proxmox VE 기반 Ubuntu 24.04 환경에서 `RKE2` 클러스터를
`control-plane 1대`, `worker 3대` 구성으로 설치하는 표준 절차를 정리합니다.

이 문서의 목표는 다음과 같습니다.

- VM 4대에 동일한 OS/네트워크 기준 적용
- `cp1`에 `rke2-server` 설치
- `w1`, `w2`, `w3`에 `rke2-agent` 조인
- 설치 직후 `kubectl` 사용 준비
- 노드 상태와 핵심 애드온 기동 여부 검증

이 문서는 단일 control-plane 기준입니다.
따라서 etcd 및 Kubernetes API는 `cp1`에 집중되며, control-plane HA는 제공하지 않습니다.
운영 환경에서 API HA가 필요하면 별도 control-plane 확장 문서를 추가로 작성해야 합니다.

## 사전 조건

- Proxmox VE에서 Ubuntu Server `24.04 LTS` ISO를 사용할 수 있어야 합니다.
- VM 4대를 생성할 수 있는 CPU, 메모리, 디스크 여유가 있어야 합니다.
- 모든 노드는 서로 통신 가능한 동일 네트워크에 있어야 합니다.
- 각 노드는 고정 IP 또는 DHCP 예약으로 주소가 변하지 않게 준비해야 합니다.
- 관리자 단말에서 `ssh` 접속이 가능해야 합니다.

권장 호스트명과 IP 예시:

| 노드 | 역할 | vCPU | RAM | 디스크 | IP |
| --- | --- | --- | --- | --- | --- |
| `vm-rke2-cp1` | control-plane | 4 | 8GB | 80GB | `192.168.0.81` |
| `vm-rke2-w1` | worker | 4 | 8GB | 120GB | `192.168.0.91` |
| `vm-rke2-w2` | worker | 4 | 8GB | 120GB | `192.168.0.92` |
| `vm-rke2-w3` | worker | 4 | 8GB | 120GB | `192.168.0.93` |

포트 메모:

- `9345/tcp`: RKE2 registration
- `6443/tcp`: Kubernetes API
- `8472/udp`: Canal VXLAN 기본값
- `10250/tcp`: kubelet metrics/API

## 배치 원칙

- `[모든 노드]`: `cp1`, `w1`, `w2`, `w3` 전체
- `[cp1 전용]`: `vm-rke2-cp1`
- `[worker 공통]`: `vm-rke2-w1`, `vm-rke2-w2`, `vm-rke2-w3`

운영 기준:

- CNI는 RKE2 기본값인 `canal`을 사용합니다.
- Ingress Controller는 RKE2 기본값인 `ingress-nginx`를 유지합니다.
- 기본 스토리지 프로비저너는 포함하지 않습니다.
- `kubectl`은 `cp1`에 기본 설치된 바이너리를 사용합니다.

## 설치 절차

### 1. VM 생성

각 VM 공통 권장값:

- Machine: `q35`
- BIOS: `OVMF (UEFI)`
- SCSI Controller: `VirtIO SCSI single`
- NIC 모델: `VirtIO`
- Ballooning: 비활성화
- CPU Type: `host`

생성 후 확인:

- `cp1` 1대, `worker` 3대가 모두 켜져 있음
- 각 노드에 SSH 접속 가능
- 각 노드의 hostname이 표준과 일치

### 2. Ubuntu 기본 설정 `[모든 노드]`

패키지 업데이트와 기본 도구를 설치합니다.

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y curl wget vim git qemu-guest-agent nfs-common open-iscsi
sudo systemctl enable --now qemu-guest-agent
```

호스트명을 확인하고 필요하면 수정합니다.

```bash
hostnamectl
sudo hostnamectl set-hostname vm-rke2-cp1
```

`/etc/hosts` 예시:

```text
192.168.0.81 vm-rke2-cp1
192.168.0.91 vm-rke2-w1
192.168.0.92 vm-rke2-w2
192.168.0.93 vm-rke2-w3
```

시간 동기화 확인:

```bash
timedatectl status
```

정상 기준:

- `System clock synchronized: yes`
- 노드 간 `ping` 통신 가능

### 3. 커널/네트워크 사전 설정 `[모든 노드]`

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

### 4. Swap 비활성화 `[모든 노드]`

```bash
sudo swapoff -a
sudo sed -i.bak '/ swap / s/^/#/' /etc/fstab
free -h
```

정상 기준:

- `Swap: 0B`

### 5. 방화벽/보안 정책 확인 `[모든 노드]`

테스트 또는 사설망 환경에서 `ufw`를 사용 중이면 필요한 포트를 허용하거나 비활성화합니다.

```bash
sudo ufw status
```

`ufw`를 유지할 경우 예시:

```bash
sudo ufw allow 22/tcp
sudo ufw allow 6443/tcp
sudo ufw allow 9345/tcp
sudo ufw allow 10250/tcp
sudo ufw allow 8472/udp
```

문서 기준:

- 초기 설치 안정화를 우선할 때는 노드 간 방화벽 정책을 단순하게 유지합니다.

### 6. 서버 토큰 생성 `[cp1 전용]`

클러스터 조인에 사용할 토큰을 미리 생성합니다.

```bash
sudo mkdir -p /etc/rancher/rke2
openssl rand -hex 24
```

출력된 값을 `RKE2_TOKEN`으로 사용합니다.

예시:

```text
4a6d7f1d58dfb8d3a6d873f0e2f8df8a8154f6a914e3c011
```

### 7. `rke2-server` 설정 파일 작성 `[cp1 전용]`

`cp1`에서 `/etc/rancher/rke2/config.yaml`을 생성합니다.

```bash
cat <<'EOF' | sudo tee /etc/rancher/rke2/config.yaml
token: "RKE2_TOKEN_VALUE"
tls-san:
  - "vm-rke2-cp1"
  - "192.168.0.81"
write-kubeconfig-mode: "0644"
cni: "canal"
node-name: "vm-rke2-cp1"
node-ip: "192.168.0.81"
EOF
```

주의:

- `RKE2_TOKEN_VALUE`는 앞 단계에서 생성한 실제 토큰으로 교체합니다.
- `tls-san`에는 `kubectl` 또는 외부 자동화가 접속할 호스트명/IP를 모두 넣습니다.
- DHCP 환경이라도 `node-ip`는 운영 IP로 고정하는 편이 안전합니다.

### 8. `rke2-server` 설치 및 기동 `[cp1 전용]`

```bash
curl -sfL https://get.rke2.io | sudo sh -
sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service
```

초기 기동 확인:

```bash
sudo systemctl status rke2-server --no-pager
sudo journalctl -u rke2-server -f
```

정상 기준:

- `Active: active (running)`
- 로그에 fatal error가 없음
- 잠시 후 `/var/lib/rancher/rke2/server/node-token` 파일 생성

### 9. `kubectl` 사용 준비 `[cp1 전용]`

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

초기에는 `cp1`만 `Ready` 또는 잠시 `NotReady`일 수 있습니다.
잠시 기다린 뒤 다시 확인합니다.

### 10. Worker 설정 파일 작성 `[worker 공통]`

각 worker에서 `/etc/rancher/rke2/config.yaml`을 생성합니다.

`w1` 예시:

```bash
sudo mkdir -p /etc/rancher/rke2

cat <<'EOF' | sudo tee /etc/rancher/rke2/config.yaml
server: "https://192.168.0.81:9345"
token: "RKE2_TOKEN_VALUE"
node-name: "vm-rke2-w1"
node-ip: "192.168.0.91"
EOF
```

노드별 변경값:

- `w1`: `node-name: vm-rke2-w1`, `node-ip: 192.168.0.91`
- `w2`: `node-name: vm-rke2-w2`, `node-ip: 192.168.0.92`
- `w3`: `node-name: vm-rke2-w3`, `node-ip: 192.168.0.93`

### 11. `rke2-agent` 설치 및 조인 `[worker 공통]`

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
- `server https://192.168.0.81:9345` 연결 오류가 지속되지 않음

### 12. 클러스터 상태 검증 `[cp1 전용]`

모든 worker 기동 후 `cp1`에서 확인합니다.

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
```

정상 기준:

- 노드 4대가 모두 `Ready`
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

### 13. 설치 후 기본 점검 `[cp1 전용]`

버전과 클러스터 정보를 기록합니다.

```bash
kubectl version
kubectl cluster-info
sudo /var/lib/rancher/rke2/bin/crictl info
```

노드 리소스 확인:

```bash
kubectl top nodes
```

메모:

- `kubectl top nodes`는 `metrics-server` 기동 후 응답이 나옵니다.
- 설치 직후 1~2분 정도는 지표 수집이 지연될 수 있습니다.

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

### kubeconfig 동작 확인

```bash
kubectl get nodes
kubectl get ns
kubectl get ingressclass
```

정상 기준:

- `default`, `kube-system` 등 기본 네임스페이스 조회 가능
- `nginx` IngressClass 존재

### 재부팅 후 확인

노드 재부팅 후 아래를 다시 확인합니다.

```bash
kubectl get nodes
kubectl get pods -A
```

단일 control-plane 구조에서는 `cp1` 재부팅 동안 API가 일시 중단됩니다.

## 트러블슈팅

### Worker가 조인되지 않음

증상:

- `rke2-agent` 서비스가 반복 재시작됨
- 로그에 `failed to get CA certs` 또는 `connection refused`

확인:

```bash
sudo journalctl -u rke2-agent -n 100 --no-pager
nc -zv 192.168.0.81 9345
```

조치:

- `cp1`의 `rke2-server`가 먼저 완전히 올라왔는지 확인합니다.
- worker의 `server`, `token` 값 오타를 점검합니다.
- 노드 간 방화벽에서 `9345/tcp`, `6443/tcp`가 허용되었는지 확인합니다.

### 노드는 보이지만 `NotReady`

증상:

- `kubectl get nodes`에서 worker가 `NotReady`

확인:

```bash
kubectl describe node vm-rke2-w1
kubectl -n kube-system get pods -o wide
```

조치:

- `canal` 파드가 정상인지 확인합니다.
- `swapoff -a`가 실제로 적용되었는지 확인합니다.
- `/etc/sysctl.d/90-rke2.conf` 값이 반영되었는지 확인합니다.

### `kubectl` 명령이 없거나 연결되지 않음

증상:

- `kubectl: command not found`
- `The connection to the server localhost:8080 was refused`

조치:

```bash
export PATH=$PATH:/var/lib/rancher/rke2/bin
mkdir -p ~/.kube
sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
sudo chown "$(id -u)":"$(id -g)" ~/.kube/config
```

### `cp1` 장애 시 클러스터 접근 불가

단일 control-plane 구조의 한계입니다.

대응:

- `cp1` 스냅샷 또는 VM 백업 정책을 반드시 운영합니다.
- etcd 스냅샷 보관 경로와 복구 절차를 별도 문서로 분리하는 것을 권장합니다.
- 운영 중요도가 높아지면 control-plane 3대 구조로 확장합니다.

## 참고

- [Rancher Installation](../rancher/installation.md)
