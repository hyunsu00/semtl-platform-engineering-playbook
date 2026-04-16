# Jenkins Harbor Integration

## 개요

이 문서는 Jenkins가 `RKE2` Kubernetes Agent Pod에서 Harbor에 컨테이너
이미지를 push하고, 다시 pull해서 실행 검증하는 Pipeline Job 예제를 정리합니다.

Jenkins Controller는 VM에 유지하고, 실제 Docker build와 Harbor push/pull은
`jenkins-agents` namespace의 일회성 Agent Pod에서 수행합니다.

이 문서의 목표는 아래 상태까지 확인하는 것입니다.

- Jenkins Kubernetes Cloud와 `k8s-default` Pod Template 재사용
- Jenkins `devops` Folder에서 Job과 Credential 관리
- Harbor Robot Account를 Jenkins Credential로 등록
- Kubernetes Agent Pod 안에서 `docker build` 실행
- Harbor 프로젝트로 `docker push` 성공
- Harbor에서 이미지를 다시 `docker pull` 후 `docker run` 검증

## 사용 시점

- Jenkins에서 Harbor Registry push/pull 동작을 검증하려는 경우
- Jenkins Controller가 아니라 Kubernetes Agent Pod에서 빌드를 실행하려는 경우
- GitLab CI와 별도로 Jenkins 기반 이미지 빌드 예제를 유지하려는 경우
- 운영 Jenkinsfile 작성 전 최소 동작 예제가 필요한 경우

## 최종 성공 기준

- Jenkins Credential에 Harbor 계정 정보 등록 완료
- `harbor-push-pull-test` Pipeline Job 생성 완료
- Pipeline 실행 시 `jenkins-agents` namespace에 Agent Pod 생성
- `docker login`, `docker build`, `docker push`, `docker pull` 성공
- Harbor UI의 `devops/jenkins-harbor-test` repository에 이미지 tag 생성
- Pipeline 마지막에 `Finished: SUCCESS` 출력

## 사전 조건

- [Jenkins 설치](./installation.md) 완료
- [Jenkins RKE2 Agent 설치](./kubernetes-agent-installation.md) 완료
- [Harbor 설치](../harbor/installation.md) 완료
- Jenkins UI `Manage Jenkins -> Clouds`의 `k8s-default` Pod Template 준비 완료
- Harbor URL: `https://harbor.semtl.synology.me`
- Harbor Registry: `harbor.semtl.synology.me`
- Harbor 프로젝트: `devops`
- Harbor Robot Account 또는 push/pull 가능한 사용자 계정 준비 완료

권장 운영값:

- Jenkins Job name: `harbor-push-pull-test`
- Jenkins Folder: `devops`
- Jenkins Credential ID: `harbor-robot-devops`
- Kubernetes pod label: `k8s-harbor`
- Harbor repository: `devops/jenkins-harbor-test`
- Docker CLI image: `docker:27`
- Docker daemon image: `docker:27-dind`

## 구성 기준

- Pipeline은 `k8s-default` Pod Template을 상속합니다.
- Agent Pod에는 `docker` 컨테이너와 `dind` 컨테이너를 추가합니다.
- Docker CLI는 같은 Pod의 `dind` daemon에 `tcp://localhost:2375`로 연결합니다.
- `dind` 컨테이너는 Docker-in-Docker 실행을 위해 `privileged`로 실행합니다.
- Harbor 비밀번호 또는 Robot Secret은 Jenkins Credential에만 저장합니다.
- Jenkins Credential은 `devops` Folder 범위에 등록해 사용 범위를 제한합니다.
- 문서 예제는 검증용이며, 운영 빌드에서는 이미지 이름과 tag 정책을 서비스 기준에 맞춥니다.

## 1. Harbor Robot Account 생성

Harbor UI에서 Jenkins용 Robot Account를 생성합니다.

Harbor UI 경로:

`Projects -> devops -> Robot Accounts -> New Robot Account`

