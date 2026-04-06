# MinIO n8n Integration

## 개요

이 문서는 n8n에서 MinIO를 S3 호환 외부 바이너리 스토리지로 연동하는 절차를
정리한 참고 문서입니다. 주요 목적은 workflow 실행 중 생성되는
파일형 데이터(binary data)를 n8n 로컬 디스크가 아니라
MinIO bucket으로 분리하는 방법을 기록해 두는 것입니다.

중요:

- n8n의 S3 외부 바이너리 스토리지는 `Self-hosted Enterprise` 기능입니다.
- Community Edition만 사용하는 경우 이 문서의 S3 external storage 설정은 적용할 수 없습니다.
- 현재 운영 환경에는 n8n Enterprise 라이선스가 없으므로,
  이 문서는 실제 적용 가이드가 아니라 향후 Enterprise 도입 시 참고할 절차 문서로 유지합니다.
- 라이선스가 만료된 상태에서 S3 모드를 유지하면, n8n은 기존 데이터를 읽을 수는 있지만 새 데이터는 쓰지 못할 수 있습니다.

## 대상 환경

- MinIO API endpoint: `http://192.168.0.171:9000`
- MinIO public S3 endpoint: `https://s3.semtl.synology.me`
- n8n URL: `https://n8n.semtl.synology.me`
- n8n 배포 방식: `Docker Compose`
- n8n binary storage bucket: `n8n-binaries`
- n8n service account: `svc-n8n-s3`

## 사전 조건

- [MinIO 설치](./installation.md) 완료
- [n8n 설치](../n8n/installation.md) 완료
- n8n이 `Docker Compose`로 정상 기동 중
- n8n Enterprise license key 적용 가능 상태
- n8n VM에서 `~/n8n/.env`, `~/n8n/docker-compose.yml` 수정 가능
- 기본 설치 문서 기준의 `N8N_DIAGNOSTICS_ENABLED=false`가 이미 반영되어 있으면 더 깔끔합니다.

endpoint 선택 기준:

- n8n은 서버가 MinIO에 직접 접근하므로 내부 API endpoint만으로도 연동은 가능합니다.
- 기본 구성은 `192.168.0.171:9000` 같은 내부 MinIO API endpoint를 권장합니다.
- 내/외부 공용 DNS와 TLS 구성이 이미 준비되어 있으면
  `s3.semtl.synology.me` 같은
  공개 S3 API endpoint로 바꿀 수 있습니다.
- MinIO Console 도메인인 `https://minio.semtl.synology.me`는 n8n S3 host로 사용하지 않습니다.

## 연동 절차(Enterprise 도입 시 참고)

### 1. [MinIO VM] bucket 및 계정 준비

아래 명령은 `MinIO VM`에서 실행합니다.

```bash
# mc가 사용할 MinIO 접속 별칭(local) 등록
mc alias set local http://127.0.0.1:9000 <MINIO_ROOT_USER> '<MINIO_ROOT_PASSWORD>'

# n8n binary data 전용 bucket 생성
mc mb -p local/n8n-binaries

# n8n 전용 bucket 제한 정책 파일 생성
cat > /tmp/policy-n8n-s3.json <<'EOF'
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
        "arn:aws:s3:::n8n-binaries"
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
        "arn:aws:s3:::n8n-binaries/*"
      ]
    }
  ]
}
EOF

# n8n 전용 정책 등록
mc admin policy create local policy-n8n-s3 /tmp/policy-n8n-s3.json
# n8n 전용 서비스 계정 생성
mc admin user add local svc-n8n-s3 'replace-with-strong-password'
# n8n 계정에 n8n bucket 전용 정책 연결
mc admin policy attach local policy-n8n-s3 --user svc-n8n-s3
# 계정 생성 및 정책 연결 상태 확인
mc admin user info local svc-n8n-s3
```

운영 기준:

- n8n 전용 bucket은 `n8n-binaries`를 기본값으로 사용합니다.
- 계정 이름은 `svc-n8n-s3`로 통일합니다.
- 공용 `readwrite` 대신 `policy-n8n-s3`로 `n8n-binaries/*` 범위만 허용합니다.
- Console 포트(`9001`)가 아니라 S3 API 포트(`9000`)를 사용합니다.

### 2. [n8n VM] n8n 환경 변수 설정

아래 작업은 `n8n VM`의 `~/n8n/.env`에서 수행합니다.

`~/n8n/.env`에 아래 값을 추가합니다.

