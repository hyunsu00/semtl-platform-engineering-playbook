# K8s Troubleshooting

## 개요
이 문서는 Proxmox 기반 Kubernetes HA 설치/운영 중 자주 발생한 이슈와 복구 절차를 정리합니다.

## 1. TLS SAN 오류 (VIP 접속 실패)
증상:
- `kubectl`이 VIP(`10.10.10.100`) 접속 시 x509 SAN 오류
- 예: `certificate is valid for ... not 10.10.10.100`

원인:
- `kubeadm init` 시 `controlPlaneEndpoint` 또는 `apiServer.certSANs`에 VIP 누락

조치:
1. kubeconfig를 cp1 IP로 임시 전환
2. `kubeadm-config`에 `controlPlaneEndpoint: 10.10.10.100:6443` 반영
3. `certSANs`에 cp1/cp2/cp3/VIP 모두 추가
4. apiserver 인증서 삭제 후 재생성
5. kubeconfig를 VIP로 재전환

핵심 명령:
```bash
sudo sed -i "s#server: https://.*:6443#server: https://10.10.10.11:6443#g" $HOME/.kube/config
kubectl -n kube-system get cm kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' > /tmp/kubeadm.yaml
sudo rm -f /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.key
sudo kubeadm init phase certs apiserver --config=/tmp/kubeadm.yaml
sudo touch /etc/kubernetes/manifests/kube-apiserver.yaml
sudo openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text | grep -A1 "Subject Alternative Name"
```

## 2. Control Plane Join 시 etcd learner sync 실패
증상:
- join 중 `can only promote a learner member which is in sync with leader`

원인:
- VIP 경유 join 또는 내부망이 아닌 외부망 IP로 etcd peer 경로 형성

조치:
1. cp2/cp3 join은 cp1(`10.10.10.11:6443`) 기준으로 수행
2. JoinConfiguration에서 `localAPIEndpoint.advertiseAddress`를 내부 IP로 지정
3. `node-ip`를 내부 IP로 고정

## 3. VIP 페일오버 실패
증상:
- 현재 VIP 보유 CP 종료 시 VIP 이동 없음

원인:
- kube-vip static pod가 cp1에만 배포됨

조치:
1. cp1/cp2/cp3 모두 `/etc/kubernetes/manifests/kube-vip.yaml` 배포
2. kube-vip RBAC 적용
3. 재테스트 후 VIP 이동 확인

검증:
```bash
ip -br a | grep 10.10.10.100
kubectl -n kube-system get pods -o wide | grep kube-vip
```

## 4. reboot 후 kubelet crash (swap 재활성화)
증상:
- `running with swap on is not supported`

원인:
- `/swap.img` 잔존 또는 `/etc/fstab` 주석 미완료

조치 (모든 노드):
```bash
sudo swapoff -a
sudo sed -i '/swap/ s/^/#/' /etc/fstab
sudo rm -f /swap.img
swapon --show
sudo systemctl restart kubelet
```

## 5. kube-vip 실행 진단 실패 (crictl 소켓 문제)
증상:
- `crictl ps`로 kube-vip 컨테이너 조회 불가

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

## 6. Cilium 초기 ImagePullBackOff
증상:
- Cilium 파드가 일시적으로 `ImagePullBackOff`

원인:
- 이미지 다운로드 중 일시 실패(unexpected EOF)

조치:
1. 즉시 재설치하지 말고 재시도 대기
2. 장기 지속 시 DNS/egress 네트워크 점검

## 공통 진단 순서
1. `kubectl get nodes -o wide`
2. `kubectl get pods -A`
3. `systemctl status kubelet --no-pager`
4. `systemctl status containerd --no-pager`
5. etcd 헬스/멤버 상태 확인

## 에스컬레이션 기준
- control-plane 과반수(`2/3`) 이상 비정상
- etcd 멤버 `started` 3개 미만 상태가 10분 이상 지속
- VIP/API 모두 접근 불가 상태가 10분 이상 지속

## 관련 문서
- [K8s Installation](./installation.md)
- [K8s Operation Guide](./operation-guide.md)
