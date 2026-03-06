# MinIO Operation Guide

## 개요
MinIO 운영 점검, 계정/버킷 관리, Harbor 연동 변경 절차를 정의합니다.

## 운영 기준
- endpoint: `http://192.168.0.171:9000`
- console: `http://192.168.0.171:9001`
- data path: `/data/minio`
- 주요 사용처: Harbor, GitLab object storage

## 일일 점검
```bash
sudo systemctl is-active minio
curl -sS http://127.0.0.1:9000/minio/health/live
mc admin info local
```

확인 항목:
- 서비스 상태 정상
- Health endpoint 응답 정상
- 디스크 사용률 임계치 이하

## 버킷/계정 운영 예시
```bash
# alias 설정
mc alias set local http://127.0.0.1:9000 <MINIO_ROOT_USER> '<MINIO_ROOT_PASSWORD>'

# bucket 생성 예시
mc mb local/harbor

# 사용자 생성 또는 비밀번호 갱신(기존 사용자면 덮어씀)
mc admin user add local harbor 'replace-with-strong-password'
```

## Harbor 연동 계정 비밀번호 변경 절차
1. MinIO에서 사용자 비밀번호 갱신
```bash
mc admin user add local harbor 'replace-with-strong-password'
```
2. Harbor VM의 `harbor.yml`에서 `storage_service.s3.secretkey`를 동일 값으로 변경
3. Harbor 재적용
```bash
cd ~/harbor
sudo ./prepare
docker compose up -d
```
4. 이미지 push/pull로 연동 검증

## 용량 관리 기준
- `/data` 사용률 `70%` 초과 시 정리 계획 수립
- `/data` 사용률 `85%` 초과 시 즉시 확장 또는 정리 실행
- 정기적으로 미사용 아티팩트/오브젝트 정리
