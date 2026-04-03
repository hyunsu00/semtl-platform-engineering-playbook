# K8s Troubleshooting

## 개요

이 문서는 Proxmox 기반 Kubernetes HA 설치/운영 중 자주 발생한 이슈와
복구 절차를 정리합니다.

## 1. `kubeadm init` timeout (VIP 선참조)

증상:

- `kubeadm init` 마지막 단계에서
  `timed out waiting for the condition`
- `journalctl -u kubelet`에
  `https://10.10.10.100:6443` 기준 `no route to host`
- `crictl ps -a`에는 `etcd`, `kube-apiserver`, `kube-controller-manager`,
  `kube-scheduler`가 `Running`

원인:

- `controlPlaneEndpoint`를 VIP(`10.10.10.100:6443`)로 먼저 설정했지만,
  아직 `kube-vip` static pod가 배포되지 않음
- bootstrap 시점의 kubelet과 `admin.conf`가 존재하지 않는 VIP로
  API 서버에 접속 시도

조치:

1. `cp1`만 초기화 중인 단계라면 `kubeadm reset -f`로 정리합니다.
2. `/var/lib/etcd`, `/etc/kubernetes/manifests`, `/etc/cni/net.d`
   잔여 파일을 정리합니다.
3. `kubeadm-init.yaml`의 `controlPlaneEndpoint`를
   `10.10.10.11:6443`로 변경합니다.
4. `certSANs`에는 VIP(`10.10.10.100`)를 유지한 채
   `kubeadm init`을 다시 수행합니다.
5. `kube-vip` 배포 후 `kubeconfig`와 `kubeadm-config`를
   VIP 기준으로 전환합니다.

핵심 명령:

```bash
sudo kubeadm reset -f
sudo rm -rf /etc/kubernetes/manifests/*
sudo rm -rf /var/lib/etcd
sudo rm -rf /etc/cni/net.d
sudo systemctl restart containerd
sudo systemctl restart kubelet
```

## 2. TLS SAN 오류 (VIP 접속 실패)

증상:

- `kubectl`이 VIP(`10.10.10.100`) 접속 시 x509 SAN 오류
- 예: `certificate is valid for ... not 10.10.10.100`

원인:

- `kubeadm init` 시 `controlPlaneEndpoint` 또는
  `apiServer.certSANs`에 VIP 누락

조치:

1. kubeconfig를 cp1 IP로 임시 전환합니다.
2. `kubeadm-config`에 `controlPlaneEndpoint: 10.10.10.100:6443`를 반영합니다.
3. `certSANs`에 cp1/cp2/cp3/VIP 모두 추가합니다.
4. apiserver 인증서를 삭제 후 재생성합니다.
5. kubeconfig를 VIP로 재전환합니다.

핵심 명령:

```bash
sudo sed -i "s#server: https://.*:6443#server: https://10.10.10.11:6443#g" \
  $HOME/.kube/config
kubectl -n kube-system get cm kubeadm-config \
  -o jsonpath='{.data.ClusterConfiguration}' > /tmp/kubeadm.yaml
sudo rm -f /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.key
sudo kubeadm init phase certs apiserver --config=/tmp/kubeadm.yaml
sudo touch /etc/kubernetes/manifests/kube-apiserver.yaml
sudo openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text | \
  grep -A1 "Subject Alternative Name"
```

## 3. Control Plane Join 시 etcd learner sync 실패

증상:

- join 중 `can only promote a learner member which is in sync with leader`

원인:

- VIP 경유 join 또는 내부망이 아닌 외부망 IP로 etcd peer 경로 형성

조치:

1. cp2/cp3 join은 `cp1`(`10.10.10.11:6443`) 기준으로 수행합니다.
2. JoinConfiguration에서 `localAPIEndpoint.advertiseAddress`를
   내부 IP로 지정합니다.
3. `node-ip`를 내부 IP로 고정합니다.

## 4. VIP 페일오버 실패

증상:

- 현재 VIP 보유 CP 종료 시 VIP 이동 없음

원인:

- `kube-vip` static pod가 cp1에만 배포됨

조치:

1. cp1/cp2/cp3 모두 `/etc/kubernetes/manifests/kube-vip.yaml`을 배포합니다.
2. `kube-vip` RBAC를 적용합니다.
3. 재테스트 후 VIP 이동을 확인합니다.

검증:

```bash
ip -br a | grep 10.10.10.100
kubectl -n kube-system get pods -o wide | grep kube-vip
```

## 5. reboot 후 kubelet crash (swap 재활성화)

증상:

- `running with swap on is not supported`

원인:

- `/swap.img` 잔존 또는 `/etc/fstab` 주석 미완료

조치 (모든 노드):

```bash
sudo swapoff -a
sudo sed -i '/swap/ s/^/# /' /etc/fstab
sudo rm -f /swap.img
swapon --show
sudo systemctl restart kubelet
```

