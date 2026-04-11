# VM-ADMIN Installation

## 문서 목적

이 문서는 `vm-admin`를 운영 전용 관리 노드로 구성하는 절차를 정리합니다.
현재 기준은 [`RKE2 Installation`](../rke2/installation.md) 문서의 단일 control-plane,
단일 네트워크 구성에 맞춘 결과만 반영합니다.

이 문서에서 확인한 범위는 다음과 같습니다.

- `kubectl` 설치 및 RKE2 원격 제어
- `helm` 설치 및 차트 배포 준비
- `mc` 설치 및 MinIO(`192.168.0.171`) 관리
- `k9s` 바이너리 설치
- 운영 경로에서 사용하지 않는 `snap` 정리

실패했던 시도나 이전 가설은 제외하고,
현재 운영 기준에서 재현 가능한 흐름만 남깁니다.

## 구성 요약

- 관리 노드: `vm-admin`
- 관리 노드 네트워크:
  - NIC 1개
  - `192.168.0.x` 대역으로만 직접 접근
- RKE2 Control Plane:
  - `vm-rke2-cp1`
  - `192.168.0.181`
- RKE2 Worker:
  - `vm-rke2-w1`: `192.168.0.191`
  - `vm-rke2-w2`: `192.168.0.192`
  - `vm-rke2-w3`: `192.168.0.193`
- Kubernetes API:
  - `https://192.168.0.181:6443`
- MinIO:
  - API: `http://192.168.0.171:9000`
  - Console: `http://192.168.0.171:9001`

이 문서는 별도 내부망 `10.10.10.x`를 사용하지 않습니다.
RKE2 노드와 `vm-admin` 모두 `192.168.0.0/24` 단일 네트워크 기준입니다.

## 1. kubectl 설치

`vm-admin`에서 `kubectl`은 공식 Kubernetes apt 저장소로 설치합니다.

```bash
sudo apt update
sudo apt install -y ca-certificates curl apt-transport-https gnupg

sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt update
sudo apt install -y kubectl

kubectl version --client
```

## 2. kubeconfig 복사

`vm-admin`에서는 `vm-rke2-cp1`의 RKE2 kubeconfig를 복사해 사용합니다.
이 문서 기준으로는 `vm-rke2-cp1`의 사용자 kubeconfig인
`/home/semtl/.kube/config`를 직접 복사합니다.

### 2.1 VM-ADMIN으로 kubeconfig 복사

`vm-admin`에서 아래를 실행합니다.

```bash
mkdir -p ~/.kube
scp semtl@192.168.0.181:/home/semtl/.kube/config ~/.kube/config
chmod 600 ~/.kube/config
```

사전 조건:

- `vm-rke2-cp1`의 `semtl` 계정 홈에 `~/.kube/config`가 이미 준비되어 있어야 합니다.
- 해당 파일은 `semtl` 계정으로 읽을 수 있어야 합니다.

## 3. kubeconfig 서버 주소 확인 및 수정

RKE2가 생성한 kubeconfig에는 기본적으로 loopback 주소가 들어 있습니다.

```bash
grep server ~/.kube/config
```

예시:

```text
server: https://127.0.0.1:6443
```

이 값을 그대로 두면 `vm-admin`에서는 API 서버에 접속할 수 없습니다.
`vm-admin`은 외부에서 `vm-rke2-cp1`의 실제 주소인
`192.168.0.181:6443`로 접속해야 합니다.

`rke2-server` 설정의 `tls-san`에 `192.168.0.181`이 포함되어 있어야 하며,
이 기준은 [`RKE2 Installation`](../rke2/installation.md) 문서와 동일합니다.

### 3.1 kubeconfig 백업 및 server 변경

```bash
cp ~/.kube/config ~/.kube/config.bak
OLD_SERVER='server: https://127.0.0.1:6443'
NEW_SERVER='server: https://192.168.0.181:6443'
sed -i \
  "s#${OLD_SERVER}#${NEW_SERVER}#g" \
  ~/.kube/config
grep server ~/.kube/config
```

기대 결과:

```text
server: https://192.168.0.181:6443
```

## 4. kubectl 동작 검증

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

확인 예시:

- `vm-rke2-cp1`: `Ready`, `control-plane`, `192.168.0.181`
- `vm-rke2-w1`: `Ready`, `192.168.0.191`
- `vm-rke2-w2`: `Ready`, `192.168.0.192`
- `vm-rke2-w3`: `Ready`, `192.168.0.193`

위 결과가 보이면 `vm-admin`에서 RKE2 원격 제어가 가능한 상태입니다.

문제가 있으면 다음을 먼저 확인합니다.

- `vm-admin`에서 `192.168.0.181:6443`로 네트워크 접근 가능한지
- `vm-rke2-cp1`의 `/etc/rancher/rke2/config.yaml`에 `tls-san`이 올바르게 들어갔는지
- 복사한 kubeconfig의 `server:` 값이 `127.0.0.1`로 남아 있지 않은지

## 5. Helm 설치

`vm-admin`은 Kubernetes 운영 전용 노드이므로 `helm`도 함께 설치합니다.

```bash
curl -fsSL \
  https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
  | bash
helm version
```

## 6. MinIO 관리용 mc 설치

MinIO 서버는 별도 VM(`192.168.0.171`)에 두고,
`vm-admin`에는 관리 클라이언트 `mc`만 설치합니다.

```bash
curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o mc
chmod +x mc
sudo mv mc /usr/local/bin/
mc --version
```

## 7. MinIO alias 등록

```bash
mc alias set minio http://192.168.0.171:9000 MINIO_ROOT_USER MINIO_ROOT_PASSWORD
```

예시:

```bash
mc alias set minio http://192.168.0.171:9000 admin '비밀번호'
```

검증:

```bash
mc admin info minio
mc ls minio
```

## 8. 운영 편의 설정

`kubectl`, `helm`, `mc`를 자주 사용하는 운영 노드이므로
아래 alias와 completion을 적용합니다.

```bash
echo 'alias k=kubectl' >> ~/.bashrc
echo 'alias h=helm' >> ~/.bashrc
echo 'alias m=mc' >> ~/.bashrc
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
source ~/.bashrc
```

## 9. k9s 설치

이 환경에서는 `snap` 기반 설치 대신 바이너리 직접 설치를 사용합니다.

```bash
K9S_VERSION="v0.50.18"
curl -fsSL -o /tmp/k9s_linux_amd64.tar.gz \
  "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_linux_amd64.tar.gz"
tar -xzf /tmp/k9s_linux_amd64.tar.gz -C /tmp
sudo install -m 0755 /tmp/k9s /usr/local/bin/k9s
k9s version
```

## 10. snap 정리

이 환경에서는 `snap install k9s`가 운영 경로로 적합하지 않아
최종적으로 `snap` 기반 설치를 제거합니다.

```bash
sudo snap remove k9s --purge
sudo snap remove lxd --purge
sudo snap remove core20 --purge
sudo snap remove snapd --purge
sudo apt purge snapd -y
sudo apt autoremove -y

sudo rm -rf /snap
sudo rm -rf /var/snap
sudo rm -rf /var/lib/snapd
rm -rf ~/snap
```

재부팅 후 확인:

```bash
systemctl status snapd
snap version
```

기대 결과:

- `systemctl status snapd`: `Unit snapd.service could not be found`
- `snap version`: `command not found`

## 11. 최종 상태

최종적으로 `vm-admin`은 아래 역할만 수행하도록 유지합니다.

- `kubectl`로 RKE2 원격 제어
- `helm`으로 패키지 배포 관리
- `mc`로 MinIO 원격 관리
- `k9s` 바이너리 사용
- 불필요한 `snap` 제거

즉, `vm-admin`은 애플리케이션 실행 노드가 아니라
운영 도구만 두는 관리 전용 VM입니다.

## 12. 성공 체크리스트

아래가 모두 되면 이 문서 기준 구성이 완료된 것입니다.

```bash
kubectl get nodes -o wide
kubectl get pods -A
helm version
k9s version
mc --version
mc alias list
```