```bash
# n8n external binary storage(S3/MinIO)
N8N_DEFAULT_BINARY_DATA_MODE=s3
N8N_EXTERNAL_STORAGE_S3_HOST=192.168.0.171
N8N_EXTERNAL_STORAGE_S3_BUCKET_NAME=n8n-binaries
N8N_EXTERNAL_STORAGE_S3_BUCKET_REGION=us-east-1
N8N_EXTERNAL_STORAGE_S3_ACCESS_KEY=svc-n8n-s3
N8N_EXTERNAL_STORAGE_S3_ACCESS_SECRET=<minio-secret-key>
```

설정 기준:

- `N8N_DEFAULT_BINARY_DATA_MODE=s3`로 두면 새 binary data는 MinIO에 저장합니다.
- `N8N_EXTERNAL_STORAGE_S3_HOST`는 프로토콜 없이 host만 사용합니다.
- 기본값은 내부 MinIO API host인 `192.168.0.171`을 사용합니다.
- 공개 S3 API endpoint를 사용할 때는
  `s3.semtl.synology.me`처럼
  Console이 아닌 API 도메인을 사용합니다.
- provider가 region을 강제하지 않으면
  `N8N_EXTERNAL_STORAGE_S3_BUCKET_REGION=auto`도 사용할 수 있지만,
  현재 운영 기준은 `us-east-1`을 사용합니다.
- n8n 최신 버전 기준으로
  `N8N_AVAILABLE_BINARY_DATA_MODES`는 더 이상 필요하지 않습니다.
- `N8N_RUNNERS_ENABLED`는 이 연동과 무관하며 넣지 않습니다.
- S3 binary data storage를 사용하려면
  현재 인스턴스에 해당 기능을 포함한
  유효한 Enterprise license가 적용되어 있어야 합니다.

### 3. [n8n VM] Compose 파일 반영

아래 작업은 `n8n VM`의 `~/n8n/docker-compose.yml`에서 수행합니다.

기존 `n8n` 서비스 `environment`에 아래 값들이 `.env`에서 반영되도록 추가합니다.

```yaml
      - N8N_DEFAULT_BINARY_DATA_MODE=${N8N_DEFAULT_BINARY_DATA_MODE}
      - N8N_EXTERNAL_STORAGE_S3_HOST=${N8N_EXTERNAL_STORAGE_S3_HOST}
      - N8N_EXTERNAL_STORAGE_S3_BUCKET_NAME=${N8N_EXTERNAL_STORAGE_S3_BUCKET_NAME}
      - N8N_EXTERNAL_STORAGE_S3_BUCKET_REGION=${N8N_EXTERNAL_STORAGE_S3_BUCKET_REGION}
      - N8N_EXTERNAL_STORAGE_S3_ACCESS_KEY=${N8N_EXTERNAL_STORAGE_S3_ACCESS_KEY}
      - N8N_EXTERNAL_STORAGE_S3_ACCESS_SECRET=${N8N_EXTERNAL_STORAGE_S3_ACCESS_SECRET}
```

설정 기준:

- n8n은 환경 변수 기반으로 external storage를 읽으므로
  `.env`와 `docker-compose.yml` 양쪽이 일치해야 합니다.
- 설치 문서의 기본값인 `N8N_DIAGNOSTICS_ENABLED=false`는 그대로 유지합니다.
- `N8N_EXTERNAL_STORAGE_S3_AUTH_AUTO_DETECT=true`는 현재 구성에서는 사용하지 않습니다.
- 현재 n8n 설치 문서에서 `./n8n-files:/files` bind mount를
  이미 사용하고 있으므로,
  이후 검증 단계에서 `/files` 경로를 활용할 수 있습니다.

### 4. [n8n VM] n8n 재기동

아래 명령은 `n8n VM`에서 실행합니다.

```bash
cd ~/n8n
docker compose down
docker compose up -d
docker compose ps
docker compose logs --tail=100 n8n
```

확인 기준:

- `n8n` 컨테이너가 `Up` 상태인지 확인합니다.
- 기동 로그에 S3 external storage 관련 치명적 오류가 없는지 확인합니다.
- 환경 변수 변경 후에는 `docker compose down`으로
  기존 컨테이너를 내린 뒤 다시 기동하는 편이 안전합니다.
- 로그에 `S3 binary data storage requires a valid license`가 보이면
  MinIO 설정이 아니라 라이선스 상태를 먼저 점검합니다.
- 로그에 `N8N_RUNNERS_ENABLED` deprecation 경고가 보이면
  이전 설정이 남아 있는지 함께 점검합니다.

