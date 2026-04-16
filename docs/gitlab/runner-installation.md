# GitLab Runner and Harbor Integration

## 개요

이 문서는 VM에 설치된 GitLab이 `RKE2` 클러스터에 동적 CI Job Pod를
생성하도록 GitLab Runner를 설치하고, GitLab CI에서 빌드한 컨테이너 이미지를
Harbor Container Registry로 push하는 표준 절차를 정리합니다.

GitLab Runner는 `Kubernetes executor`로 동작하며, Pipeline Job이 실행될 때마다
`RKE2` 위에 일회성 Pod를 생성하고 작업 종료 후 정리합니다.

이 문서의 목표는 아래 상태까지 한 번에 만드는 것입니다.

- GitLab 본체는 VM에서 계속 실행
- 실제 CI 작업은 `RKE2` 위의 `Pod` 기반 Job에서 수행
- Runner 전용 namespace, service account, RBAC 적용 완료
- GitLab UI에서 Runner가 `online` 상태로 표시
- 기본 검증용 Pipeline이 `RKE2` Job Pod에서 정상 실행
- GitLab CI/CD 변수를 통해 Harbor 인증 정보 등록 완료
- Pipeline에서 `docker build`와 `docker push` 성공

## 사용 시점

- GitLab은 VM에 두고 CI 실행만 `RKE2`로 분리하려는 경우
- GitLab VM의 CPU, 메모리, 디스크 사용량을 CI 작업과 분리하려는 경우
- Job마다 깨끗한 Pod를 새로 띄우는 구조가 필요한 경우
- Harbor로 이미지를 빌드하고 push하는 CI/CD 흐름을 구성하려는 경우

## 최종 성공 기준

- `gitlab-runner` namespace 생성 완료
- `gitlab-runner` Helm release 배포 완료
- Runner manager Pod가 `Running` 상태
- GitLab UI `Settings -> CI/CD -> Runners`에서 Runner가 `online` 상태
- `tags: [k8s]` Pipeline이 성공하고 Job Pod가 자동 삭제됨
- Harbor 검증용 Pipeline이 Harbor에 이미지를 push함

## 사전 조건

- [GitLab 설치](./installation.md) 완료
- [RKE2 설치](../rke2/installation.md) 완료
- GitLab 관리자 또는 그룹 Owner 계정 준비 완료
- `kubectl`이 가능한 관리 노드에서 대상 `RKE2` 클러스터 접속 가능
- 관리 노드에 `helm` 설치 완료
- GitLab URL이 `RKE2` 클러스터 내부 Pod에서 접근 가능
- GitLab Registry 비활성 정책 적용 완료
- Harbor URL: `https://harbor.semtl.synology.me`
- Harbor 프로젝트 준비 완료
- Harbor Robot Account 또는 사용자 계정 준비 완료

권장 운영값:

- GitLab group: `devops`
- namespace: `gitlab-runner`
- Helm release: `gitlab-runner`
- service account: `gitlab-runner`
- runner tag: `k8s`
- executor: `kubernetes`
- 기본 Job image: `ubuntu:22.04`
- GitLab URL: `https://gitlab.semtl.synology.me`
- Harbor registry: `harbor.semtl.synology.me`
- Harbor project: `devops`

## 구성 기준

- GitLab 본체는 VM에 유지합니다.
- GitLab Runner manager만 `RKE2`에 상시 Pod로 배치합니다.
- 실제 CI Job은 실행 시점에만 `RKE2` Pod로 생성합니다.
- Runner 권한은 전용 namespace 범위로 제한합니다.
- GitLab Runner는 Helm chart로 설치하고 `values.yaml`을 기준으로 관리합니다.
- Harbor 이미지 빌드가 필요한 경우에만 `privileged = true`를 사용합니다.
- 컨테이너 이미지는 GitLab Registry가 아니라 Harbor에 저장합니다.

## 1. GitLab 그룹 생성

GitLab UI 경로:

`Groups -> New group -> Create group`

입력 기준:

- Group name: `devops`
- Group URL: `https://gitlab.semtl.synology.me/devops`
- Visibility level: `Private`
- Who will be using this group?: `My company or team`
- What will you use this group for?: 운영 목적에 맞는 항목 선택
- Invite Members: 비움

입력 후 `Create group`을 선택합니다.

운영 메모:

- `devops`는 표준 예시 그룹명입니다.
- 이미 운영 중인 그룹이 있으면 새로 만들지 않고 기존 그룹을 사용합니다.
- GitLab 그룹과 Harbor 프로젝트 이름을 `devops`로 맞추면 이미지 경로와
  권한 범위를 이해하기 쉽습니다.
