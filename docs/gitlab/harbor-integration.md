# GitLab Harbor Integration

## 개요

이 문서는 GitLab 기본 설치 완료 후 Harbor Container Registry를 연동하는 절차를 정의합니다.

## 사전 조건

- GitLab 기본 설치 완료
- GitLab Registry 비활성 정책 적용 완료
- GitLab Runner 준비 (`executor = kubernetes`, `privileged = true`)
- Harbor URL: `https://harbor.semtl.synology.me`
- Harbor 프로젝트 준비 (예: `devops`)
- Harbor Robot Account 또는 사용자 계정 준비

## 연동 절차

### 1. Harbor 접속 정보 확인

- Registry 주소: `harbor.semtl.synology.me`
- 이미지 경로 패턴: `harbor.semtl.synology.me/<project>/<image>:<tag>`
- 예시: `harbor.semtl.synology.me/devops/app:main-001`

### 2. GitLab CI/CD 변수 등록

GitLab 프로젝트 `Settings -> CI/CD -> Variables`에 아래 항목을 등록합니다.

- `HARBOR_REGISTRY`: `harbor.semtl.synology.me`
- `HARBOR_PROJECT`: `devops`
- `HARBOR_USERNAME`: Harbor 계정 또는 Robot ID
- `HARBOR_PASSWORD`: Harbor 비밀번호 또는 Robot Secret

민감 값은 `Masked`, `Protected`를 활성화합니다.

### 3. `.gitlab-ci.yml` 예시 적용

아래 예시는 `docker:dind` 기준이므로 Runner가 `privileged = true`여야 합니다.

```yaml
stages:
  - build

build-image:
  stage: build
  image: docker:27
  services:
    - docker:27-dind
  variables:
    DOCKER_HOST: tcp://docker:2375
    DOCKER_TLS_CERTDIR: ""
    IMAGE_TAG: ${CI_COMMIT_REF_SLUG}-${CI_PIPELINE_IID}
  script:
    - docker login -u "$HARBOR_USERNAME" -p "$HARBOR_PASSWORD" "$HARBOR_REGISTRY"
    - docker build -t "$HARBOR_REGISTRY/$HARBOR_PROJECT/app:$IMAGE_TAG" .
    - docker push "$HARBOR_REGISTRY/$HARBOR_PROJECT/app:$IMAGE_TAG"
  # 기본 브랜치가 main이 아닌 경우 환경에 맞게 수정
  only:
    - main
```

### 4. 연동 검증

```bash
# Harbor API 헬스체크
curl -I https://harbor.semtl.synology.me/api/v2.0/health
```

검증 기준:

- GitLab Pipeline에서 `docker login` 성공
- `docker push` 성공 후 Harbor 프로젝트에 이미지 생성 확인

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

- 시점: GitLab CI에서 Harbor push 성공 검증 후
- Proxmox: `Snapshots > Take Snapshot`
- 권장 이름: `BASE-GitLab-Harbor-Integrated-v1`
