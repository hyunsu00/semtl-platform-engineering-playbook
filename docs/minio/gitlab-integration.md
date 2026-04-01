# MinIO GitLab Integration

## 개요

이 문서는 MinIO를 GitLab Omnibus의 Object Storage로 연동하는 표준 절차를 정의합니다.
GitLab VM의 로컬 디스크에는 코드와 메타데이터를 두고, 대용량 오브젝트는 MinIO로 분리합니다.

## 대상 환경

- MinIO API endpoint: `http://192.168.0.171:9000`
- GitLab URL: `https://gitlab.semtl.synology.me`
- GitLab 배포 방식: Omnibus
- GitLab Container Registry: 비활성
- GitLab service account: `svc-gitlab-s3`

## 사전 조건

- [MinIO 설치](./installation.md) 완료
- [GitLab 설치](../gitlab/installation.md) 완료
- GitLab VM에서 `/etc/gitlab/gitlab.rb` 수정 가능

## 연동 순서

### 1. MinIO bucket 준비

아래 명령은 `MinIO VM`에서 실행합니다.

```bash
# mc가 사용할 MinIO 접속 별칭(local) 등록
mc alias set local http://127.0.0.1:9000 <MINIO_ROOT_USER> '<MINIO_ROOT_PASSWORD>'

# GitLab Object Storage용 bucket들을 순서대로 생성
for bucket in \
  gitlab-artifacts \
  gitlab-uploads \
  gitlab-lfs \
  gitlab-packages \
  gitlab-external-diffs \
  gitlab-terraform-state \
  gitlab-dependency-proxy \
  gitlab-ci-secure-files
do
  # 각 기능별 bucket 생성
  mc mb -p "local/${bucket}"
done

# GitLab 전용 multi-bucket 정책 파일 생성
cat > /tmp/policy-gitlab-s3.json <<'EOF'
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
        "arn:aws:s3:::gitlab-artifacts",
        "arn:aws:s3:::gitlab-uploads",
        "arn:aws:s3:::gitlab-lfs",
        "arn:aws:s3:::gitlab-packages",
        "arn:aws:s3:::gitlab-external-diffs",
        "arn:aws:s3:::gitlab-terraform-state",
        "arn:aws:s3:::gitlab-dependency-proxy",
        "arn:aws:s3:::gitlab-ci-secure-files"
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
        "arn:aws:s3:::gitlab-artifacts/*",
        "arn:aws:s3:::gitlab-uploads/*",
        "arn:aws:s3:::gitlab-lfs/*",
        "arn:aws:s3:::gitlab-packages/*",
        "arn:aws:s3:::gitlab-external-diffs/*",
        "arn:aws:s3:::gitlab-terraform-state/*",
        "arn:aws:s3:::gitlab-dependency-proxy/*",
        "arn:aws:s3:::gitlab-ci-secure-files/*"
      ]
    }
  ]
}
EOF

# GitLab 전용 정책 등록
mc admin policy create local policy-gitlab-s3 /tmp/policy-gitlab-s3.json
```

### 2. GitLab 전용 계정 준비

아래 명령은 `MinIO VM`에서 실행합니다.

```bash
# GitLab 전용 서비스 계정 생성
mc admin user add local svc-gitlab-s3 'replace-with-strong-password'
# GitLab 계정에 GitLab bucket 전용 정책 연결
mc admin policy attach local policy-gitlab-s3 --user svc-gitlab-s3
# 계정 생성 및 정책 연결 상태 확인
mc admin user info local svc-gitlab-s3
```

운영 기준:

- GitLab은 bucket별 세분화보다 전용 계정 + 복수 bucket 구성을 기본으로 사용합니다.
- 계정 이름은 `svc-gitlab-s3`으로 고정해 운영 문서와 맞춥니다.
- 공용 `readwrite` 대신 `policy-gitlab-s3`로 `gitlab-*` bucket만 허용합니다.

### 3. `gitlab.rb` 설정

#### 3.1 [GitLab VM] `gitlab.rb` 백업

아래 명령은 `GitLab VM`에서 실행합니다.

```bash
# 현재 GitLab 설정 파일 백업
sudo cp /etc/gitlab/gitlab.rb /etc/gitlab/gitlab.rb.bak.$(date -u +%Y%m%d%H%M%S)
```

#### 3.2 [GitLab VM] `gitlab.rb` 수정

아래 작업은 `GitLab VM`에서 수행합니다.