입력 순서:

1. Name에 `jenkins-ci`를 입력합니다.
2. Expiration time은 운영 정책에 맞게 선택합니다.
3. 설명에는 `Jenkins Kubernetes Agent image push/pull for devops`를 입력합니다.
4. Permissions에서 `devops` 프로젝트 권한을 설정합니다.
5. Repository 권한은 `Pull`, `Push`를 선택합니다.
6. `Add` 또는 `Save`를 선택합니다.
7. 생성 후 표시되는 Robot Account username과 Secret을 복사합니다.

권장 권한:

- Project: `devops`
- Repository: `Pull`
- Repository: `Push`
- Artifact 삭제: 부여하지 않음
- Project 관리 권한: 부여하지 않음

확인 항목:

- `devops` 프로젝트의 Robot Accounts 목록에 `jenkins-ci` 계정이 표시됩니다.
- Robot Account username 전체 값을 확인합니다.
- Robot Secret을 안전한 위치에 임시 보관합니다.
- `robot$...` 형식이면 `$`를 포함해 전체 username을 사용합니다.

운영 메모:

- 개인 사용자 계정 대신 Jenkins 전용 Robot Account를 사용합니다.
- 이미 GitLab CI용 Robot Account가 있어도 Jenkins용 계정은 분리하는 것을 권장합니다.
- 계정을 분리하면 Jenkins Job 중지, Secret 교체, 감사 추적을 독립적으로 관리하기 쉽습니다.
- Robot Secret은 생성 직후에만 확인 가능한 경우가 있으므로 즉시 Jenkins Credential에 등록합니다.
- Jenkins에는 Harbor가 표시하는 username 전체를 그대로 입력합니다.
- Secret이 노출되면 해당 Robot Account를 삭제하거나 Secret을 재발급합니다.

## 2. Jenkins Credential 등록

Jenkins UI에서 Harbor 인증 정보를 등록합니다.

사전 확인:

- [Jenkins RKE2 Agent 설치](./kubernetes-agent-installation.md)의
  `Jenkins devops Folder 생성` 절차가 완료되어 있어야 합니다.

Jenkins UI 경로:

`Dashboard -> devops -> Credentials -> Folder -> Global credentials (unrestricted)`

입력 순서:

1. `Global credentials (unrestricted)`를 선택합니다.
2. 좌측 또는 우측 상단의 `Add Credentials`를 선택합니다.

입력값:

- Kind: `Username with password`
- Scope: `Global`
- Username: Harbor Robot Account username 전체 값
- Password: Harbor Robot Secret
- ID: `harbor-robot-devops`
- Description: `Harbor devops robot account for Jenkins`

등록 확인:

- `devops` Folder credentials 목록에 `harbor-robot-devops`가 표시됨
- Credential 상세 화면에서 Secret 값이 평문으로 노출되지 않음

운영 메모:

- Jenkins UI에서 Scope가 `Global`로 표시되더라도 Folder credentials에 등록하면
  해당 Folder와 하위 Job에서 사용하는 Credential로 관리됩니다.
- Pipeline에는 username/password 값을 직접 쓰지 않습니다.
- Credential ID만 Jenkinsfile 또는 Pipeline Script에 남깁니다.
- `HARBOR_PASSWORD`는 콘솔 로그에 출력하지 않습니다.

## 3. Pipeline Job 생성

`devops` Folder 안에서 새 Pipeline Job을 생성합니다.

Jenkins UI 경로:

`Dashboard -> devops -> New Item`

입력값:

- Item name: `harbor-push-pull-test`
- Job type: `Pipeline`

입력 후 `OK`를 선택합니다.

운영 메모:

- 이 Job은 Harbor push/pull 수동 검증용입니다.
- 별도 SCM trigger를 설정하지 않으면 사용자가 `Build Now`를 눌렀을 때만 실행됩니다.
- Job 전체 경로는 `devops/harbor-push-pull-test`입니다.
- 운영 서비스 빌드는 별도 Job 또는 Multibranch Pipeline으로 분리합니다.

