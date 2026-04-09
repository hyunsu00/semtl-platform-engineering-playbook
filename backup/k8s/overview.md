# K8s Overview

## 목적

Proxmox 기반 Kubernetes HA 표준 구축/운영 기준을 정의합니다.

## 범위

- Proxmox VM 기반 Kubernetes 설치
- CNI, API HA, LoadBalancer, Ingress 구성
- 백업/복구 및 운영 점검
- 장애 진단 및 복구 절차

## 표준 구성

- OS: `Ubuntu 22.04 LTS`
- Kubernetes: `v1.29.x` (`kubeadm`)
- Runtime: `containerd`
- CNI: `Cilium v1.15.5`
- 내부 API HA: `kube-vip v0.8.2` (`10.10.10.100`)
- 외부 API HA: `CT-LB1/CT-LB2 + Keepalived + HAProxy` (`192.168.0.180`)
- LoadBalancer: `MetalLB` (`192.168.0.200-220`)
- Ingress: `ingress-nginx`
- Control Plane: 3노드(stacked etcd)
- Worker: 2노드
- 기본 리소스: `2/2/2/4/4 vCPU`, `6/6/6/8/8 GB RAM`

## 문서 목록

- [Installation](./installation.md): Proxmox VM 생성부터 HA 구성,
  설치 직후 검증, 초기 운영 기준까지 포함한 기준 문서
- [Operation Guide](./operation-guide.md): 통합된 설치 기준 문서 위치 안내
- [Troubleshooting](./troubleshooting.md): 실제 장애 패턴별 진단/조치 가이드

## API 엔드포인트 구분

- 내부 control-plane 엔드포인트:
  `10.10.10.100:6443` (`kube-vip`)
- 외부 운영 접속 엔드포인트:
  `192.168.0.180:6443` (`CT-LB1/CT-LB2 + Keepalived + HAProxy`)
- `vm-admin` 같은 운영 노드는 외부 운영 접속 엔드포인트를 사용합니다.
