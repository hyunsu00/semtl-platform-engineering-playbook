# GitLab MinIO Integration

## 개요

이 문서는 GitLab 기본 설치 완료 후 MinIO Object Storage를 연동하는 절차를 정의합니다.

## 사전 조건

- GitLab 기본 설치 완료
- MinIO 서비스 정상 동작
- MinIO endpoint: `http://192.168.0.171:9000` (예시)
- MinIO access/secret key 준비
- MinIO 버킷 사전 생성
  - `gitlab-artifacts`
  - `gitlab-uploads`
  - `gitlab-lfs`
  - `gitlab-packages`
  - `gitlab-external-diffs`
  - `gitlab-terraform-state`
  - `gitlab-dependency-proxy`
  - `gitlab-ci-secure-files`

## 설정 절차

### 1. `gitlab.rb` 설정

`/etc/gitlab/gitlab.rb`에 Object Storage 연결을 추가합니다.

```ruby
gitlab_rails['object_store']['enabled'] = true
gitlab_rails['object_store']['proxy_download'] = false
gitlab_rails['object_store']['connection'] = {
  'provider' => 'AWS',
  'region' => 'us-east-1',
  'endpoint' => 'http://192.168.0.171:9000',
  'path_style' => true,
  'aws_access_key_id' => '<minio-access-key>',
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

### 2. 설정 적용

```bash
# GitLab 설정 반영
sudo gitlab-ctl reconfigure

# 서비스 상태 확인
sudo gitlab-ctl status
```

### 3. 연동 검증

```bash
# GitLab 점검 실행
sudo gitlab-rake gitlab:check SANITIZE=true
```

## 스냅샷 권장 시점

스냅샷 생성 전 아래 정리 작업을 먼저 수행합니다.

```bash
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*
sudo apt autoremove -y
sudo apt clean
sudo journalctl --vacuum-time=1s
cat /dev/null > ~/.bash_history && history -c
```

- 시점: MinIO Object Storage 연동 적용/검증 완료 후
- Proxmox: `Snapshots > Take Snapshot`
- 권장 이름: `BASE-GitLab-MinIO-Integrated-v1`
