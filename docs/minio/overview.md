# MinIO Overview

## 목적
MinIO를 S3 Object Storage 표준 백엔드로 운영하기 위한 기준을 정의합니다.

## 적용 범위
- MinIO VM 구성 및 데이터 디스크 분리
- Harbor/GitLab의 Object Storage 연동 기반
- 운영 점검과 장애 대응 표준

## 권장 아키텍처
- OS 디스크와 데이터 디스크를 분리합니다.
- MinIO 데이터 경로는 `/data/minio`를 기본으로 사용합니다.
- TLS 종료는 Reverse Proxy에서 수행하고 MinIO는 내부망으로 노출합니다.

예시 구성:
- MinIO VM: `192.168.0.171`
- API endpoint: `http://192.168.0.171:9000`
- Console endpoint: `http://192.168.0.171:9001`

## 문서 맵
- 설치: [Installation](./installation.md)
- 운영 가이드: [Operation Guide](./operation-guide.md)
- 트러블슈팅: [Troubleshooting](./troubleshooting.md)
