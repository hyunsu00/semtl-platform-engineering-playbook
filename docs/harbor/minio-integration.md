# Harbor MinIO Integration

## 개요

이 문서는 Harbor 기본 설치 이후 이미지 저장소를 MinIO S3 backend로 연동하는 절차를 정의합니다.

## 사전 조건

- Harbor 기본 설치 완료
- MinIO 설치 및 동작 확인 완료
- MinIO endpoint: `http://192.168.0.171:9000` (예시)
- MinIO bucket(`harbor`) 및 Access/Secret Key 준비

## 설정 절차

### 1. Harbor 설정 파일 백업

```bash
cd ~/harbor/harbor
cp harbor.yml harbor.yml.bak.$(date -u +%Y%m%d%H%M%S)
```

### 2. `harbor.yml`에 S3 backend 반영

`storage_service`를 아래처럼 설정합니다.

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

### 3. Harbor 재적용

```bash
cd ~/harbor/harbor
sudo ./prepare
sudo docker compose down
sudo docker compose up -d
```

## 검증

```bash
# Harbor 컨테이너 상태 확인
sudo docker ps

# Harbor 접속 확인
curl -I https://harbor.semtl.synology.me
```

검증 기준:

- Harbor 로그인/프로젝트 접근 정상
- 이미지 push/pull 동작 정상
- MinIO bucket(`harbor`)에 오브젝트 생성 확인

## 롤백

```bash
cd ~/harbor/harbor
cp harbor.yml.bak.<timestamp> harbor.yml
sudo ./prepare
sudo docker compose down
sudo docker compose up -d
```
