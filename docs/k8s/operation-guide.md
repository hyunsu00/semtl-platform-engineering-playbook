# K8s Operation Guide

## 개요
이 문서는 `docs/k8s/installation.md` 기준으로 구축된 Proxmox Kubernetes HA 클러스터의 운영 절차를 정의합니다.

## 일일 점검
```bash
# 노드 상태(Ready), 내부 IP, 런타임 정보를 확인
kubectl get nodes -o wide

# 전체 네임스페이스 파드 상태를 점검
kubectl get pods -A

# 최신 이벤트 50건으로 장애 징후를 확인
kubectl get events -A --sort-by=.metadata.creationTimestamp | tail -n 50
```

확인 항목:
- 모든 노드 `Ready`
- `kube-system`, `metallb-system`, `ingress-nginx` 주요 파드 `Running`
- 반복 `CrashLoopBackOff`/`ImagePullBackOff` 발생 여부

## 주간 점검
### etcd 상태
```bash
# etcd endpoint 응답 정상 여부를 확인
sudo ETCDCTL_API=3 etcdctl \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  --endpoints=https://127.0.0.1:2379 \
  endpoint health

# etcd 멤버 수와 상태(started)를 확인
sudo ETCDCTL_API=3 etcdctl \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  --endpoints=https://127.0.0.1:2379 \
  member list
```

### VIP 상태
```bash
# VIP가 현재 어느 노드에 붙어 있는지 확인
ip -br a | grep 10.10.10.100

# kube-vip 파드가 정상 동작 중인지 확인
kubectl -n kube-system get pods -o wide | grep kube-vip
```

### 노드 IP 정합성
```bash
# 노드 INTERNAL-IP가 내부망(10.10.10.x) 기준인지 확인
kubectl get nodes -o wide
```

### 백업 상태
```bash
# etcd 백업 타이머의 활성/다음 실행 시각을 확인
systemctl list-timers | grep etcd-backup

# 최근 백업 파일 생성 여부와 용량을 확인
ls -lh /var/backups/etcd | tail -n 10
```

### 용량/압력 점검
```bash
# 노드별 CPU/메모리 사용량을 확인
kubectl top nodes

# 상위 파드 리소스 사용량을 빠르게 확인
kubectl top pods -A | head -n 30

# 노드 압력 상태(Memory/Disk/PID)와 Ready 조건을 확인
kubectl describe node k8s-w1 | egrep -i 'MemoryPressure|DiskPressure|PIDPressure|Ready'
```

## 월간 점검
### HA 페일오버 테스트
1. 현재 VIP 보유 노드 확인
2. 해당 CP 노드를 종료
3. 10~30초 내 VIP 이동 확인
4. API 응답/노드 상태 정상 확인

확인 명령:
```bash
# VIP가 다른 control-plane 노드로 이동했는지 확인
ip -br a | grep 10.10.10.100

# API 엔드포인트 응답 상태를 확인
kubectl cluster-info

# 페일오버 후 노드 상태를 확인
kubectl get nodes
```

### 인증서 만료 점검
```bash
# control-plane 인증서 만료 예정일을 확인
sudo kubeadm certs check-expiration
```

만료 임박 시(예: 30일 이내) 갱신:
```bash
# kubeadm 관리 인증서를 일괄 갱신
sudo kubeadm certs renew all

# 갱신 반영을 위해 kubelet 재시작
sudo systemctl restart kubelet
```

## 변경 작업 표준
1. 작업 전 etcd 스냅샷 수동 생성
2. 변경 대상/영향 노드 명시
3. 단일 변경 단위 적용 후 상태 확인
4. 이상 시 즉시 롤백

수동 etcd 백업:
```bash
# etcd 백업 서비스를 즉시 1회 실행
sudo systemctl start etcd-backup.service

# 방금 생성된 백업 파일을 확인
ls -lh /var/backups/etcd | tail -n 5
```

