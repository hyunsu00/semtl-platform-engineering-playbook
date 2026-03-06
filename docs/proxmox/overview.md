# Proxmox Overview

## 목적

이 문서는 Proxmox 기반 DevOps 인프라의
구성 원칙과 구축 순서를 정의합니다.

## 기준 아키텍처

- 상태 저장 서비스: VM에 배치
- 변동 부하 서비스: Kubernetes에 배치
- 외부 노출: Synology Reverse Proxy 단일 진입점
- 외부 접근망: `net0` (`192.168.0.x`)
- 내부 데이터망: `net1`

## 구축 순서 (고정)

1. MinIO VM 생성/설치
2. GitLab VM 생성/Omnibus 설치
3. Harbor VM 생성/Docker Compose 설치
4. Kubernetes에 GitLab Runner 설치
5. Kubernetes에 Jenkins 설치
6. Synology Reverse Proxy 라우팅 구성

## 설계 제약

- GitLab을 CT로 설치하지 않음
- Harbor를 Kubernetes에 설치하지 않음
- Runner를 CT로 설치하지 않음
- 별도 Edge Nginx를 추가하지 않음

## VM 기준 배치

- MinIO: `192.168.0.171`
- GitLab: `192.168.0.221`
- Harbor: `192.168.0.222`
- Jenkins: Kubernetes LoadBalancer IP (`192.168.0.20X`)

## 문서 매핑

- Proxmox 배치 원칙: 이 문서
- GitLab 설치 상세: `docs/gitlab/installation.md`
- Harbor 설치 상세: `docs/harbor/installation.md`
- Jenkins 설치 상세: `docs/jenkins/installation.md`
- Kubernetes 운영: `docs/k8s/operation-guide.md`
