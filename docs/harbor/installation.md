# Harbor Installation

## 개요

이 문서는 VM 기반 Harbor 설치와 MinIO S3 backend 연동 절차를 정의합니다.

## 사전 조건

- OS: Ubuntu 22.04 LTS
- 배치: VM 설치 (Kubernetes 배치 금지)
- 도메인: `harbor.semtl.synology.me`
- Reverse Proxy 경유 노출
- MinIO endpoint 준비 (`http://192.168.0.171:9000` 예시)

## 네트워크 기준

- `net0`: 외부 접근망 (`192.168.0.x`)
- `net1`: 내부 데이터망
- 예시 VM IP: `192.168.0.222`

## 설치 절차

### 1. Docker/Compose 설치

```bash
# Docker 설치
curl -fsSL https://get.docker.com | sh

# 현재 사용자 docker 그룹 추가
sudo usermod -aG docker $USER

# compose plugin 설치
sudo apt update
sudo apt install -y docker-compose-plugin
```

### 2. Harbor 오프라인 패키지 준비

```bash
# 작업 디렉터리 생성
mkdir -p ~/harbor
cd ~/harbor

# 예시: Harbor 설치 번들 다운로드(버전은 정책에 맞게 조정)
# curl -LO https://github.com/goharbor/harbor/releases/download/v2.13.2/harbor-offline-installer-v2.13.2.tgz
# tar -xzf harbor-offline-installer-v2.13.2.tgz
```

### 3. `harbor.yml` 설정

핵심 항목:

- `hostname: harbor.semtl.synology.me`
- HTTPS 인증서는 Reverse Proxy에서 종료
- storage service를 `s3`로 설정
- bucket: `harbor`

S3 예시:

```yaml
storage_service:
  s3:
    regionendpoint: http://192.168.0.171:9000
    accesskey: harbor
    secretkey: <minio-secret>
    bucket: harbor
    secure: false
    v4auth: true
    chunksize: 5242880
    rootdirectory: /
    storageclass: STANDARD
```

### 4. Harbor 설치 실행

```bash
# Harbor 설치 스크립트 실행
cd ~/harbor/harbor
sudo ./install.sh
```

## 방화벽/포트 체크

- VM 내부 포트: `80`, `443` (Reverse Proxy 연결 경로)
- MinIO endpoint 접근 가능 여부 확인 필요

## 설치 검증

```bash
# Harbor 컨테이너 상태
sudo docker ps

# 외부 URL 응답 확인
curl -I https://harbor.semtl.synology.me
```

검증 기준:

- 로그인 페이지 응답
- 이미지 프로젝트 생성 가능
- MinIO bucket(`harbor`)에 오브젝트 생성 확인

## 스냅샷 권장 시점

- 관리자 비밀번호 변경 후
- Robot account 생성 전
- OIDC 연동 전

권장 이름:

- `BASE-Harbor-Install`

## 참고

- GitLab Container Registry는 비활성 정책
- 이미지 저장소는 Harbor로 통일
