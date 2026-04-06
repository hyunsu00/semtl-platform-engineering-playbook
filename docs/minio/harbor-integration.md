# MinIO Harbor Integration

## 개요

이 문서는 MinIO를 Harbor의 외부 S3 backend로 연동하는 표준 절차를 정의합니다.
Harbor 설치를 끝낸 뒤 이미지 레이어와 아티팩트를 MinIO로 분리할 때 사용합니다.

## 대상 환경

- MinIO API endpoint: `http://192.168.0.171:9000`
- MinIO public S3 endpoint: `https://s3.semtl.synology.me`
- Harbor URL: `https://harbor.semtl.synology.me`
- Harbor storage bucket: `harbor`
- Harbor service account: `svc-harbor-s3`
- Reverse Proxy TLS 종료: Synology

## 사전 조건

- [MinIO 설치](./installation.md) 완료
- [Harbor 설치](../harbor/installation.md) 완료
- Harbor VM에서 `~/harbor/harbor.yml` 기준 운영
- MinIO root 또는 운영용 관리자 계정으로 `mc` 사용 가능

endpoint 선택 기준:

- Harbor는 내부/외부 Docker client가 blob push/pull에 관여하므로
  `https://s3.semtl.synology.me` 같은 공개 S3 API endpoint를
  권장합니다.
- MinIO Console 도메인인 `https://minio.semtl.synology.me`는
  Harbor `regionendpoint`로 사용하지 않습니다.

## 연동 순서

### 1. [MinIO VM] bucket 및 계정 준비

아래 명령은 `MinIO VM`에서 실행합니다.

```bash
# mc가 사용할 MinIO 접속 별칭(local) 등록
mc alias set local http://127.0.0.1:9000 <MINIO_ROOT_USER> '<MINIO_ROOT_PASSWORD>'

# Harbor가 사용할 bucket 생성
mc mb -p local/harbor

# Harbor 전용 bucket 제한 정책 파일 생성
cat > /tmp/policy-harbor-s3.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::harbor"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::harbor/*"
      ]
    }
  ]
}
EOF

# Harbor 전용 정책 등록
mc admin policy create local policy-harbor-s3 /tmp/policy-harbor-s3.json
# Harbor 전용 서비스 계정 생성
mc admin user add local svc-harbor-s3 'replace-with-strong-password'
# Harbor 계정에 Harbor bucket 전용 정책 연결
mc admin policy attach local policy-harbor-s3 --user svc-harbor-s3
# bucket 생성 결과 확인
mc ls local/harbor
```

운영 기준:

- Harbor 전용 계정 `svc-harbor-s3`를 사용합니다.
- bucket은 `harbor` 단일 bucket으로 시작합니다.
- 공용 `readwrite` 대신 `policy-harbor-s3`로 `harbor/*` 범위만 허용합니다.

### 2. [Harbor VM] Harbor 설정 파일 백업

아래 명령은 `Harbor VM`에서 실행합니다.

```bash
# Harbor 설정 디렉터리로 이동
cd ~/harbor
# 롤백을 위해 현재 설정 백업
cp harbor.yml harbor.yml.bak.$(date -u +%Y%m%d%H%M%S)
```

### 3. `harbor.yml`에 S3 backend 반영

이 단계는 `Harbor VM`의 `~/harbor/harbor.yml`에서 작업합니다.

`storage_service`를 아래처럼 설정합니다.

```yaml
# Harbor 저장소는 기본적으로 로컬 파일시스템의 `/data` 디렉터리를 사용합니다.
# 현재 구성은 MinIO를 외부 S3 호환 스토리지로 사용하는 예시입니다.
storage_service:
  # ca_bundle:
  # 자체 서명 인증서를 사용하는 내부 S3 스토리지를 연결할 때
  # Registry 컨테이너 truststore에 주입할 루트 CA 인증서 경로입니다.
  # 지금 예시는 내부 HTTP endpoint 기준이므로 비워둡니다.
  ca_bundle:

  # s3:
  # Harbor 이미지/아티팩트를 MinIO bucket에 저장합니다.
  s3:
    # region:
    # Harbor registry가 요구하는 S3 region 값입니다.
    # MinIO 사용 시에도 반드시 넣어야 하며 일반적으로 `us-east-1`을 사용합니다.
    region: us-east-1
    # regionendpoint:
    # MinIO S3 API endpoint 입니다.
    # Console 도메인이 아니라 S3 API 도메인을 사용해야 합니다.
    regionendpoint: https://s3.semtl.synology.me
    # accesskey:
    # MinIO에 생성한 Harbor 전용 서비스 계정 ID 입니다.
    accesskey: svc-harbor-s3
    # secretkey:
    # 위 accesskey에 대응하는 MinIO 비밀번호입니다.
    secretkey: <minio-secret>
    # bucket:
    # Harbor가 오브젝트를 저장할 MinIO bucket 이름입니다.
    bucket: harbor
    # secure:
    # MinIO endpoint가 HTTPS면 true, HTTP면 false 입니다.
    secure: true
    # v4auth:
    # S3 Signature Version 4 인증 사용 여부입니다.
    v4auth: true
    # chunksize:
    # 멀티파트 업로드 시 사용할 청크 크기(byte)입니다.
    chunksize: 5242880
    # rootdirectory:
    # bucket 내부에서 Harbor 데이터가 저장될 시작 경로입니다.
    # `/`는 bucket 루트를 의미합니다.
    rootdirectory: /
    # storageclass:
    # 오브젝트 저장 클래스입니다.
    storageclass: STANDARD

  # redirect:
  # 내부/외부 Docker client를 함께 지원하려면
  # redirect를 비활성화하고 Harbor가 blob 다운로드를 프록시하도록 둡니다.
  redirect:
    disable: true
```