## 4. Pipeline Script 입력

Job 설정 화면의 `Pipeline` 섹션에 아래 스크립트를 입력합니다.

```groovy
pipeline {
  agent {
    kubernetes {
      label 'k8s-harbor'
      inheritFrom 'k8s-default'
      defaultContainer 'docker'
      yamlMergeStrategy merge()
      yaml '''
apiVersion: v1
kind: Pod
spec:
  containers:
    - name: docker
      image: docker:27
      command:
        - cat
      tty: true
      env:
        - name: DOCKER_HOST
          value: tcp://localhost:2375
        - name: DOCKER_TLS_CERTDIR
          value: ""
    - name: dind
      image: docker:27-dind
      securityContext:
        privileged: true
        runAsUser: 0
        runAsGroup: 0
      args:
        - --host=tcp://0.0.0.0:2375
        - --tls=false
      env:
        - name: DOCKER_TLS_CERTDIR
          value: ""
      volumeMounts:
        - name: docker-graph-storage
          mountPath: /var/lib/docker
  volumes:
    - name: docker-graph-storage
      emptyDir: {}
'''
    }
  }

  environment {
    HARBOR_REGISTRY = 'harbor.semtl.synology.me'
    HARBOR_PROJECT = 'devops'
    IMAGE_NAME = 'jenkins-harbor-test'
    IMAGE_TAG = "${env.BUILD_NUMBER}"
  }

  stages {
    stage('Prepare Dockerfile') {
      steps {
        sh '''
          cat > Dockerfile <<'EOF'
FROM alpine:3.20
ARG BUILD_ID
LABEL org.opencontainers.image.source="jenkins"
RUN echo "hello from jenkins ${BUILD_ID}" > /message.txt
CMD ["cat", "/message.txt"]
EOF
        '''
      }
    }

    stage('Docker Login') {
      steps {
        withCredentials([
          usernamePassword(
            credentialsId: 'harbor-robot-devops',
            usernameVariable: 'HARBOR_USERNAME',
            passwordVariable: 'HARBOR_PASSWORD'
          )
        ]) {
          sh '''
            mkdir -p .docker
            export DOCKER_CONFIG="$PWD/.docker"
            echo "$HARBOR_PASSWORD" | docker login \
              -u "$HARBOR_USERNAME" \
              --password-stdin "$HARBOR_REGISTRY"
          '''
        }
      }
    }

    stage('Build And Push') {
      steps {
        sh '''
          export DOCKER_CONFIG="$PWD/.docker"
          IMAGE="$HARBOR_REGISTRY/$HARBOR_PROJECT/$IMAGE_NAME:$IMAGE_TAG"
          docker build --build-arg BUILD_ID="$BUILD_NUMBER" -t "$IMAGE" .
          docker push "$IMAGE"
        '''
      }
    }

    stage('Pull And Run') {
      steps {
        sh '''
          export DOCKER_CONFIG="$PWD/.docker"
          IMAGE="$HARBOR_REGISTRY/$HARBOR_PROJECT/$IMAGE_NAME:$IMAGE_TAG"
          docker image rm "$IMAGE" || true
          docker pull "$IMAGE"
          docker run --rm "$IMAGE"
        '''
      }
    }
  }

  post {
    always {
      sh '''
        export DOCKER_CONFIG="$PWD/.docker"
        docker logout "$HARBOR_REGISTRY" || true
      '''
    }
  }
}
```

저장 기준:

- `Pipeline script`에 위 예제를 붙여 넣습니다.
- `Save`를 선택합니다.
- SCM checkout 없이 Pipeline Script 자체에서 검증용 `Dockerfile`을 생성합니다.

운영 메모:

- `inheritFrom 'k8s-default'`는 기존 Jenkins Kubernetes Agent 설정을 재사용합니다.
- `yamlMergeStrategy merge()`는 `k8s-default` Pod Template에 예제 컨테이너를 병합합니다.
- `DOCKER_HOST=tcp://localhost:2375`는 같은 Pod의 `dind` 컨테이너를 바라봅니다.
- `docker:dind`는 `privileged`가 필요하므로 신뢰된 Job에서만 사용합니다.
- `k8s-default`가 `Run As User ID: 1000`을 사용하더라도 `dind` 컨테이너는
  `runAsUser: 0`으로 실행해 Docker daemon 권한 문제를 줄입니다.
- Docker login config는 workspace의 `.docker` 디렉터리에 저장하고 Job 종료 후
  `docker logout`을 수행합니다.
- Harbor가 사설 인증서를 사용하면 Docker daemon 신뢰 저장소 구성이 추가로 필요할 수 있습니다.

## 5. Job 실행

Jenkins UI에서 Job을 수동 실행합니다.

Jenkins UI 경로:

`devops -> harbor-push-pull-test -> Build Now`

실행 중 Agent Pod 확인:

```bash
sudo -u jenkins kubectl --kubeconfig /var/lib/jenkins/.kube/config \
  -n jenkins-agents get pods -w
```

기대 결과:

- `jenkins-agents` namespace에 `k8s-harbor` 기반 Agent Pod가 생성됨
- Jenkins Console Output에 `docker login` 성공 로그가 출력됨
- `docker build`가 성공함
- `docker push`가 성공함
- `docker pull`이 성공함
- `docker run --rm` 결과로 `hello from jenkins <BUILD_NUMBER>`가 출력됨
- 마지막에 `Finished: SUCCESS`가 출력됨

운영 메모:

- Pod가 빠르게 삭제될 수 있으므로 Job 실행 전에 watch 명령을 먼저 실행합니다.
- 같은 tag를 재사용하지 않도록 예제는 Jenkins `BUILD_NUMBER`를 tag로 사용합니다.
- 필요하면 `IMAGE_TAG`를 Git commit SHA, release version, 날짜 기반 값으로 바꿉니다.

## 6. Harbor UI 확인

Harbor UI에서 push된 이미지를 확인합니다.

Harbor UI 경로:

`Projects -> devops -> Repositories -> jenkins-harbor-test`

확인 기준:

- `jenkins-harbor-test` repository가 생성됨
- Jenkins `BUILD_NUMBER`와 같은 tag가 표시됨
- Artifact 상세 화면에서 push 시간이 Jenkins Job 실행 시점과 일치함

운영 메모:

- 검증용 tag가 많이 쌓이면 Harbor retention policy를 적용합니다.
- 운영 이미지에는 빌드 번호 외에 Git SHA 또는 release tag를 함께 남기는 것을 권장합니다.

## 검증 방법

아래 항목을 모두 확인합니다.

- Jenkins Credential `harbor-robot-devops` 등록 완료
- `harbor-push-pull-test` Job 성공
- Jenkins Console Output에서 `docker push` 성공 확인
- Jenkins Console Output에서 `docker pull` 성공 확인
- Harbor UI에서 `devops/jenkins-harbor-test:<BUILD_NUMBER>` tag 확인
- 빌드 실행 중 `jenkins-agents` namespace에 Agent Pod 생성 확인

## 보안 주의사항

- Harbor Robot Secret을 Pipeline Script에 직접 작성하지 않습니다.
- Jenkins Credential 권한은 필요한 사용자와 Folder로 제한합니다.
- `docker:dind` privileged Agent는 신뢰된 Job에만 사용합니다.
- 외부 사용자가 임의 Pipeline을 privileged Agent에서 실행하지 못하도록 권한을 제한합니다.
- 운영 서비스 이미지 push 권한은 프로젝트 단위 Robot Account로 분리합니다.

## 참고

- [Jenkins 설치](./installation.md)
- [Jenkins RKE2 Agent 설치](./kubernetes-agent-installation.md)
- [Harbor 설치](../harbor/installation.md)