`/etc/gitlab/gitlab.rb`에 Object Storage 연결을 추가합니다.

```ruby
# BEGIN semtl minio object storage
gitlab_rails['object_store']['enabled'] = true
gitlab_rails['object_store']['proxy_download'] = true
gitlab_rails['object_store']['connection'] = {
  'provider' => 'AWS',
  'region' => 'us-east-1',
  'endpoint' => 'http://192.168.0.171:9000',
  'path_style' => true,
  'aws_access_key_id' => 'svc-gitlab-s3',
  'aws_secret_access_key' => '<minio-secret-key>'
}

gitlab_rails['object_store']['objects']['artifacts']['bucket'] = 'gitlab-artifacts'
gitlab_rails['object_store']['objects']['uploads']['bucket'] = 'gitlab-uploads'
gitlab_rails['object_store']['objects']['lfs']['bucket'] = 'gitlab-lfs'
gitlab_rails['object_store']['objects']['packages']['bucket'] = 'gitlab-packages'
gitlab_rails['object_store']['objects']['external_diffs']['bucket'] = 'gitlab-external-diffs'
gitlab_rails['object_store']['objects']['terraform_state']['bucket'] = 'gitlab-terraform-state'
gitlab_rails['object_store']['objects']['dependency_proxy']['bucket'] = 'gitlab-dependency-proxy'
gitlab_rails['object_store']['objects']['ci_secure_files']['bucket'] = 'gitlab-ci-secure-files'
# END semtl minio object storage
```

설정 기준:

- `endpoint`는 MinIO S3 API 포트(`9000`)를 사용합니다.
- `proxy_download`는 `true`로 둡니다. 현재 구성은 내부 MinIO endpoint를 사용하므로
  브라우저가 MinIO로 직접 접근하지 않고 GitLab이 프록시 다운로드를 처리하는 편이 안전합니다.
- `path_style`은 반드시 `true`로 둡니다.
- `provider`는 MinIO여도 GitLab 호환을 위해 `AWS`를 사용합니다.

### 4. 설정 적용

아래 명령은 `GitLab VM`에서 실행합니다.

```bash
# gitlab.rb 반영
sudo gitlab-ctl reconfigure
# GitLab 주요 서비스 재시작
sudo gitlab-ctl restart
# 서비스 상태 확인
sudo gitlab-ctl status
```

### 5. 연동 검증

#### 5.1 [GitLab VM] GitLab 상태 확인

아래 명령은 `GitLab VM`에서 실행합니다.

```bash
# GitLab 전체 진단 수행
sudo gitlab-rake gitlab:check SANITIZE=true
```

#### 5.2 [GitLab Web UI] 저장소 파일 업로드 기본 검증

먼저 프로젝트 저장소 자체가 정상인지 확인합니다.

주의:

- `New file -> Upload file -> Commit changes` 방식은 Git 저장소에 파일을 추가하는 동작입니다.
- 이 경우 `gitlab-uploads` bucket이 아니라 Git repository 저장 경로가 사용됩니다.
- 따라서 아래 절차만 수행하고 `gitlab-uploads` bucket이 비어 있어도 비정상은 아닙니다.

권장 테스트 프로젝트:

- Namespace selector: `root` (개인 사용자 namespace)
- Project name: `minio-object-storage-test`
- Visibility: `Private`
- Initialize repository with a README: `ON`

권장 생성 경로:

- `New project -> Create blank project`

예시 설정:

- Base URL: `https://gitlab.semtl.synology.me/`
- Namespace: `root`
- Project slug: `minio-object-storage-test`
- 최종 Project URL: `https://gitlab.semtl.synology.me/root/minio-object-storage-test`
- Default branch: `main`

검증 절차:

1. GitLab에서 `minio-object-storage-test` 프로젝트를 생성합니다.
2. `New file -> Upload file` 로 `test-upload.txt` 파일을 추가합니다.
3. `Commit changes` 후 프로젝트 파일 목록에 `test-upload.txt`가 보이는지 확인합니다.

예시 파일:

- `test-upload.txt`

#### 5.3 [GitLab Web UI] uploads bucket 검증

`gitlab-uploads` bucket을 확인하려면 Git 저장소 커밋이 아니라 Web UI 첨부 업로드를 사용해야 합니다.

권장 절차:

1. 프로젝트에서 `Issues -> New issue` 로 이동합니다.
2. Title에 `minio-uploads-test` 를 입력합니다.
3. Description 입력창을 클릭합니다.
4. 작은 텍스트 파일이나 PNG 이미지 1개를 Description 입력창 안에 드래그앤드롭으로 첨부합니다.
5. 업로드 링크가 Description 본문에 자동 삽입되는지 확인합니다.
6. `Create issue` 로 저장합니다.
7. 생성된 이슈 본문에서 첨부 링크가 정상 동작하는지 확인합니다.

예시 파일:

- `test-upload.txt`
- 작은 PNG 이미지 1개

예시 Description:

```text
MinIO uploads bucket test

attached file check
```

#### 5.4 [MinIO VM] uploads bucket 오브젝트 확인

아래 명령은 `MinIO VM`에서 실행합니다.

```bash
# uploads bucket 확인
mc ls local/gitlab-uploads
# uploads bucket 내부 구조 확인
mc tree local/gitlab-uploads
```

참고:

- `@hashed/`, `user/` prefix가 보이면 uploads bucket 저장은 정상으로 볼 수 있습니다.
- 업로드 오브젝트가 MinIO에 존재하는데 GitLab 화면에서 `Image could not be loaded`가 보이면
  `proxy_download` 설정과 브라우저 다운로드 경로를 함께 점검합니다.

#### 5.5 [선택] [GitLab Web UI + Runner] artifacts bucket 검증

Runner가 준비된 경우에는 CI artifact로도 추가 검증할 수 있습니다.

테스트 프로젝트는 위에서 만든 `minio-object-storage-test`를 그대로 사용합니다.

`.gitlab-ci.yml` 생성 경로 예시:

- `Project -> Build -> Pipeline editor`
- 또는 프로젝트 루트에 `.gitlab-ci.yml` 파일 생성

`.gitlab-ci.yml` 예시:

```yaml
stages:
  - test

artifact-test:
  stage: test
  script:
    - mkdir -p out
    - echo hello-minio > out/result.txt
  artifacts:
    paths:
      - out/result.txt
```

파이프라인 실행 후 `MinIO VM`에서 아래 명령으로 확인합니다.

```bash
# artifact bucket 확인
mc ls local/gitlab-artifacts
# artifact bucket 내부 구조 확인
mc tree local/gitlab-artifacts
```

검증 기준:

- `gitlab:check` 주요 오류 없음
- `Upload file + Commit changes` 후 프로젝트 파일 목록에 `test-upload.txt` 확인
- Web UI 첨부 업로드 후 `gitlab-uploads` bucket에 오브젝트 확인
- Runner가 있을 경우 pipeline artifact 생성 후 `gitlab-artifacts` bucket에 오브젝트 확인

## 운영 작업

### GitLab 계정 비밀번호 변경

아래 명령은 `MinIO VM`에서 실행합니다.

```bash
# GitLab 서비스 계정 비밀번호 갱신
mc admin user add local svc-gitlab-s3 'replace-with-strong-password'
# 계정 상태 재확인
mc admin user info local svc-gitlab-s3
```

이후 GitLab VM의 `/etc/gitlab/gitlab.rb`에서
`aws_secret_access_key`를 같은 값으로 변경하고 `gitlab-ctl reconfigure`를 다시 수행합니다.

### 신규 bucket 추가

GitLab 기능 추가로 bucket이 더 필요하면 아래 순서로 적용합니다.

1. MinIO에 bucket 생성
2. `gitlab.rb`에 해당 object type bucket 매핑 추가
3. `gitlab-ctl reconfigure`
4. 기능별 업로드 테스트

## 스냅샷 권장 시점

스냅샷 생성 전 아래 정리 작업을 먼저 수행합니다.
아래 명령은 `GitLab VM`에서 실행합니다.

```bash
# 스냅샷 전 임시 파일 정리
sudo rm -rf /tmp/*
# 스냅샷 전 시스템 임시 파일 정리
sudo rm -rf /var/tmp/*
# 불필요 패키지 제거
sudo apt autoremove -y
# 패키지 캐시 정리
sudo apt clean
# 과거 journal 로그 최소화
sudo journalctl --vacuum-time=1s
# 셸 히스토리 정리
cat /dev/null > ~/.bash_history && history -c
```

- 시점: GitLab Object Storage 연동 적용 및 bucket 생성 확인 완료 후
- Proxmox: `Snapshots > Take Snapshot`
- 권장 이름: `BASE-GitLab-MinIO-Integrated-v1`