## 노드 유지보수 절차
### Worker 노드
```bash
# 워커 노드를 드레인하여 유지보수 상태로 전환
kubectl drain <worker-node> --ignore-daemonsets --delete-emptydir-data

# 점검/패치/재부팅 수행

# 유지보수 완료 후 스케줄링 재개
kubectl uncordon <worker-node>

# 노드가 Ready,SchedulingEnabled인지 확인
kubectl get nodes
```

### Control Plane 노드
1. 한 번에 1대만 작업
2. 작업 전 etcd 헬스와 멤버 상태 확인
3. 작업 후 `Ready` 복귀 확인 후 다음 노드 진행

참고 명령:
```bash
# control-plane 포함 전체 노드 상태를 확인
kubectl get nodes -o wide

# etcd 쿼럼 유지 여부(3개 started)를 확인
sudo ETCDCTL_API=3 etcdctl \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  --endpoints=https://127.0.0.1:2379 \
  member list
```

## 업그레이드 운영 원칙
1. 대상 버전 호환성 확인 (`kubeadm`/`kubelet`/Cilium)
2. cp1 -> cp2 -> cp3 -> worker 순서로 단계 업그레이드
3. 각 단계마다 `kubectl get nodes`, `kubectl get pods -A` 검증
4. 장애 발생 시 즉시 중단하고 직전 안정 버전으로 롤백

사전 확인:
```bash
# 현재 kubeadm 버전을 확인
kubeadm version

# 클러스터/클라이언트 버전 차이를 확인
kubectl version --short

# 현재 Cilium 이미지 태그를 확인
kubectl -n kube-system get ds cilium -o jsonpath='{.spec.template.spec.containers[0].image}'
```

## 복구 기본 절차
1. 증상 노드와 영향 범위 확인
2. `kubelet`, `containerd` 상태 확인
3. `kube-system` 핵심 파드 상태 확인
4. etcd 멤버/헬스 확인
5. 필요 시 [Troubleshooting](./troubleshooting.md) 절차 적용

## 백업 복구 리허설 (분기 1회 권장)
1. 최신 etcd snapshot 파일 선택
2. 격리 테스트 VM/랩 환경에서 복구 리허설 수행
3. API 서버 기동/노드 인식/핵심 네임스페이스 확인
4. 리허설 결과와 소요 시간 기록

## 채팅 재시작용 핸드오프 템플릿
긴 작업을 새 채팅으로 이어갈 때는 아래 템플릿으로 현재 상태를 전달합니다.

```md
# Proxmox Kubernetes HA 작업 재개

## 현재 상태
- 노드 구성: `cp1/cp2/cp3/w1/w2`
- 권장 vCPU: `2,2,2,4,4`
- cp1 `kubeadm init` 완료
- kube-vip 적용 완료
- 현재 시작 지점: kube-vip 문제 해결

## 먼저 점검할 항목
1. VIP 바인딩 확인: `ip a | grep <VIP>`
2. API 응답 확인: `curl -k https://<VIP>:6443`
3. kube-vip 상태 확인: `kubectl -n kube-system get pods -o wide | grep vip`
4. kube-vip 로그 확인: `kubectl -n kube-system logs <kube-vip-pod>`

## 다음 진행 순서
1. kube-vip 정상화
2. cp2/cp3 조인
3. worker 조인
4. CNI/핵심 파드 상태 확인
5. 전체 Ready 확인 후 스냅샷 생성
```

중복 방지 원칙:
- 상세 설치 명령은 [K8s Installation](./installation.md)만 기준으로 유지합니다.
- 장애 조치는 [K8s Troubleshooting](./troubleshooting.md) 링크로만 참조합니다.

## 운영 시 금지사항
- swap 재활성화 상태로 운영 금지
- control-plane join을 VIP 경유로 수행 금지
- kube-vip를 단일 CP에만 배포하는 구성 금지
- `kubeadm-config` 수정 후 검증 없는 배포 금지
- control-plane 다중 노드 동시 재부팅 금지
- 노드 `INTERNAL-IP`가 외부망(`192.168.0.x`)으로 잡힌 상태 방치 금지
