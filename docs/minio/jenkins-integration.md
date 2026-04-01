# MinIO Jenkins Integration

## 개요

이 문서는 Jenkins에서 MinIO를 S3 호환 스토리지로 연동하는 표준 절차를 정의합니다.
주요 목적은 빌드 산출물과 아카이브를 Controller 로컬 디스크가 아닌 MinIO bucket으로 분리하는 것입니다.

## 대상 환경

- MinIO API endpoint: `http://192.168.0.171:9000`
- Jenkins URL: `https://jenkins.semtl.synology.me`
- Jenkins 플러그인: `aws-credentials`, `artifact-manager-s3`, `pipeline-utility-steps`
- CI service account: `svc-ci-artifact`

## 사전 조건

- [MinIO 설치](./installation.md) 완료
- [Jenkins 설치](../jenkins/installation.md) 완료
- Jenkins 주요 플러그인 설치 완료
- Jenkins 관리자 계정 준비

## 연동 순서

### 1. MinIO bucket 및 계정 준비

```bash
# mc가 사용할 MinIO 접속 별칭(local) 등록
mc alias set local http://127.0.0.1:9000 <MINIO_ROOT_USER> '<MINIO_ROOT_PASSWORD>'

# CI artifact 전용 bucket 생성
mc mb -p local/ci
# CI 전용 서비스 계정 생성
mc admin user add local svc-ci-artifact 'replace-with-strong-password'
# CI 계정에 읽기/쓰기 권한 부여
mc admin policy attach local readwrite --user svc-ci-artifact
# 계정 생성 및 정책 연결 상태 확인
mc admin user info local svc-ci-artifact
```

운영 기준:

- Jenkins/CI 전용 bucket은 `ci`를 기본값으로 사용합니다.
- 계정 이름은 `svc-ci-artifact`로 통일합니다.
- Console 포트(`9001`)가 아니라 S3 API 포트(`9000`)를 사용합니다.

### 2. Jenkins Credentials 등록

Jenkins UI 경로:

`Manage Jenkins -> Credentials -> System -> Global credentials -> Add Credentials`

입력 기준:

- Kind: `AWS Credentials`
- ID: `minio-s3`
- Access Key ID: `svc-ci-artifact`
- Secret Access Key: `<minio-secret-key>`
- Description: `MinIO S3 for Jenkins artifacts`

### 3. Artifact Manager on S3 설정

Jenkins UI 경로:

`Manage Jenkins -> System -> Artifact Management for Builds`

설정 예시:

- Provider: `Amazon S3`
- Bucket: `ci`
- Region: `us-east-1`
- Credentials: `minio-s3`
- Endpoint URL: `http://192.168.0.171:9000`
- Path Style Access Enabled: `ON`
- Delete Artifacts: 운영 정책에 맞게 선택

설정 기준:

- Endpoint는 내부 MinIO API 주소를 사용합니다.
- `Path Style Access`를 반드시 켭니다.
- TLS를 Reverse Proxy에서 끝내지 않는 내부망 기준이므로 `http://`를 사용합니다.

### 4. Pipeline 검증

테스트용 Pipeline 예시:

```groovy
pipeline {
  agent any
  stages {
    stage('build') {
      steps {
        sh 'mkdir -p dist && echo hello-minio > dist/result.txt'
        archiveArtifacts artifacts: 'dist/*.txt', fingerprint: true
      }
    }
  }
}
```

### 5. 연동 검증

```bash
# CI bucket 오브젝트 확인
mc ls local/ci
# 업로드된 artifact 파일 검색
mc find local/ci --name '*.txt'
```

검증 기준:

- Jenkins build 성공
- `archiveArtifacts` 수행 후 MinIO bucket에 오브젝트 생성
- Jenkins UI에서 artifact 다운로드 가능

## 운영 작업

### 계정 비밀번호 변경

```bash
# CI 서비스 계정 비밀번호 갱신
mc admin user add local svc-ci-artifact 'replace-with-strong-password'
# 계정 상태 재확인
mc admin user info local svc-ci-artifact
```

이후 Jenkins의 `minio-s3` credential 값을 같은 비밀번호로 갱신합니다.

### 점검 명령

```bash
# CI 서비스 계정 상태 확인
mc admin user info local svc-ci-artifact
# CI bucket 사용량 확인
mc du local/ci --depth 1
```

확인 항목:

- CI 계정이 `enabled` 상태인지 확인
- bucket 용량 증가 추세 확인
- 보관 주기에 맞는 정리 정책이 있는지 확인

## 주의사항

- 이 문서는 build artifact offload 기준입니다.
- Jenkins home 전체 백업을 MinIO로 직접 대체하는 문서는 아닙니다.
- Controller 백업 정책은 계속 별도로 유지합니다.