- Visibility level은 운영 저장소 기준으로 `Private`를 권장합니다.
- 그룹 생성 후 필요한 사용자는 `Manage -> Members`에서 추가합니다.
- 최소 권한 원칙에 따라 일반 CI 사용자는 `Developer`,
  Runner와 그룹 설정을 관리하는 사용자는 `Owner` 권한을 부여합니다.

생성 확인:

- 좌측 `Groups` 또는 상단 검색에서 `devops` 그룹이 조회됨
- 그룹 URL `https://gitlab.semtl.synology.me/devops` 접근 가능

## 2. GitLab Runner 토큰 발급

권장 우선순위:

1. Group Runner
2. Instance Runner

Group Runner 생성 경로:

`devops` 그룹 -> `Build -> Runners -> Create group runner`

입력 순서:

1. Tags에 `k8s`를 입력합니다.
2. Run untagged jobs를 체크합니다.
3. Runner description에 `k8s-runner`를 입력합니다.
4. Paused는 체크하지 않습니다.
5. Protected는 체크하지 않습니다.
6. Maximum job timeout은 비워 둡니다.
7. `Create runner`를 선택합니다.

생성 후 표시되는 Runner authentication token을 확인합니다.

토큰 형식 예시:

```text
glrt-xxxxxxxxxxxxxxxxxxxx
```

Register 화면 처리:

1. Platform에서 `Linux`를 선택합니다.
2. Containers 항목은 참고용으로만 확인합니다.
3. 화면에 표시되는 `gitlab-runner register` 명령은 실행하지 않습니다.
4. 표시된 `glrt-...` token만 복사합니다.
5. 복사한 token은 다음 단계의 `values.yaml`에서 `runnerToken`에 입력합니다.
6. `View runners`는 Helm 설치와 Runner Pod 기동 검증 후 선택합니다.

중요:

- 이 문서는 Helm chart가 Runner manager Pod를 설치하면서 token을 사용해
  GitLab에 연결하는 방식입니다.
- 따라서 GitLab UI가 보여주는 `gitlab-runner register` CLI 절차를
  별도로 실행하지 않습니다.
- `Docker`, `Kubernetes` 버튼은 일반 설치 가이드 링크입니다.
  Helm 설치 흐름에서는 클릭하지 않아도 됩니다.

운영 메모:

- GitLab 18.x 기준으로 새 Runner 생성 후 `glrt-...` 형식의 인증 토큰을 사용합니다.
- 토큰은 다시 표시되지 않을 수 있으므로 비밀 저장소에 안전하게 보관합니다.
- 이 토큰은 문서, 이슈, 채팅, Git 저장소에 평문으로 남기지 않습니다.
- 토큰이 화면 캡처, 채팅, 이슈 등에 노출된 경우 해당 Runner를 삭제하고
  새 Runner token을 발급합니다.
- `Run untagged jobs`를 체크하면 tag가 없는 기본 Pipeline도 이 Runner에서 실행할 수 있습니다.
- `Paused`를 체크하면 생성 직후 Job을 받지 않으므로 초기 설치에서는 비활성화합니다.
- `Protected`를 체크하면 protected branch/tag Pipeline만 실행하므로
  초기 검증 단계에서는 비활성화합니다.
- `Maximum job timeout`을 비워 두면 프로젝트 또는 인스턴스 기본 timeout 정책을 따릅니다.
- `Settings -> CI/CD -> Runners` 화면은 Runner 사용 정책을 조정하는 화면입니다.
- Group Runner 생성 버튼이 보이지 않으면 그룹 좌측 메뉴의 `Build -> Runners`로 이동합니다.
- `Build -> Runners`에서도 `Create group runner`가 보이지 않으면
  현재 계정이 해당 그룹의 `Owner`인지 확인합니다.
- Group Runner 생성이 제한된 환경에서는 관리자 계정으로
  `Admin -> CI/CD -> Runners -> Create instance runner`를 사용합니다.

## 3. RKE2 namespace 생성

`kubectl`이 가능한 관리 노드에서 아래 명령을 실행합니다.

```bash
kubectl create namespace gitlab-runner --dry-run=client -o yaml \
  | kubectl apply -f -

kubectl get namespace gitlab-runner
```

기대 결과:

- `gitlab-runner` namespace가 출력됨

운영 메모:

- Runner manager Pod와 CI Job Pod를 같은 namespace에 배치하는 기준입니다.
- 프로젝트별 격리가 필요하면 namespace와 Runner를 프로젝트 또는 그룹 단위로 분리합니다.

## 4. Helm 저장소 준비

관리 노드에서 GitLab Helm 저장소를 추가합니다.

