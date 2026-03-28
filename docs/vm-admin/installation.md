# VM-ADMIN Installation

## 문서 목적

이 문서는 `vm-admin`를 운영 전용 관리 노드로 구성하면서 실제로 성공한 절차만 정리한 기록입니다. 아래 항목만 확인되었습니다.

- `kubectl` 설치 및 Kubernetes 원격 제어 성공
- `mc` 설치 및 MinIO(`192.168.0.171`) 관리 성공
- `k9s`는 바이너리 방식 사용, `snap` 기반 설치는 운영 경로에서 제외

실패했던 시도나 중간 가설은 제외하고, 최종적으로 동작이 확인된 흐름만 남깁니다.

## 구성 요약

- 관리 노드: `vm-admin`
- VM-ADMIN 네트워크:
  - 외부망 NIC 1개
  - `192.168.0.x` 대역으로만 직접 접근
- Kubernetes Control Plane:
  - `192.168.0.181`
  - `192.168.0.182`
  - `192.168.0.183`
  - 각 노드는 외부망/내부망 NIC 2개 구성
- Kubernetes Worker:
  - `192.168.0.191`
  - `192.168.0.192`
- Kubernetes 내부 API 접근망:
  - `10.10.10.11:6443`
  - Control Plane 내부 통신용
- MinIO:
  - API: `http://192.168.0.171:9000`
  - Console: `http://192.168.0.171:9001`

## 1. kubectl 설치

`vm-admin`에서 `kubectl`은 공식 Kubernetes apt 저장소로 설치했습니다.

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

직접 `scp`로 `/etc/kubernetes/admin.conf`를 가져오면 권한 문제로
실패했습니다. 성공한 방식은 Control Plane 1번 노드에서 임시 파일을
만든 뒤 `vm-admin`으로 복사하는 절차입니다.

### 2.1 CP1에서 임시 파일 준비

CP1(`192.168.0.181`)에 접속해서 아래를 실행합니다.

```bash
sudo -i
install -m 600 /etc/kubernetes/admin.conf /home/semtl/admin.conf
chown semtl:semtl /home/semtl/admin.conf
exit
```

### 2.2 VM-ADMIN으로 kubeconfig 복사

`vm-admin`에서 아래를 실행합니다.

```bash
mkdir -p ~/.kube
scp semtl@192.168.0.181:/home/semtl/admin.conf ~/.kube/config
chmod 600 ~/.kube/config
```

### 2.3 CP1 임시 파일 정리

복사가 끝나면 CP1에서 임시 파일을 삭제합니다.

```bash
rm -f /home/semtl/admin.conf
```

## 3. kubeconfig 서버 주소 확인

초기 kubeconfig에는 내부망 API 주소가 포함될 수 있습니다.

```bash
cat ~/.kube/config | grep server
```

예시:

```text
server: https://10.10.10.11:6443
```

운영 기준에서는 이 값을 그대로 사용하면 안 됩니다.

- `vm-admin`: 외부망 NIC 1개
- K8s Control Plane/Worker: 외부망 `192.168.0.x` + 내부망 `10.10.10.x`

따라서 `vm-admin`은 외부망 `192.168.0.x`를 통해
Control Plane API에 접근해야 합니다.

`2.3` 이후 `kubectl` 접속에 문제가 발생하면
[Kubernetes Installation](../k8s/installation.md)을 참고해
API 접근 경로 또는 apiserver SAN을 먼저 재설정해야 합니다.

재설정이 끝나면 `vm-admin`의 kubeconfig를 먼저 백업한 뒤
`server:` 값을 외부 운영 접속 VIP로 변경해야 합니다.

### 3.1 kubeconfig 백업 및 server 변경

```bash
cp ~/.kube/config ~/.kube/config.bak
sed -i \
  's#server: https://10\.10\.10\.11:6443#server: https://192.168.0.180:6443#g' \
  ~/.kube/config
grep server ~/.kube/config
kubectl get nodes -o wide
```

