# MinIO Jenkins Integration

## 개요

이 문서는 Jenkins에서 MinIO를 S3 호환 스토리지로 연동하는 표준 절차를 정의합니다.
주요 목적은 빌드 산출물과 아카이브를 Controller 로컬 디스크가 아닌 MinIO bucket으로 분리하는 것입니다.

## 대상 환경

- MinIO API endpoint: `http://192.168.0.171:9000`
- Jenkins URL: `https://jenkins.semtl.synology.me`
- Jenkins 플러그인: `aws-credentials`, `artifact-manager-s3`, `pipeline-utility-steps`
- Jenkins service account: `svc-jenkins-s3`

## 사전 조건

- [MinIO 설치](./installation.md) 완료
- [Jenkins 설치](../jenkins/installation.md) 완료
- Jenkins 주요 플러그인 설치 완료
- Jenkins 관리자 계정 준비

## 연동 순서

### 1. MinIO bucket 및 계정 준비

아래 명령은 `MinIO VM`에서 실행합니다.

```bash
# mc가 사용할 MinIO 접속 별칭(local) 등록
mc alias set local http://127.0.0.1:9000 <MINIO_ROOT_USER> '<MINIO_ROOT_PASSWORD>'

# Jenkins artifact 전용 bucket 생성
mc mb -p local/jenkins-artifacts

# Jenkins 전용 bucket 제한 정책 파일 생성
cat > /tmp/policy-jenkins-artifacts.json <<'EOF'
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
        "arn:aws:s3:::jenkins-artifacts"
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
        "arn:aws:s3:::jenkins-artifacts/*"
      ]
    }
  ]
}
EOF

# Jenkins 전용 정책 등록
mc admin policy create local policy-jenkins-artifacts /tmp/policy-jenkins-artifacts.json
# Jenkins 전용 서비스 계정 생성
mc admin user add local svc-jenkins-s3 'replace-with-strong-password'
# Jenkins 계정에 Jenkins bucket 전용 정책 연결
mc admin policy attach local policy-jenkins-artifacts --user svc-jenkins-s3
# 계정 생성 및 정책 연결 상태 확인
mc admin user info local svc-jenkins-s3
```

운영 기준:

- Jenkins 전용 bucket은 `jenkins-artifacts`를 기본값으로 사용합니다.
- 계정 이름은 `svc-jenkins-s3`로 통일합니다.
- 공용 `readwrite` 대신 `policy-jenkins-artifacts`로 `jenkins-artifacts/*` 범위만 허용합니다.
- Console 포트(`9001`)가 아니라 S3 API 포트(`9000`)를 사용합니다.

### 2. [Jenkins Web UI] Jenkins Credentials 등록

Jenkins UI 경로:

`Manage Jenkins -> Credentials -> System -> Global credentials -> Add Credentials`

입력 기준:

- Kind: `AWS Credentials`
- Scope: `Global`
- ID: `jenkins-minio-s3`
- Access Key ID: `svc-jenkins-s3`
- Secret Access Key: `<minio-secret-key>`
- Description: `MinIO S3 for Jenkins artifacts`

참고:

- 저장 위치는 `System -> Global credentials (unrestricted)`를 사용합니다.
- `Artifact Manager on S3`는 Jenkins 전역 설정에서 credential을 참조하므로 `Scope`는 `Global`로 둡니다.
- `IAM Role Support`는 사용하지 않고 기본값으로 둡니다.
- 현재 구성은 AWS IAM Role이 아니라 MinIO의 고정 Access Key/Secret Key를 사용합니다.
- Jenkins의 `AWS Credentials` 입력 화면에서 `AWS was not able to validate the provided access credentials` 경고가 표시될 수 있습니다.
- 이 경고는 Jenkins가 MinIO 계정을 AWS IAM 자격증명처럼 사전 검증하려고 할 때 발생할 수 있습니다.
- MinIO 연동에서는 저장 후 `Artifact Manager on S3` 설정과 실제 artifact 업로드 테스트로 동작 여부를 확인합니다.