```bash
helm repo add gitlab https://charts.gitlab.io
helm repo update gitlab

helm search repo gitlab/gitlab-runner
```

기대 결과:

- `gitlab/gitlab-runner` chart 목록이 출력됨

운영 메모:

- 운영 환경에서는 설치 시점의 chart 버전을 기록합니다.
- 특정 chart 버전을 고정하려면 `helm install` 또는 `helm upgrade`에
  `--version <RUNNER_HELM_CHART_VERSION>`을 추가합니다.

## 5. Runner values.yaml 생성

관리 노드에서 Runner 설정 파일을 만듭니다.

```bash
mkdir -p ~/rke2/gitlab-runner

cat <<'EOF' >~/rke2/gitlab-runner/values.yaml
gitlabUrl: https://gitlab.semtl.synology.me
runnerToken: "<glrt-token>"

rbac:
  create: true

serviceAccount:
  create: true
  name: gitlab-runner

concurrent: 10
checkInterval: 30

runners:
  name: k8s-runner
  tags: "k8s"
  runUntagged: true
  locked: false
  executor: kubernetes
  privileged: true
  config: |
    [[runners]]
      name = "k8s-runner"
      executor = "kubernetes"
      request_concurrency = 2
      [runners.kubernetes]
        namespace = "gitlab-runner"
        image = "ubuntu:22.04"
        privileged = true
        poll_timeout = 600
        helper_image_flavor = "ubuntu"
        service_account = "gitlab-runner"
        cpu_request = "250m"
        memory_request = "256Mi"
        cpu_limit = "2"
        memory_limit = "2Gi"
EOF

chmod 600 ~/rke2/gitlab-runner/values.yaml
```

`<glrt-token>`은 GitLab UI에서 발급한 Runner authentication token으로 교체합니다.

설정 설명:

- `gitlabUrl`
  Runner가 연결할 GitLab 외부 URL입니다.
- `runnerToken`
  GitLab UI에서 생성한 Runner 인증 토큰입니다.
- `rbac.create`
  Runner가 Job Pod를 생성할 수 있도록 필요한 RBAC를 Helm chart가 생성합니다.
- `serviceAccount.name`
  Runner manager와 Job Pod가 사용할 Kubernetes service account입니다.
- `concurrent`
  Runner manager가 동시에 처리할 수 있는 Job 수입니다.
- `runners.tags`
  `.gitlab-ci.yml`에서 사용할 Runner tag입니다.
- `runners.runUntagged`
  tag가 없는 Job도 실행할지 결정합니다.
- `runners.privileged`
  Docker-in-Docker 기반 이미지 빌드에 필요한 설정입니다.
- `request_concurrency`
  GitLab long polling으로 인한 Job 대기 지연을 줄이기 위한 Runner 요청 동시성입니다.

운영 메모:

- Harbor push를 위해 `docker:dind`를 사용할 경우 `privileged = true`가 필요합니다.
- Docker-in-Docker를 사용하지 않는 빌드는 `privileged = false`를 우선 검토합니다.
- 운영 안정성을 위해 기본 Job image는 팀 표준 이미지로 교체하는 것을 권장합니다.

## 6. GitLab Runner 설치

관리 노드에서 Helm chart를 설치합니다.

```bash
helm upgrade --install gitlab-runner gitlab/gitlab-runner \
  --namespace gitlab-runner \
  --values ~/rke2/gitlab-runner/values.yaml
```

설치 상태를 확인합니다.

```bash
helm -n gitlab-runner list
kubectl -n gitlab-runner get pods -o wide
kubectl -n gitlab-runner get sa,role,rolebinding
```

기대 결과:

- Helm release `gitlab-runner` 상태가 `deployed`
- Runner manager Pod가 `Running`
- `gitlab-runner` service account와 RBAC 리소스가 생성됨

## 7. Runner manager 로그 확인

Runner manager Pod 이름을 확인한 뒤 로그를 조회합니다.

```bash
RUNNER_POD=$(
  kubectl -n gitlab-runner get pods \
    -l app=gitlab-runner \
    -o jsonpath='{.items[0].metadata.name}'
)

kubectl -n gitlab-runner logs "$RUNNER_POD"
```

기대 결과:

- GitLab 연결 오류가 없음
- Runner registration 또는 authentication 관련 오류가 없음
- `Runner registered successfully`가 출력됨
- `Configuration loaded`가 출력됨
- `Initializing executor providers` 또는 유사한 executor 초기화 로그가 출력됨

정상 로그 예시:

```text
Verifying runner... is valid
Runner registered successfully.
Configuration loaded
Initializing executor providers
```

로그 참고:

- `Running in user-mode` 경고는 Helm chart로 컨테이너 안에서 Runner를 실행할 때
  표시될 수 있으며, Pod가 `1/1 Running`이고 Runner가 `online`이면 정상으로 봅니다.
- `listen_address not defined, metrics & debug endpoints disabled` 로그는 metrics/debug
  endpoint를 별도로 열지 않았다는 의미입니다. Runner 동작 자체의 실패가 아닙니다.
- `[session_server].listen_address not defined, session endpoints disabled` 로그는
  interactive web terminal 세션 endpoint를 열지 않았다는 의미입니다.
  일반 CI Job 실행에는 영향이 없습니다.
- `Runner registered successfully`, `Configuration loaded`,
  `Initializing executor providers`가 순서대로 보이면 Runner manager는 정상 기동한
  상태로 봅니다. 이후 GitLab UI에서 Runner가 `online`인지 확인하고 검증 Pipeline을 실행합니다.
- `Long polling issues detected` 경고가 보이면 `request_concurrency`를
  `2`에서 `4` 사이로 설정한 뒤 Helm upgrade를 수행합니다.

실패 시 우선 확인:

- `gitlabUrl` 값이 Pod 내부에서 접근 가능한지 확인
- `runnerToken` 값이 올바른지 확인
- GitLab UI에서 Runner가 삭제 또는 paused 상태가 아닌지 확인
- Synology Reverse Proxy 또는 DNS가 `RKE2` Pod에서 해석 가능한지 확인

## 8. GitLab UI Runner 상태 확인

GitLab UI 경로:

`devops` 그룹 -> `Build -> Runners`

확인 기준:

- Runner description이 `k8s-runner`로 표시됨
- Runner tag에 `k8s`가 표시됨
- Runner 상태가 `online`
- Runner가 `paused` 상태가 아님

운영 메모:

- Group Runner로 생성하면 해당 그룹 하위 프로젝트에서 Runner를 공유할 수 있습니다.
- 특정 프로젝트에만 제한하려면 Project Runner로 별도 생성합니다.
- Job이 계속 `pending`이면 Runner tag와 `.gitlab-ci.yml`의 `tags` 값을 먼저 확인합니다.

## 9. 기본 Runner 검증용 프로젝트 생성

Runner 기본 동작 검증 전용 프로젝트를 `devops` 그룹 아래에 생성합니다.

GitLab UI 경로:

`devops` 그룹 -> `New project -> Create blank project`

입력 순서:

1. Project name에 `runner-basic-test`를 입력합니다.
2. Project URL이 `devops/runner-basic-test`인지 확인합니다.
3. Visibility Level은 `Private`를 선택합니다.
4. Initialize repository with a README를 체크합니다.
5. `Create project`를 선택합니다.

생성 확인:

- 프로젝트 URL `https://gitlab.semtl.synology.me/devops/runner-basic-test` 접근 가능
- Repository에 `README.md`가 생성됨

운영 메모:

- 이 프로젝트는 Runner 동작 확인용입니다.
- Harbor 인증 정보, Dockerfile, 이미지 push Pipeline은 이 프로젝트에 넣지 않습니다.
- 실제 서비스 소스와 분리해 두면 Runner 설정 변경 후 반복 검증하기 쉽습니다.
- `Initialize repository with a README`를 체크하면 기본 브랜치가 바로 생성되어
  `.gitlab-ci.yml`을 Web UI에서 추가하기 쉽습니다.

## 10. 기본 Runner 검증용 Pipeline 생성

`runner-basic-test` 프로젝트에 `.gitlab-ci.yml`을 추가합니다.

GitLab UI 경로:

`runner-basic-test -> Code -> Repository -> + -> New file`

입력 순서:

1. Filename에 `.gitlab-ci.yml`을 입력합니다.
2. 파일 내용에 아래 YAML을 입력합니다.
3. Commit message에 `test: GitLab Runner basic test`를 입력합니다.
4. Target branch가 `main`인지 확인합니다.
5. `Commit changes`를 선택합니다.

```yaml
stages:
  - test

k8s-runner-basic-test:
  stage: test
  image: ubuntu:22.04
  tags:
    - k8s
  script:
    - hostname
    - id
    - pwd
    - printenv | sort | grep -E "CI_PROJECT_PATH|CI_PIPELINE_ID" || true
    - printenv | sort | grep -E "CI_RUNNER_DESCRIPTION|CI_RUNNER_TAGS" || true
```

Pipeline 확인 경로:

`runner-basic-test -> Build -> Pipelines`

실행 중 확인:

```bash
kubectl -n gitlab-runner get pods -w
```

설명:

- Runner manager Pod는 계속 유지됩니다.
- Pipeline이 시작되면 별도의 Job Pod가 `gitlab-runner` namespace에 생성됩니다.
- Job이 끝나면 Job Pod는 자동으로 정리됩니다.
- Pod가 빠르게 삭제될 수 있으므로 Pipeline 실행 전에 watch를 걸어 두고 확인합니다.

기대 결과:

- GitLab Pipeline이 `passed`
- Job 로그에 `hostname`, `id`, `pwd` 결과가 출력됨
- `CI_RUNNER_DESCRIPTION` 또는 `CI_RUNNER_TAGS` 환경변수가 출력됨
- `kubectl get pods -w`에서 Job Pod 생성과 종료 흐름이 확인됨

성공 예시 해석:

- Runner manager Pod만 상시 유지되고 Job Pod가 별도로 생성되면 정상입니다.
- `tags: [k8s]` Job이 실행되면 GitLab Runner tag 매칭이 정상입니다.
- Job 로그의 hostname이 GitLab VM hostname이 아니라 Pod hostname이면
  실제 작업이 `RKE2` Pod에서 실행 중이라는 뜻입니다.

## 11. Harbor 연동 정보 확인

GitLab CI에서 사용할 Harbor 접속 정보를 확인합니다.

기준값:

- Harbor URL: `https://harbor.semtl.synology.me`
- Registry 주소: `harbor.semtl.synology.me`
- Harbor 프로젝트: `devops`
- 이미지 경로 패턴: `harbor.semtl.synology.me/<project>/<image>:<tag>`
- 이미지 경로 예시: `harbor.semtl.synology.me/devops/app:main-001`

Harbor API 헬스체크:

```bash
curl -fsS https://harbor.semtl.synology.me/api/v2.0/health
```

기대 결과:

- Harbor API가 `200 OK`와 health JSON을 반환함
- `curl -I`처럼 `HEAD` 요청으로 확인하면 Harbor 버전 또는 nginx 설정에 따라
  `405 Method Not Allowed`가 반환될 수 있음

운영 메모:

- Harbor 프로젝트 이름과 GitLab 그룹 이름을 `devops`로 맞추면
  CI 변수와 이미지 경로를 이해하기 쉽습니다.
- Robot Account를 사용할 경우 최소 권한으로 push 대상 프로젝트에만 권한을 부여합니다.
- Harbor 비밀번호 또는 Robot Secret은 GitLab 변수에만 저장하고 문서에 남기지 않습니다.

## 12. Harbor 프로젝트 생성

GitLab CI에서 이미지를 push할 Harbor 프로젝트를 생성합니다.

Harbor UI 경로:

`Projects -> New Project`

입력 순서:

1. Project Name에 `devops`를 입력합니다.
2. Access Level의 `Public`은 체크하지 않습니다.
3. Project Quota는 `-1 GiB`를 유지합니다.
4. Proxy Cache는 비활성화 상태로 둡니다.
5. `OK` 또는 `확인`을 선택합니다.

입력 기준:

- Project Name: `devops`
- Access Level: `Private`
- Project Quota: `-1 GiB`
- Proxy Cache: `OFF`

생성 확인:

- Harbor `Projects` 목록에 `devops` 프로젝트가 표시됨
- `devops` 프로젝트 상세 화면에 진입 가능

운영 메모:

- Harbor 프로젝트 이름과 GitLab 그룹 이름을 `devops`로 맞추면
  이미지 경로와 권한 범위를 이해하기 쉽습니다.
- `Public`을 체크하지 않고 private 프로젝트로 운영합니다.
- `-1 GiB`는 용량 제한 없음 의미로 사용합니다.
- 운영 환경에서는 Harbor 스토리지 정책에 맞춰 quota를 별도로 지정할 수 있습니다.
- Proxy Cache는 외부 Registry 캐시 용도이므로 GitLab CI push 검증에서는 사용하지 않습니다.

## 13. GitLab CI용 Harbor Robot Account 생성

GitLab CI에서 사용할 전용 Harbor Robot Account를 생성합니다.

Harbor UI 경로:

`Projects -> devops -> Robot Accounts -> New Robot Account`

입력 순서:

1. Name에 `gitlab-ci`를 입력합니다.
2. Expiration time은 운영 정책에 맞게 선택합니다.
3. Description에는 `GitLab CI image push account`를 입력합니다.
4. Permissions에서 `devops` 프로젝트 권한을 설정합니다.
5. Repository 권한은 `Pull`, `Push`를 선택합니다.
6. `Add` 또는 `Save`를 선택합니다.
7. 생성 후 표시되는 Robot Account username과 Secret을 복사합니다.

권장 권한:

- Project: `devops`
- Repository: `Pull`
- Repository: `Push`
- Artifact 삭제, Project 관리 권한: 부여하지 않음

생성 확인:

- `devops` 프로젝트의 Robot Accounts 목록에 `gitlab-ci` 계정이 표시됨
- Robot Account username 전체 값이 확인됨
- Robot Secret이 안전한 위치에 임시 보관됨

운영 메모:

- 개인 사용자 계정 대신 GitLab CI 전용 Robot Account를 사용합니다.
- Harbor가 표시하는 username 전체를 그대로 `HARBOR_USERNAME`에 입력합니다.
- `robot$...` 형식이면 `$`를 포함해 전체 값을 복사합니다.
- Robot Secret은 생성 직후에만 확인 가능한 경우가 있으므로 즉시 저장합니다.
- Secret이 노출되면 Robot Account를 재발급하거나 삭제 후 새로 생성합니다.

## 14. Harbor 검증용 프로젝트 생성

Harbor 이미지 빌드와 push 검증 전용 프로젝트를 `devops` 그룹 아래에 생성합니다.

GitLab UI 경로:

`devops` 그룹 -> `New project -> Create blank project`

입력 순서:

1. Project name에 `harbor-image-test`를 입력합니다.
2. Project URL이 `devops/harbor-image-test`인지 확인합니다.
3. Visibility Level은 `Private`를 선택합니다.
4. Initialize repository with a README를 체크합니다.
5. `Create project`를 선택합니다.

생성 확인:

- 프로젝트 URL `https://gitlab.semtl.synology.me/devops/harbor-image-test` 접근 가능
- Repository에 `README.md`가 생성됨

운영 메모:

- 이 프로젝트는 Harbor push 검증 전용입니다.
- 기본 Runner 동작 확인은 `runner-basic-test`에서 먼저 완료합니다.
- Harbor 인증 정보는 이 프로젝트의 CI/CD 변수로만 등록합니다.
- 검증용 이미지와 Pipeline 이력이 기본 Runner 검증 프로젝트와 섞이지 않도록 분리합니다.

## 15. Harbor 검증용 GitLab CI/CD 변수 등록

`harbor-image-test` 프로젝트에 Harbor 접속 정보를 변수로 등록합니다.

GitLab UI 경로:

`harbor-image-test -> Settings -> CI/CD -> Variables -> Add variable`

`Add variable`을 눌러 아래 변수를 하나씩 등록합니다.

공통 입력 기준:

- Type: `Variable`
- Environment: `All`
- Expand variable reference: 체크 해제
- Description: 비움

### 15.1 HARBOR_REGISTRY 등록

입력값:

- Key: `HARBOR_REGISTRY`
- Value: `harbor.semtl.synology.me`
- Visibility: `Visible`
- Protect variable: 체크 해제
- Expand variable reference: 체크 해제

입력 후 `Add variable`을 선택합니다.

### 15.2 HARBOR_PROJECT 등록

입력값:

- Key: `HARBOR_PROJECT`
- Value: `devops`
- Visibility: `Visible`
- Protect variable: 체크 해제
- Expand variable reference: 체크 해제

입력 후 `Add variable`을 선택합니다.

### 15.3 HARBOR_USERNAME 등록

입력값:

- Key: `HARBOR_USERNAME`
- Value: Harbor Robot Account username 전체 값
- Visibility: `Masked`
- Protect variable: 운영 브랜치에서만 사용할 경우 체크
- Expand variable reference: 체크 해제

입력 후 `Add variable`을 선택합니다.

### 15.4 HARBOR_PASSWORD 등록

입력값:

- Key: `HARBOR_PASSWORD`
- Value: Harbor Robot Secret
- Visibility: `Masked and hidden`
- Protect variable: 운영 브랜치에서만 사용할 경우 체크
- Expand variable reference: 체크 해제

입력 후 `Add variable`을 선택합니다.

등록 확인:

- `HARBOR_REGISTRY`, `HARBOR_PROJECT`, `HARBOR_USERNAME`, `HARBOR_PASSWORD`가
  Variables 목록에 표시됨
- `HARBOR_USERNAME`, `HARBOR_PASSWORD` 값은 목록에서 평문으로 보이지 않음

운영 메모:

- protected branch에서만 Harbor push를 허용하려면 `HARBOR_PASSWORD`를
  `Protected`로 등록하고 Pipeline도 protected branch에서 실행합니다.
- 초기 검증을 일반 브랜치에서 수행해야 하면 검증 중에만 `Protected`를 끄고,
  검증 후 다시 켭니다.
- Robot ID나 Secret이 Masked 정규식 조건을 만족하지 못하면
  `Masked` 저장이 거부될 수 있습니다.
