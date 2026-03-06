# MinIO Troubleshooting

## 개요
MinIO 설치/운영 중 자주 발생하는 문제와 해결 절차를 정리합니다.

## 1. `mc admin user add` 실행 시 Signature 오류
증상:
- `The request signature we calculated does not match the signature you provided`

원인:
- `mc alias`가 MinIO root 계정이 아닌 다른 계정으로 설정됨
- root 비밀번호 변경 후 구 alias 인증 정보가 stale 상태

해결:
1. root 계정 정보 확인
```bash
sudo egrep 'MINIO_ROOT_USER|MINIO_ROOT_PASSWORD' /etc/default/minio
```
2. alias 재설정
```bash
mc alias set local http://127.0.0.1:9000 <MINIO_ROOT_USER> '<MINIO_ROOT_PASSWORD>'
mc admin info local
```
3. 다시 사용자 비밀번호 갱신
```bash
mc admin user add local harbor 'replace-with-strong-password'
```

## 2. 단일 루트 디스크에 MinIO 데이터가 함께 저장됨
증상:
- OS와 MinIO 데이터가 같은 볼륨(`/`)에 누적됨

위험:
- Object 증가 시 루트 디스크 Full로 시스템 장애 유발 가능

해결:
- 데이터 디스크를 추가하고 `/data/minio`로 분리
- `fstab` 영구 마운트 설정 후 MinIO 데이터 경로 고정

## 3. Harbor 연동 후 Push/Pull 실패
점검 순서:
1. MinIO 계정(`accesskey`, `secretkey`)과 Harbor 설정 일치 여부 확인
2. `regionendpoint`와 `secure`, `s3forcepathstyle` 값 확인
3. Harbor 재적용(`./prepare`, `docker compose up -d`) 후 재시도

## 4. 서비스 기동 실패
점검:
```bash
sudo systemctl status minio --no-pager
sudo journalctl -u minio -n 200 --no-pager
```

주요 원인:
- `/etc/default/minio` 오타
- 데이터 경로 권한 불일치
- 포트 충돌(`9000`, `9001`)