### 3. [Jenkins Web UI] Artifact Management for Builds 설정

Jenkins UI 경로:

`Manage Jenkins -> System -> Artifact Management for Builds`

입력 기준:

- Cloud Provider: `Amazon S3`

설정 기준:

- 먼저 `Artifact Management for Builds`에서 Cloud Provider를 `Amazon S3`로 선택해야 Jenkins가 기본 로컬 artifact manager 대신 S3 artifact manager를 사용합니다.
- 이 설정이 빠지면 Jenkins UI에서는 artifact가 보여도 실제 파일은 `/var/lib/jenkins/jobs/.../archive/` 아래 로컬 디스크에만 저장될 수 있습니다.
- 저장 후 다음 단계의 `AWS` 페이지에서 bucket과 credential 상세 설정을 진행합니다.

### 4. [Jenkins Web UI] AWS 페이지 설정

Jenkins UI 경로:

`Manage Jenkins -> Amazon Web Services Configuration`

이 페이지에는 `Artifact Manager Amazon S3 Bucket`와 `Amazon Credentials` 섹션이 함께 표시됩니다.

#### 4.1 `Artifact Manager Amazon S3 Bucket` 섹션

입력 기준:

- S3 Bucket Name: `jenkins-artifacts`
- Base Prefix: 비움
- Delete Artifacts: `OFF`
- Delete Stashes: `OFF`
- Custom Endpoint: `192.168.0.171:9000`
- Custom Signing Region: `us-east-1`
- Use Path Style URL: `ON`
- Use Insecure HTTP: `ON`
- Use Transfer Acceleration: `OFF`
- Disable Session Token: `ON`

#### 4.2 `Amazon Credentials` 섹션

입력 기준:

- Region: `Auto` 또는 `US East (N. Virginia) / us-east-1`
- Amazon Credentials: `svc-jenkins-s3 (MinIO S3 for Jenkins artifacts)` 항목 선택

설정 기준:

- `Artifact Manager Amazon S3 Bucket`와 `Amazon Credentials`를 같은 `AWS` 페이지에서 함께 저장합니다.
- bucket 이름은 MinIO에 생성한 `jenkins-artifacts`와 정확히 일치해야 합니다.
- `Custom Endpoint`는 프로토콜 없이 `host:port` 형식으로 입력하고, HTTP 사용 여부는 `Use Insecure HTTP` 체크박스로 제어합니다.
- MinIO 같은 S3 호환 스토리지는 AWS가 아니므로 `Custom Endpoint`, `Use Path Style URL`, `Use Insecure HTTP`, `Disable Session Token`을 함께 설정합니다.
- `Custom Signing Region`은 `us-east-1`로 두고, `Amazon Credentials`의 `Region`은 `Auto`를 사용하거나 필요 시 `US East (N. Virginia) / us-east-1`로 명시합니다.
- `Amazon Credentials` 드롭다운에는 credential ID인 `jenkins-minio-s3` 대신 Access Key ID와 설명이 조합된 표시 이름이 보일 수 있습니다.
- `Base Prefix`를 비워 두면 artifact는 bucket 루트 경로 아래에 저장됩니다.
- `Delete Artifacts`와 `Delete Stashes`는 기본적으로 비활성화합니다. 삭제 동기화는 Jenkins 메타데이터와 S3 오브젝트 정합성이 어긋날 수 있어, 보관 정리는 MinIO lifecycle 정책으로 관리하는 편이 안전합니다.
- `Cloud Artifact Storage` 또는 `Artifact Manager on S3` 관련 경고가 보이면, 이 페이지에서 bucket과 credential 설정이 모두 저장되었는지 먼저 확인합니다.

### 5. [Jenkins Web UI] Pipeline 검증

권장 테스트 Job:

- Item name: `minio-artifact-test`
- Job type: `Pipeline`

따라가기:

1. Jenkins 첫 화면에서 `New Item`을 클릭합니다.
2. `Item name`에 `minio-artifact-test`를 입력합니다.
3. `Pipeline`을 선택한 뒤 `OK`를 클릭합니다.
4. Job 설정 화면의 `Pipeline` 섹션으로 이동합니다.
5. `Definition`은 `Pipeline script`로 둡니다.
6. 아래 테스트용 Pipeline 스크립트를 붙여 넣습니다.
7. `Save`를 클릭합니다.
8. Job 화면에서 `Build Now`를 클릭합니다.
9. 좌측 `Build History`에서 방금 실행된 build를 클릭합니다.
10. `Console Output`에서 build가 성공했는지 확인합니다.
11. build 상세 화면에서 `Artifacts` 링크가 보이는지 확인합니다.
12. `result.txt`를 다운로드해 내용이 `hello-minio`인지 확인합니다.

테스트용 Pipeline 스크립트:

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

참고:

- 별도 Git 저장소 연결 없이 Jenkins 내부 테스트용 Pipeline으로 검증할 수 있습니다.
- `archiveArtifacts` 단계가 성공하면 Jenkins가 MinIO bucket에 artifact 업로드를 시도합니다.
- build 로그에 `Still waiting to schedule task` 또는 `Waiting for next available executor`가 보이면 MinIO 문제가 아니라 Jenkins executor 부족 상태일 수 있습니다.
- 이 경우 `Manage Jenkins -> Nodes`에서 built-in node 또는 연결된 agent가 `online` 상태인지, executor 수가 `1` 이상인지 먼저 확인합니다.

### 6. 연동 검증

#### 6.1 [Jenkins Web UI] build 및 artifact 확인

Jenkins에서 테스트 Job 또는 Pipeline을 실행합니다.

확인 항목:

- build가 성공 상태인지 확인합니다.
- `archiveArtifacts` 수행 후 Jenkins UI에서 artifact 링크가 노출되는지 확인합니다.
- Jenkins UI에서 artifact 다운로드가 가능한지 확인합니다.

#### 6.2 [MinIO VM] bucket 오브젝트 확인

아래 명령은 `MinIO VM`에서 실행합니다.

```bash
# Jenkins artifact bucket 오브젝트 확인
mc ls local/jenkins-artifacts
# Jenkins artifact bucket 내부 경로 확인
mc tree local/jenkins-artifacts
# 업로드된 artifact 파일 검색
mc find local/jenkins-artifacts --name '*.txt'
```

검증 기준:

- Jenkins build 성공
- `archiveArtifacts` 수행 후 MinIO bucket에 오브젝트 생성
- Jenkins UI에서 artifact 다운로드 가능

## 트러블슈팅

### Jenkins UI에서는 artifact가 보이는데 MinIO bucket이 비어 있음

확인 순서:

1. `Manage Jenkins -> System -> Artifact Management for Builds`에서 Cloud Provider가 `Amazon S3`로 저장되어 있는지 확인합니다.
2. `Manage Jenkins -> Amazon Web Services Configuration`에서 bucket과 credential 설정이 저장되어 있는지 다시 확인합니다.
3. Jenkins VM에서 아래 명령으로 로컬 archive 저장 여부를 확인합니다.

```bash
sudo find /var/lib/jenkins/jobs -path '*/archive/dist/result.txt'
```

해석 기준:

- 위 경로에 파일이 보이면 Jenkins가 아직 기본 로컬 artifact manager를 사용 중일 수 있습니다.
- `Artifact Management for Builds`에서 `Amazon S3` 선택이 빠졌는지 먼저 확인합니다.

### `Still waiting to schedule task` 또는 `Waiting for next available executor`

의미:

- MinIO 문제가 아니라 Jenkins executor 부족 상태입니다.

확인 순서:

1. `Manage Jenkins -> Nodes`로 이동합니다.
2. built-in node 또는 연결된 agent가 `online` 상태인지 확인합니다.
3. executor 수가 `1` 이상인지 확인합니다.

### `mc admin user info`에서 `PolicyName`이 비어 있음

의미:

- MinIO 정책은 생성됐지만 `svc-jenkins-s3` 계정에 실제 연결되지 않은 상태입니다.