- Masked 저장이 안 되는 값은 Harbor에서 Robot Account를 새로 발급해
  조건에 맞는 Secret을 사용합니다.

## 16. Harbor 이미지 빌드 검증

`harbor-image-test` 프로젝트에서 Web IDE를 열고 `Dockerfile`과 `.gitlab-ci.yml`을
한 번에 추가합니다.

GitLab UI 경로:

`harbor-image-test -> Code -> Web IDE`

입력 순서:

1. Web IDE에서 프로젝트 루트에 `Dockerfile`을 생성합니다.
2. 프로젝트 루트에 `.gitlab-ci.yml`을 생성합니다.
3. Web IDE의 변경 목록에 두 파일이 모두 있는지 확인합니다.
4. Commit message에 `test: Add Harbor image build pipeline`을 입력합니다.
5. Target branch가 `main`인지 확인합니다.
6. `Commit` 또는 `Commit to main`을 선택합니다.

`Dockerfile` 내용:

```dockerfile
FROM alpine:3.20
CMD ["echo", "hello from gitlab runner"]
```

`.gitlab-ci.yml` 내용:

```yaml
stages:
  - build

build-image:
  stage: build
  image: docker:27
  services:
    - name: docker:27-dind
      command: ["--tls=false"]
  tags:
    - k8s
  variables:
    DOCKER_HOST: tcp://docker:2375
    DOCKER_TLS_CERTDIR: ""
    IMAGE_TAG: ${CI_COMMIT_REF_SLUG}-${CI_PIPELINE_IID}
  script:
    - test -n "$HARBOR_REGISTRY"
    - test -n "$HARBOR_PROJECT"
    - test -n "$HARBOR_USERNAME"
    - test -n "$HARBOR_PASSWORD"
    - |
      echo "$HARBOR_PASSWORD" | docker login \
        -u "$HARBOR_USERNAME" \
        --password-stdin "$HARBOR_REGISTRY"
    - docker build -t "$HARBOR_REGISTRY/$HARBOR_PROJECT/app:$IMAGE_TAG" .
    - docker push "$HARBOR_REGISTRY/$HARBOR_PROJECT/app:$IMAGE_TAG"
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
      when: manual
    - when: never
```

생성 확인:

- Repository 루트에 `Dockerfile`이 표시됨
- Repository 루트에 `.gitlab-ci.yml`이 표시됨
- 파일명 대소문자가 정확함
- 하나의 commit에 `Dockerfile`, `.gitlab-ci.yml` 두 파일이 함께 포함됨

수동 실행 경로:

`harbor-image-test -> Build -> Pipelines -> 최신 Pipeline -> build-image -> Run`

실행 중 확인:

```bash
kubectl -n gitlab-runner get pods -w
```

검증 기준:

- `harbor-image-test` Pipeline이 `passed`
- `build-image` Job 성공
- push 직후에는 `build-image` Job이 자동 실행되지 않음
- GitLab UI에서 `build-image` Job을 수동 실행하면 Job Pod가 생성됨
- `docker login` 성공
- `docker build` 성공
- `docker push` 성공
- Harbor 프로젝트에 이미지가 생성됨

운영 메모:

- Harbor 계정 정보는 GitLab CI/CD Variables에 `Masked`, `Protected`로 등록합니다.
- `docker:dind`를 쓰는 Runner는 `privileged = true`가 필요합니다.
- `when: manual`을 사용하면 코드 push와 이미지 push 시점을 분리할 수 있습니다.
- Web IDE에서 두 파일을 한 번에 commit하면 중간 상태의 Pipeline 생성을 줄일 수 있습니다.
- 기본 Runner 검증은 `runner-basic-test`, Harbor push 검증은
  `harbor-image-test`에서 수행합니다.
- `docker login`은 비밀번호가 Job 로그에 노출되지 않도록 `--password-stdin`을 사용합니다.
- 보안 기준이 더 강한 환경에서는 Kaniko, BuildKit rootless, buildah 같은 대안을 검토합니다.

## 17. 업그레이드와 설정 변경

설정 변경 또는 chart 업그레이드는 같은 `values.yaml`을 기준으로 수행합니다.

```bash
helm repo update gitlab

helm upgrade gitlab-runner gitlab/gitlab-runner \
  --namespace gitlab-runner \
  --values ~/rke2/gitlab-runner/values.yaml
```

업그레이드 전 확인:

- GitLab UI에서 Runner를 일시 중지할지 검토
- 실행 중인 Pipeline이 없는지 확인
- `helm -n gitlab-runner list`로 현재 chart와 app version 기록
- `kubectl -n gitlab-runner get pods`로 현재 상태 기록