운영 기준으로는 `192.168.0.180:6443` 같은 외부망 VIP를 사용해야 합니다.

## 4. kubectl 동작 검증

```bash
kubectl get nodes -o wide
```

Control Plane이 내부망 IP를 `INTERNAL-IP`로 표시하는 것은 정상입니다.
향후 외부망 SAN 또는 외부망 VIP 구성을 마친 뒤 `vm-admin`이 외부망 API로
접속하더라도, 노드 정보에는 클러스터 내부 통신망인 `10.10.10.x`가
출력될 수 있습니다.

확인된 결과 예시:

- `k8s-cp1`: `Ready`, `control-plane`, `10.10.10.11`, `v1.29.15`
- `k8s-cp2`: `Ready`, `control-plane`, `10.10.10.12`, `v1.29.15`
- `k8s-cp3`: `Ready`, `control-plane`, `10.10.10.13`, `v1.29.15`
- `k8s-w1`: `Ready`, `10.10.10.21`, `v1.29.15`
- `k8s-w2`: `Ready`, `10.10.10.22`, `v1.29.15`
- 공통 OS: `Ubuntu 22.04.5 LTS`
- 공통 Runtime: `containerd://1.7.28`

위 결과는 클러스터 자체가 정상 동작하고 있음을 보여주는 예시입니다.
`vm-admin`에서 외부망 API로 정상 접속하려면 외부망 주소가 apiserver
인증서 SAN에 포함되어 있어야 합니다.

## 5. MinIO 관리용 mc 설치

MinIO 서버는 별도 VM(`192.168.0.171`)에 두고, `vm-admin`에는
관리 클라이언트 `mc`만 설치했습니다.

```bash
curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o mc
chmod +x mc
sudo mv mc /usr/local/bin/
mc --version
```

## 6. MinIO alias 등록

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

위 절차로 `vm-admin`에서 MinIO 관리 연결이 성공했습니다.

## 7. 운영 편의 설정

`kubectl`과 `mc`를 자주 사용하는 운영 노드이므로 아래 alias를 적용했습니다.

```bash
echo 'alias k=kubectl' >> ~/.bashrc
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
echo 'alias m=mc' >> ~/.bashrc
source ~/.bashrc
```

## 8. Helm 설치

`vm-admin`은 Kubernetes 운영 전용 노드이므로 `helm`도 함께 설치해야 합니다.

```bash
curl -fsSL \
  https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
  | bash
helm version
```

## 9. k9s 설치

`snap` 설치 방식은 명령 노출 문제가 있어,
최종적으로는 바이너리 설치본을 사용하는 방향으로 정리해야 합니다.

예시:

```bash
K9S_VERSION="v0.50.18"
curl -fsSL -o /tmp/k9s_linux_amd64.tar.gz \
  "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_linux_amd64.tar.gz"
tar -xzf /tmp/k9s_linux_amd64.tar.gz -C /tmp
sudo install -m 0755 /tmp/k9s /usr/local/bin/k9s
k9s version
```

## 10. k9s 및 snap 정리

이 환경에서는 `snap install k9s` 자체는 성공 메시지가 나왔지만,
`/snap/bin/k9s`가 정상 노출되지 않아 운영 경로로는 적합하지 않았습니다.

최종적으로 확인된 방향은 다음과 같습니다.

- `k9s`는 바이너리 직접 설치본 사용
- `snap` 기반 `k9s`는 제거
- 관리 전용 노드 특성상 `snap` 자체도 정리

`snap` 제거 절차:

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

최종적으로 `vm-admin`은 아래 역할만 수행하도록 정리했습니다.

- `kubectl`로 Kubernetes 원격 제어
- `helm`으로 패키지 배포 관리
- `mc`로 MinIO 원격 관리
- `k9s` 바이너리 사용
- 불필요한 `snap` 제거

즉, `vm-admin`은 애플리케이션 실행 노드가 아니라 운영 도구만 두는 관리 전용 VM으로 유지합니다.

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
