# K8s Overview

## 목적
Proxmox 기반 Kubernetes HA 표준 구축/운영 기준을 정의합니다.

## 범위
- Proxmox VM 기반 Kubernetes 설치
- CNI, API HA, LoadBalancer, Ingress 구성
- 백업/복구 및 운영 점검
- 장애 진단 및 복구 절차

## 표준 구성
- Kubernetes: `v1.29.x` (`kubeadm`)
- Runtime: `containerd`
- CNI: `Cilium v1.15.5`
- API HA: `kube-vip v0.8.2` (`10.10.10.100`)
- LoadBalancer: `MetalLB` (`192.168.0.200-220`)
- Ingress: `ingress-nginx`
- Control Plane: 3노드(stacked etcd)
- Worker: 2노드

## 문서 목록
- [Installation](./installation.md): Proxmox VM 생성부터 HA 구성 전체 설치 절차
- [Operation Guide](./operation-guide.md): 일상 점검, 변경, 백업/복구 운영 절차
- [Troubleshooting](./troubleshooting.md): 실제 장애 패턴별 진단/조치 가이드