운영 메모:

- 운영 환경에서는 chart version을 고정하고 검증 후 올리는 방식을 권장합니다.
- 설정 변경 후에는 기본 Runner 검증용 Pipeline과 Harbor 검증용 Pipeline을
  다시 실행합니다.

## 18. 제거 절차

나중에 처음부터 다시 설치하려면 GitLab Runner 객체와 Kubernetes 리소스를
함께 정리합니다.

### 18.1 GitLab UI에서 Runner 중지 및 삭제

GitLab UI 경로:

`devops 그룹 -> Build -> Runners -> k8s-runner`

작업 순서:

1. Runner를 `Pause` 처리합니다.
2. 실행 중인 Job이 없는지 확인합니다.
3. 우측 상단 메뉴에서 `Delete runner`를 선택합니다.
4. Runner 목록에서 `k8s-runner`가 사라졌는지 확인합니다.

운영 메모:

- GitLab UI에서 Runner를 삭제하면 기존 `glrt-...` token은 더 이상 사용할 수 없습니다.
- 삭제된 token을 `values.yaml`에 그대로 두고 Helm을 재실행하면
  Runner Pod가 `CrashLoopBackOff` 상태가 될 수 있습니다.

### 18.2 Helm release 제거

관리 노드에서 아래 명령을 실행합니다.

```bash
helm -n gitlab-runner uninstall gitlab-runner

kubectl -n gitlab-runner get all
```

기대 결과:

- Helm release `gitlab-runner`가 제거됨
- Runner manager Pod가 삭제됨
- 실행 중인 Job Pod가 남아 있지 않음

### 18.3 namespace 정리

`gitlab-runner` namespace를 Runner 전용으로만 사용했다면 namespace까지 제거합니다.

```bash
kubectl delete namespace gitlab-runner
```

삭제 확인:

```bash
kubectl get namespace gitlab-runner
```

기대 결과:

- `not found` 또는 namespace가 조회되지 않음

### 18.4 로컬 token 파일 정리

관리 노드의 `values.yaml`에는 Runner token이 들어 있으므로 재사용하지 않도록 정리합니다.

```bash
cp ~/rke2/gitlab-runner/values.yaml \
  ~/rke2/gitlab-runner/values.yaml.bak.$(date -u +%Y%m%d%H%M%S)

sed -i 's/^runnerToken:.*/runnerToken: "<glrt-token>"/' \
  ~/rke2/gitlab-runner/values.yaml
```

확인:

```bash
grep '^runnerToken:' ~/rke2/gitlab-runner/values.yaml
```

기대 결과:

```text
runnerToken: "<glrt-token>"
```

운영 메모:

- namespace를 삭제하면 Runner 관련 Secret, ConfigMap, RBAC도 함께 삭제됩니다.
- 같은 namespace를 다른 Runner가 공유하고 있다면 namespace 삭제는 수행하지 않습니다.
- 다시 설치할 때는 GitLab UI에서 새 Runner를 생성하고 새 `glrt-...` token을 발급합니다.
- 기존 Job/Pipeline 이력까지 완전히 새로 시작하려면 `runner-basic-test`와
  `harbor-image-test` 프로젝트도 삭제 후 재생성합니다.

## 검증 방법

아래 항목을 모두 확인합니다.

- `helm -n gitlab-runner list`에서 release 상태가 `deployed`
- `kubectl -n gitlab-runner get pods`에서 Runner manager Pod가 `Running`
- GitLab UI에서 Runner가 `online`
- `k8s-runner-basic-test` Pipeline 성공
- Pipeline 실행 중 `gitlab-runner` namespace에 Job Pod 생성 확인
- `harbor-image-test` 프로젝트에 Harbor CI/CD 변수 등록 완료
- `harbor-image-test` Pipeline에서 `docker push` 성공

## 보안 주의사항

- Runner token은 평문으로 커밋하지 않습니다.
- `values.yaml`에 실제 token을 넣은 경우 Git 관리 대상에서 제외합니다.
- GitLab CI/CD 변수의 민감 값은 `Masked`, `Protected`를 활성화합니다.
- `privileged = true` Runner는 신뢰된 프로젝트 또는 그룹에만 연결합니다.
- 외부 기여자의 임의 Pipeline이 privileged Runner에서 실행되지 않도록 권한을 제한합니다.

## 참고

- [GitLab 설치](./installation.md)
- [RKE2 설치](../rke2/installation.md)
- [GitLab Runner Helm chart](https://docs.gitlab.com/runner/install/kubernetes/)
- [GitLab Runner Kubernetes executor](https://docs.gitlab.com/runner/executors/kubernetes/)
