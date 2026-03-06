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

## 5. `No valid configuration found for 'myminio' host alias`
증상:
- `mc admin policy list myminio` 실행 시 alias 관련 오류 발생

원인:
- `myminio` alias 미등록
- alias가 MinIO Console(`9001`)로 등록됨

해결:
```bash
# S3 API endpoint(9000)로 alias 등록
mc alias set myminio http://127.0.0.1:9000 <MINIO_ROOT_USER> '<MINIO_ROOT_PASSWORD>'
mc alias ls
mc admin info myminio
```

## 6. OIDC 로그인 후 정책 권한이 적용되지 않음
증상:
- Keycloak 로그인은 성공하지만 MinIO 권한이 기대와 다름
- 토큰에 `policy` claim이 없음

원인:
- Keycloak User Profile 스키마에 `policy` attribute 정의가 없음
- 사용자 `policy` 값 미입력 또는 mapper 미구성

해결:
1. Keycloak `Realm settings -> User profile`에서 `policy` attribute 생성
2. `Who can view/edit`에 최소 `Admin` 권한 부여
3. 사용자 `Details`에서 `policy=readwrite` 입력
4. Client mapper가 `policy`를 토큰 claim으로 내보내는지 확인