확인 명령:

```bash
mc admin user info local svc-jenkins-s3
```

정상 예시:

- `PolicyName: policy-jenkins-artifacts`

수정 명령:

```bash
mc admin policy attach local policy-jenkins-artifacts --user svc-jenkins-s3
mc admin user info local svc-jenkins-s3
```

### `SignatureDoesNotMatch`로 업로드 실패

의미:

- Jenkins가 MinIO로 업로드를 시도했지만 서명 계산에 사용한 자격증명이 MinIO와 일치하지 않습니다.

주요 원인:

- Jenkins에 저장된 `Secret Access Key`와 MinIO의 현재 사용자 비밀번호가 다름
- `Custom Endpoint`를 `http://host:port`로 넣는 등 형식이 잘못됨

확인 순서:

1. `Custom Endpoint`가 `192.168.0.171:9000`처럼 `host:port` 형식인지 확인합니다.
2. MinIO VM에서 `svc-jenkins-s3` 비밀번호를 다시 설정합니다.
3. Jenkins의 `jenkins-minio-s3` credential에도 같은 Secret Access Key를 다시 저장합니다.
4. 새 build를 다시 실행합니다.

참고:

- `403 Forbidden`과 `SignatureDoesNotMatch`가 보이면 네트워크 문제보다 secret key 불일치 가능성이 큽니다.
- Jenkins credential 값을 수정한 뒤에는 이전 build가 아니라 새 build로 다시 검증해야 합니다.

## 운영 작업

### 계정 비밀번호 변경

아래 명령은 `MinIO VM`에서 실행합니다.

```bash
# Jenkins 서비스 계정 비밀번호 갱신
mc admin user add local svc-jenkins-s3 'replace-with-strong-password'
# 계정 상태 재확인
mc admin user info local svc-jenkins-s3
```

이후 Jenkins의 `jenkins-minio-s3` credential 값을 같은 비밀번호로 갱신합니다.

### 점검 명령

아래 명령은 `MinIO VM`에서 실행합니다.

```bash
# Jenkins 서비스 계정 상태 확인
mc admin user info local svc-jenkins-s3
# Jenkins artifact bucket 사용량 확인
mc du local/jenkins-artifacts --depth 1
```

확인 항목:

- Jenkins 계정이 `enabled` 상태인지 확인
- bucket 용량 증가 추세 확인
- 보관 주기에 맞는 정리 정책이 있는지 확인

### [Jenkins Web UI] 테스트 Job build 이력 초기화

테스트 Job `minio-artifact-test`를 다시 `#1`부터 검증하고 싶다면 Jenkins Script Console에서 build 이력을 초기화할 수 있습니다.

Jenkins UI 경로:

`Manage Jenkins -> Script Console`

실행 스크립트:

```groovy
import jenkins.model.Jenkins

def job = Jenkins.instance.getItemByFullName('minio-artifact-test')
assert job != null : 'Job not found: minio-artifact-test'

job.builds.each { build ->
  build.delete()
}

job.updateNextBuildNumber(1)
job.save()

println "Deleted all builds for ${job.fullName}"
println "Next build number reset to 1"
```

참고:

- 이 스크립트는 Jenkins의 성공/실패 build 이력과 build 번호만 초기화합니다.
- MinIO bucket의 오브젝트는 자동으로 삭제되지 않을 수 있습니다.
- `Delete Artifacts`, `Delete Stashes`를 `OFF`로 둔 현재 구성에서는 MinIO 오브젝트를 별도로 지워야 합니다.

필요 시 `MinIO VM`에서 아래 명령으로 테스트 Job artifact를 함께 정리합니다.

```bash
mc rm --recursive --force local/jenkins-artifacts/minio-artifact-test
```

## 주의사항

- 이 문서는 build artifact offload 기준입니다.
- Jenkins home 전체 백업을 MinIO로 직접 대체하는 문서는 아닙니다.
- Controller 백업 정책은 계속 별도로 유지합니다.