### 5. [n8n Web UI] binary data 검증 workflow 생성

권장 테스트 workflow:

- Workflow name: `minio-binary-storage-test`

사전 준비:

아래 명령은 `n8n VM`에서 실행합니다.

```bash
mkdir -p ~/n8n/n8n-files
echo 'hello-minio-from-n8n' > ~/n8n/n8n-files/minio-test.txt
```

따라가기:

1. n8n Web UI에서 `Create Workflow`를 클릭합니다.
2. 첫 노드로 `Manual Trigger`를 추가합니다.
3. 다음 노드로 `Read/Write Files from Disk`를 추가합니다.
4. Operation은 `Read File(s) From Disk`로 선택합니다.
5. File Selector에 `/files/minio-test.txt`를 입력합니다.
6. workflow를 저장합니다.
7. `Execute workflow`를 클릭합니다.
8. 실행 결과에서 binary data가 포함되었는지 확인합니다.

참고:

- 이 검증은 n8n 설치 문서의 `/files` bind mount를 활용합니다.
- workflow 실행 결과에 binary data가 포함되면,
  새 binary data는 MinIO bucket에 저장되어야 합니다.

### 6. 연동 검증

#### 6.1 [n8n Web UI] workflow 실행 결과 확인

확인 항목:

- workflow execution이 `success` 상태인지 확인합니다.
- `Read/Write Files from Disk` 노드 출력에 binary data가 포함되는지 확인합니다.

#### 6.2 [MinIO VM] bucket 오브젝트 확인

아래 명령은 `MinIO VM`에서 실행합니다.

```bash
# n8n bucket 오브젝트 확인
mc ls local/n8n-binaries
# n8n bucket 내부 구조 확인
mc tree local/n8n-binaries
# 테스트 파일명 검색
mc find local/n8n-binaries --name '*minio-test*'
```

검증 기준:

- n8n workflow 성공
- MinIO bucket `n8n-binaries`에 오브젝트 생성
- 경로에
  `workflows/<workflowId>/executions/<executionId>/binary_data/...`
  형태가 보이면 정상으로 봅니다.

## 운영 작업

### [MinIO VM] n8n 계정 비밀번호 변경

아래 명령은 `MinIO VM`에서 실행합니다.

```bash
# n8n 서비스 계정 비밀번호 갱신
mc admin user add local svc-n8n-s3 'replace-with-strong-password'
# 계정 상태 재확인
mc admin user info local svc-n8n-s3
```

이후 `n8n VM`의 `~/n8n/.env`에서
`N8N_EXTERNAL_STORAGE_S3_ACCESS_SECRET`를 같은 값으로 갱신하고
`docker compose up -d`를 다시 수행합니다.

### [MinIO VM] bucket lifecycle 권장

n8n 공식 문서 기준으로
S3 external storage의 binary data pruning은
S3 lifecycle 정책에 맡기는 방식을 권장합니다.

운영 기준:

- 장기 보관이 필요하지 않은 binary data는 bucket lifecycle로 자동 정리합니다.
- n8n binary data를 filesystem에서 S3로 전환한 뒤에는
  기존 filesystem 데이터가 별도로 남을 수 있으므로
  정리 정책을 분리해서 확인합니다.

## 트러블슈팅

### Community Edition이라 S3 external storage가 동작하지 않음

의미:

- n8n S3 external storage는 Enterprise 기능입니다.

확인 기준:

- Enterprise license key가 없는 경우,
  env를 넣어도 외부 바이너리 스토리지를
  정상적으로 사용할 수 없습니다.

로그 예시:

- `S3 binary data storage requires a valid license`
- `Either set N8N_DEFAULT_BINARY_DATA_MODE to something else,
  or upgrade to a license that supports this feature.`

### `mc admin user info`에서 `PolicyName`이 비어 있음

의미:

- MinIO 정책은 생성됐지만 `svc-n8n-s3` 계정에 실제 연결되지 않은 상태입니다.

확인 명령:

```bash
mc admin user info local svc-n8n-s3
```

수정 명령:

```bash
mc admin policy attach local policy-n8n-s3 --user svc-n8n-s3
mc admin user info local svc-n8n-s3
```

### n8n workflow는 성공했는데 MinIO bucket이 비어 있음

주요 원인:

- workflow가 실제 binary data를 생성하지 않음
- `N8N_DEFAULT_BINARY_DATA_MODE=s3`가 반영되지 않음
- `docker compose up -d` 이후 컨테이너가 새 env를 읽지 못함

확인 순서:

1. workflow 노드 출력에 binary data가 실제 포함됐는지 확인합니다.
2. `docker compose exec n8n env | grep N8N_EXTERNAL_STORAGE_S3`로
   환경 변수가 컨테이너 내부에 반영됐는지 확인합니다.
3. `docker compose logs --tail=200 n8n`에서 S3 external storage 오류가 있는지 확인합니다.
4. 새 execution으로 다시 검증합니다.

### deprecation 경고가 보임

로그 예시:

- `N8N_AVAILABLE_BINARY_DATA_MODES -> Remove this environment variable;
  it is no longer needed.`
- `N8N_RUNNERS_ENABLED -> Remove this environment variable; it is no longer needed.`

조치:

- `N8N_AVAILABLE_BINARY_DATA_MODES`는 `.env`와 `docker-compose.yml`에서 제거합니다.
- `N8N_RUNNERS_ENABLED`는 n8n 기본 설치 문서와 현재 Compose 설정에서 제거합니다.
- 수정 후 `docker compose down && docker compose up -d`로 재기동합니다.

### Python task runner 경고가 보임

로그 예시:

- `Failed to start Python task runner in internal mode.
  because Python 3 is missing from this system.`

의미:

- Python task runner 관련 경고이며 MinIO S3 binary storage 실패의 직접 원인은 아닙니다.

조치:

- MinIO binary storage 검증만 목적이면 우선 무시할 수 있습니다.
- Python Code node를 운영에서 사용할 계획이면
  n8n 공식 문서 기준으로 external mode task runner 구성을
  별도로 검토합니다.

### `Last session crashed`가 보임

의미:

- n8n이 이전 종료를 비정상 종료로 판단해 남기는 안내 메시지입니다.
- 직전 컨테이너 재시작, VM 재부팅,
  `docker kill`, OOM 종료가 있었으면
  한 번 정도는 자연스럽게 보일 수 있습니다.

조치:

- 현재 기동 로그에 `n8n ready on ::, port 5678`가 보이면
  이번 기동 자체는 성공한 것으로 봅니다.
- 반복해서 보이면
  `docker inspect n8n --format '{{.State.OOMKilled}} {{.State.ExitCode}}'`
  로 OOM 여부와 종료 코드를 확인합니다.
- 필요하면 `docker compose logs --tail=200 n8n`와
  `docker compose ps`로 직전 재기동 흔적을 함께 점검합니다.

### `telemetry.n8n.io` DNS 오류가 반복됨

로그 예시:

- `getaddrinfo ENOTFOUND telemetry.n8n.io`
- `[Rudder] error: Response error code: ENOTFOUND`

의미:

- n8n이 telemetry 전송을 시도했지만
  현재 VM 또는 컨테이너에서 외부 DNS 해석에 실패한 상태입니다.
- MinIO S3 binary storage 실패의 직접 원인은 아니며,
  편집기 접근과 기본 workflow 실행에는
  큰 영향이 없을 수 있습니다.

조치:

- 외부 telemetry가 불필요한 운영 환경이면
  `N8N_DIAGNOSTICS_ENABLED=false`를 `~/n8n/.env`와
  `docker-compose.yml` 환경 변수에 반영해 경고를 없앱니다.
- telemetry를 유지할 계획이면
  n8n VM 또는 컨테이너에서 외부 DNS가 가능한지
  `getent hosts telemetry.n8n.io` 또는
  `nslookup telemetry.n8n.io`로 확인합니다.
- 수정 후 `docker compose down && docker compose up -d`로 재기동합니다.

### 외부 S3 API 도메인으로 바꿨는데 연결이 안 됨

주요 원인:

- `s3.semtl.synology.me`가 MinIO Console이 아니라
  S3 API(`9000`)로 reverse proxy 되지 않음
- n8n VM 내부 DNS에서
  `s3.semtl.synology.me`가 정상 해석되지 않음
- TLS 인증서 신뢰 문제가 있음

확인 순서:

1. n8n VM에서
   `curl -I https://s3.semtl.synology.me/minio/health/live`
   로 응답을 확인합니다.
2. reverse proxy 대상이 `9001` Console이 아니라 `9000` S3 API인지 확인합니다.
3. 내부 DNS와 인증서 체인을 점검합니다.

## 주의사항

- 이 문서는 n8n binary data external storage 기준입니다.
- workflow, credential, execution 메타데이터는 계속 PostgreSQL에 저장됩니다.
- MinIO external storage를 켜더라도 n8n 데이터 백업 정책은 별도로 유지합니다.
