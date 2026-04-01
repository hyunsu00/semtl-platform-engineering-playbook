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
```

### 2. GitLab 전용 계정 준비

```bash
# GitLab 전용 서비스 계정 생성
mc admin user add local svc-gitlab-s3 'replace-with-strong-password'
# GitLab 계정에 읽기/쓰기 권한 부여
mc admin policy attach local readwrite --user svc-gitlab-s3
# 계정 생성 및 정책 연결 상태 확인
mc admin user info local svc-gitlab-s3
```

운영 기준:

- GitLab은 bucket별 세분화보다 전용 계정 + 복수 bucket 구성을 기본으로 사용합니다.
- 계정 이름은 `svc-gitlab-s3`으로 고정해 운영 문서와 맞춥니다.

### 3. `gitlab.rb` 설정

`/etc/gitlab/gitlab.rb`에 Object Storage 연결을 추가합니다.

```ruby
gitlab_rails['object_store']['enabled'] = true
gitlab_rails['object_store']['proxy_download'] = false
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
```

설정 기준:

- `endpoint`는 MinIO S3 API 포트(`9000`)를 사용합니다.
- `path_style`은 반드시 `true`로 둡니다.
- `provider`는 MinIO여도 GitLab 호환을 위해 `AWS`를 사용합니다.

### 4. 설정 적용

```bash
# gitlab.rb 반영
sudo gitlab-ctl reconfigure
# GitLab 주요 서비스 재시작
sudo gitlab-ctl restart
# 서비스 상태 확인
sudo gitlab-ctl status
```

### 5. 연동 검증

```bash
# GitLab 전체 진단 수행
sudo gitlab-rake gitlab:check SANITIZE=true
# artifact bucket 확인
mc ls local/gitlab-artifacts
# uploads bucket 확인
mc ls local/gitlab-uploads
```

검증 기준:

- `gitlab:check` 주요 오류 없음
- Pipeline artifact, 업로드 파일, LFS 등 생성 시 MinIO bucket에 오브젝트 확인

## 운영 작업

### GitLab 계정 비밀번호 변경

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