## 6. kube-vip 실행 진단 실패 (crictl 소켓 문제)

증상:

- `crictl ps`로 `kube-vip` 컨테이너 조회 불가

원인:

- `crictl`이 dockershim 소켓으로 연결 시도

조치:

```bash
sudo tee /etc/crictl.yaml >/dev/null <<'EOF2'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF2
sudo crictl info | head
sudo crictl ps --name kube-vip
```

## 7. Cilium 초기 ImagePullBackOff

증상:

- Cilium 파드가 일시적으로 `ImagePullBackOff`

원인:

- 이미지 다운로드 중 일시 실패(`unexpected EOF`)

조치:

1. 즉시 재설치하지 말고 재시도 대기합니다.
2. 장기 지속 시 DNS/egress 네트워크를 점검합니다.

## 8. INTERNAL-IP가 외부망(192.168.0.x)으로 잡힘

증상:

- `kubectl get nodes -o wide`에서 `INTERNAL-IP`가
  `10.10.10.x`가 아닌 `192.168.0.x`

원인:

- kubelet이 첫 번째 NIC(`vmbr0`)를 우선 선택

조치:

1. 각 노드 `/etc/default/kubelet`에
   `KUBELET_EXTRA_ARGS=--node-ip=<10.10.10.x>`를 설정합니다.
2. `systemctl daemon-reload && systemctl restart kubelet`을 실행합니다.
3. `kubectl get nodes -o wide`에서 내부망 IP 반영을 확인합니다.

## 9. `netplan apply` 시 Open vSwitch 경고

증상:

- `sudo netplan apply` 실행 시 아래 경고가 출력됨
- `Cannot call Open vSwitch: ovsdb-server.service is not running.`

원인:

- netplan이 OVS 존재 여부를 확인하지만, 현재 설정은 `renderer: networkd`이며
  OVS를 사용하지 않음

조치:

- 해당 경고는 무시 가능합니다.
- 대신 실제 인터페이스가 의도대로 적용됐는지 확인합니다.

검증:

```bash
ip -br a
networkctl status
```

## 10. Ingress `EXTERNAL-IP`는 보이지만 `80/443` 연결 거부

증상:

- `kubectl -n ingress-nginx get svc ingress-nginx-controller`에서는
  `EXTERNAL-IP`가 정상 할당됨
- `nc -vz <EXTERNAL-IP> 80` 또는 `443` 결과가 `Connection refused`
- Synology Reverse Proxy 또는 외부 `curl`에서 `502 Bad Gateway`
- `kubectl -n ingress-nginx get pods -o wide`를 보면
  controller 파드가 특정 노드 1대에만 존재

원인:

- `ingress-nginx-controller` 서비스의 `externalTrafficPolicy`가 `Local`
- 실제 ingress controller endpoint가 일부 노드에만 존재
- MetalLB 또는 VIP가 endpoint가 없는 노드에서 응답하면
  `80/443` 연결이 거부될 수 있음

조치:

1. 현재 서비스 정책과 endpoint 위치를 확인합니다.
2. ingress controller replica가 1개이거나 일부 노드에만 있으면
   `externalTrafficPolicy`를 `Cluster`로 변경합니다.
3. 변경 후 `80/443` 연결과 Host 헤더 기반 응답을 다시 확인합니다.

핵심 명령:

```bash
kubectl -n ingress-nginx get svc ingress-nginx-controller -o wide
kubectl -n ingress-nginx describe svc ingress-nginx-controller
kubectl -n ingress-nginx get pods -o wide
kubectl -n ingress-nginx get endpoints ingress-nginx-controller
kubectl -n ingress-nginx patch svc ingress-nginx-controller \
  -p '{"spec":{"externalTrafficPolicy":"Cluster"}}'
nc -vz 192.168.0.200 80
nc -vz 192.168.0.200 443
curl -I -H 'Host: prometheus.semtl.synology.me' http://192.168.0.200
```

참고:

- `externalTrafficPolicy: Local`은 source IP 보존에는 유리하지만,
  endpoint가 없는 노드로 트래픽이 들어오면 연결 실패가 날 수 있습니다.
- 홈랩/단일 replica 환경에서는 `Cluster`가 더 안정적일 수 있습니다.

## 공통 진단 순서

1. `kubectl get nodes -o wide`
2. `kubectl get pods -A`
3. `systemctl status kubelet --no-pager`
4. `systemctl status containerd --no-pager`
5. etcd 헬스와 멤버 상태 확인

## 에스컬레이션 기준

- control-plane 과반수(`2/3`) 이상 비정상
- etcd 멤버 `started` 3개 미만 상태가 10분 이상 지속
- VIP/API 모두 접근 불가 상태가 10분 이상 지속

## 관련 문서

- [K8s Installation](./installation.md)
- [K8s Operation Guide](./operation-guide.md)