설정 기준:

- `regionendpoint`는 `https://s3.semtl.synology.me`처럼
  외부/내부에서 함께 접근 가능한 MinIO S3 API endpoint를
  사용합니다.
- `secure: true`는 HTTPS reverse proxy 기준입니다.
- Console 도메인이나 Console 포트(`9001`)를 넣지 않습니다.
- `bucket`, `accesskey`, `secretkey`는 MinIO에 생성한 값과 정확히 일치해야 합니다.
- 내부/외부 Docker client가 함께 Harbor를 통해 이미지를
  push/pull하는 환경이면 `redirect.disable: true`를 권장합니다.
- `redirect.disable: false`를 사용하려면 Docker client가
  MinIO S3 endpoint에 직접 도달할 수 있어야 합니다.
- 내부 VM에서도 `s3.semtl.synology.me`가 정상 해석되고
  TLS 인증서를 신뢰할 수 있어야 합니다.
- MinIO Console 도메인과 S3 API 도메인은 분리합니다.
  Harbor 연동에는 Console 도메인이 아니라
  S3 API 도메인을 사용해야 합니다.

### 4. [Harbor VM] Harbor 재적용

아래 명령은 `Harbor VM`에서 실행합니다.

```bash
# Harbor 설정 디렉터리로 이동
cd ~/harbor
# harbor.yml 기준으로 컨테이너 설정 재생성
sudo ./prepare
# 기존 컨테이너 중지
sudo docker compose down
# 변경된 설정으로 Harbor 재기동
sudo docker compose up -d
```

### 5. 연동 검증

#### 5.1 [Harbor VM] Harbor 상태 확인

아래 명령은 `Harbor VM`에서 실행합니다.

```bash
# Harbor 컨테이너 상태 확인
sudo docker ps

# Harbor 접속 확인
curl -I https://harbor.semtl.synology.me
```

#### 5.2 [Harbor VM 또는 Docker 가능한 작업용 호스트] test image push

아래 명령은 `Harbor VM` 또는 Docker CLI가 있는 작업용 호스트에서 실행합니다.
프로젝트 예시는 `library` 대신 운영 중인 프로젝트명(예: `devops`)으로 바꿔 사용해도 됩니다.

```bash
# Docker Hub에서 테스트용 이미지 pull
docker pull hello-world:latest

# Harbor 프로젝트 경로로 tag 변경
docker tag hello-world:latest harbor.semtl.synology.me/library/hello-world:minio-test

# Harbor 로그인
docker login harbor.semtl.synology.me

# Harbor로 이미지 push
docker push harbor.semtl.synology.me/library/hello-world:minio-test
```

#### 5.3 [MinIO VM] bucket 오브젝트 확인

아래 명령은 `MinIO VM`에서 실행합니다.

```bash
# MinIO bucket에 오브젝트가 생기는지 확인
mc ls local/harbor
# Harbor bucket 내부 구조를 트리 형태로 확인
mc tree local/harbor
```

검증 기준:

- Harbor 로그인 및 프로젝트 접근 정상
- `hello-world:minio-test` 이미지 push 성공
- Harbor UI에서 테스트 이미지 확인
- MinIO bucket `harbor`에 오브젝트 생성 확인

## 운영 작업

### [MinIO VM] Harbor 계정 비밀번호 변경

주의:

- MinIO는 기존 사용자 비밀번호의 평문 조회를 지원하지 않습니다.
- 현재 비밀번호를 모르면 확인이 아니라 재설정으로 처리합니다.
- 아래 명령은 `MinIO VM`에서 실행합니다.

```bash
# Harbor 서비스 계정 비밀번호 갱신
mc admin user add local svc-harbor-s3 'replace-with-strong-password'
```

이후 `Harbor VM`에서 `harbor.yml`의 `storage_service.s3.secretkey`를 같은 값으로 맞추고
`./prepare` 후 `docker compose up -d`를 다시 적용합니다.

### 점검 명령

#### [MinIO VM] 계정 및 bucket 점검

아래 명령은 `MinIO VM`에서 실행합니다.

```bash
# Harbor 서비스 계정 상태와 정책 확인
mc admin user info local svc-harbor-s3
# bucket 오브젝트 증가 여부 확인
mc ls local/harbor
```

#### [Harbor VM] Registry 로그 점검

아래 명령은 `Harbor VM`에서 실행합니다.

```bash
# Harbor registry 로그에서 S3 오류 확인
sudo docker logs --tail 100 registry
```

확인 항목:

- Harbor 계정이 `enabled` 상태인지 확인
- bucket에 새 아티팩트가 계속 기록되는지 확인
- Registry 로그에 S3 인증 오류가 없는지 확인
- Harbor storage credential과 MinIO 계정명이 일치하는지 확인

## 롤백

아래 명령은 `Harbor VM`에서 실행합니다.

```bash
# Harbor 설정 디렉터리로 이동
cd ~/harbor
# 백업해둔 설정 복원
cp harbor.yml.bak.<timestamp> harbor.yml
# 복원된 설정으로 컨테이너 설정 재생성
sudo ./prepare
# 기존 컨테이너 중지
sudo docker compose down
# 복원 설정으로 Harbor 재기동
sudo docker compose up -d
```

필요 시 MinIO 사용자 비활성화:

아래 명령은 `MinIO VM`에서 실행합니다.

```bash
# Harbor 서비스 계정 비활성화
mc admin user disable local svc-harbor-s3
```
