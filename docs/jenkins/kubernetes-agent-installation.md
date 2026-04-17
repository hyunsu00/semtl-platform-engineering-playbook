# Jenkins RKE2 Agent Installation

## 개요

이 문서는 VM에 설치된 Jenkins Controller가 `RKE2` 클러스터에
동적 Agent Pod를 생성하도록 연동하는 표준 절차를 정리합니다.

Jenkins 플러그인과 Web UI 용어는 `Kubernetes`로 표시되지만,
이 문서의 실제 대상 환경은 `RKE2`입니다.

이 문서의 목표는 아래 상태까지 한 번에 만드는 것입니다.

- Jenkins Controller는 VM에서 계속 실행
- 실제 빌드는 `RKE2` 위의 `Pod` 기반 Agent에서 수행
- Agent 전용 namespace, service account, RBAC 적용 완료
- Jenkins Web UI에서 `Kubernetes Cloud` 연결 성공
- 검증용 Pipeline이 `RKE2` Agent에서 정상 실행

## 사용 시점

- Jenkins Controller는 VM에 두고 빌드 실행만 `RKE2`로 분리하려는 경우
- Controller의 executor를 `0`으로 유지하고 싶은 경우
- 빌드 작업별로 깨끗한 Pod를 새로 띄우는 구조가 필요한 경우

## 최종 성공 기준

- `jenkins-agents` namespace 생성 완료
- `jenkins-agent` service account와 RBAC 적용 완료
- Jenkins VM에 `/var/lib/jenkins/.kube/config` 배치 완료
- Jenkins UI `Manage Jenkins -> Clouds`에서 연결 테스트 성공
- `agent { label 'k8s' }` Pipeline이 성공하고 Agent Pod가 자동 삭제됨

## 사전 조건

- [Jenkins 설치](./installation.md) 완료
- [RKE2 설치](../rke2/installation.md) 완료
- Jenkins 관리자 계정 준비 완료
- `kubectl`이 가능한 관리 노드에서 대상 `RKE2` 클러스터 접속 가능
- Jenkins URL이 외부 또는 내부에서 정상 접근 가능
- Controller의 executor가 `0`으로 설정되어 있음

권장 운영값:

- namespace: `jenkins-agents`
- service account: `jenkins-agent`
- pod label: `k8s`
- 작업 디렉터리: `/home/jenkins/agent`
- 연결 방식: `WebSocket`

## 구성 기준

- Jenkins Controller는 VM에 유지합니다.
- Jenkins Agent는 빌드 시점에만 `RKE2` Pod로 생성합니다.
- Agent용 권한은 전용 namespace 범위로 제한합니다.
- Jenkins에서 `RKE2` Kubernetes API 접근 시 전용 `kubeconfig`를 사용합니다.
- `JNLP TCP 50000` 대신 `WebSocket`을 우선 사용합니다.

## 1. Jenkins Controller에 Kubernetes 플러그인 설치

Jenkins VM에서 아래 명령을 실행합니다.

```bash
sudo tee /var/lib/jenkins/plugins-k8s.txt >/dev/null <<'EOF'
kubernetes
kubernetes-credentials
kubernetes-credentials-provider
EOF

sudo chown jenkins:jenkins /var/lib/jenkins/plugins-k8s.txt

JENKINS_ADMIN_ID=$(sudo sed -n "s/^JENKINS_ADMIN_ID='\\(.*\\)'$/\\1/p" \
  /var/lib/jenkins/jenkins-admin.env)
JENKINS_ADMIN_PASSWORD=$(
  sudo sed -n "s/^JENKINS_ADMIN_PASSWORD='\\(.*\\)'$/\\1/p" \
  /var/lib/jenkins/jenkins-admin.env
)

if [ ! -f /tmp/jenkins-cli.jar ]; then
  curl -fsSL -o /tmp/jenkins-cli.jar \
    http://127.0.0.1:8080/jnlpJars/jenkins-cli.jar
fi

PLUGINS_K8S="$(tr '\n' ' ' </var/lib/jenkins/plugins-k8s.txt)"
java -jar /tmp/jenkins-cli.jar -http \
  -s http://127.0.0.1:8080/ \
  -auth "${JENKINS_ADMIN_ID}:${JENKINS_ADMIN_PASSWORD}" \
  install-plugin ${PLUGINS_K8S} -restart
```

확인:

```bash
curl -fsSL --user "${JENKINS_ADMIN_ID}:${JENKINS_ADMIN_PASSWORD}" \
  "http://127.0.0.1:8080/pluginManager/api/json?depth=1" \
  | grep -E '"shortName":"(kubernetes|kubernetes-credentials|kubernetes-credentials-provider)"'
```

기대 결과:

- 세 플러그인 이름이 모두 출력됨

## 2. RKE2 namespace와 RBAC 생성

`kubectl`이 가능한 관리 노드에서 아래 매니페스트를 적용합니다.
이 단계는 일반 Kubernetes 명령처럼 보이지만 대상은 `RKE2` 클러스터입니다.

중요:

- 이 단계에서 생성하는 `Namespace`, `ServiceAccount`, `Role`,
  `RoleBinding`, `Secret`는 `PVC`, `Longhorn`, `NFS`, `local-path`
  같은 스토리지를 사용하지 않습니다.
- 위 리소스는 `kubectl apply` 시점에 `RKE2` control-plane의 datastore
  (일반적으로 `etcd`)에 저장됩니다.
- 즉, 이 단계는 "권한과 계정 구성" 단계이고, "스토리지 구성" 단계가 아닙니다.

```bash
mkdir -p ~/rke2/jenkins-agents

cat <<'EOF' >~/rke2/jenkins-agents/jenkins-agent-rbac.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: jenkins-agents
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins-agent
  namespace: jenkins-agents
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: jenkins-agent
  namespace: jenkins-agents
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["create", "delete", "get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["create", "get"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: jenkins-agent
  namespace: jenkins-agents
subjects:
  - kind: ServiceAccount
    name: jenkins-agent
    namespace: jenkins-agents
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: jenkins-agent
---
apiVersion: v1
kind: Secret
metadata:
  name: jenkins-agent-token
  namespace: jenkins-agents
  annotations:
    kubernetes.io/service-account.name: jenkins-agent
type: kubernetes.io/service-account-token
EOF

kubectl apply -f ~/rke2/jenkins-agents/jenkins-agent-rbac.yaml
kubectl -n jenkins-agents get sa,role,rolebinding,secret
```

매니페스트 설명:

- `Namespace`
  `jenkins-agents`라는 작업 전용 공간을 만듭니다.
- `ServiceAccount`
  Jenkins가 `RKE2` API를 호출할 때 사용할 Kubernetes 계정입니다.
- `Role`
  `jenkins-agents` namespace 안에서 Pod 생성, 조회, 삭제, 로그 확인에
  필요한 최소 권한을 정의합니다.
- `RoleBinding`
  위 `Role` 권한을 `jenkins-agent` ServiceAccount에 연결합니다.
- `Secret`
  `jenkins-agent` ServiceAccount용 토큰 Secret을 생성해 이후
  Jenkins 전용 `kubeconfig`를 만들 때 사용합니다.

운영 메모:

- 이 문서는 빌드용 Agent를 `jenkins-agents` namespace 안에만 띄우는 기준입니다.
- `secrets`의 `list`, `watch` 권한은 `kubernetes-credentials-provider`
  플러그인이 Kubernetes Secret을 Jenkins Credential로 감시할 때 필요합니다.
  이 권한이 없으면 Jenkins UI에 `Credentials from Kubernetes Secrets will not be
  available` 경고가 표시될 수 있습니다.
- 다른 namespace에도 Agent를 띄워야 하면 `Role/RoleBinding` 범위를 별도로 설계합니다.
- 장기 토큰을 쓰는 대신 kubeconfig를 정기적으로 재발급하는 운영 기준을 함께 두는 편이 안전합니다.

## 3. Jenkins 전용 kubeconfig 생성

같은 관리 노드에서 `RKE2` API 서버 주소와 ServiceAccount 토큰을 이용해
Jenkins 전용 kubeconfig를 만듭니다.

```bash
APISERVER=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}')
CA_DATA=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

echo "${APISERVER}"
```

확인:

- `APISERVER`는 Jenkins VM에서 접근 가능한 `RKE2` API 서버 주소여야 합니다.
- 예: `https://192.168.0.181:6443`
- `https://kubernetes.default.svc`처럼 Kubernetes 클러스터 내부 DNS 이름이면
  Jenkins VM에서는 해석할 수 없으므로 사용하지 않습니다.

관리 노드의 kubeconfig가 클러스터 내부 주소를 가리킨다면 Jenkins VM에서 접근 가능한
주소로 직접 지정합니다.

```bash
APISERVER="https://192.168.0.181:6443"
```

ServiceAccount 토큰을 읽어 kubeconfig를 생성합니다.

```bash
until kubectl -n jenkins-agents get secret jenkins-agent-token \
  -o jsonpath='{.data.token}' | grep -q .; do
  sleep 2
done

TOKEN=$(
  kubectl -n jenkins-agents get secret jenkins-agent-token \
    -o jsonpath='{.data.token}' | base64 -d
)

cat <<EOF >~/rke2/jenkins-agents/jenkins-agent.kubeconfig
apiVersion: v1
kind: Config
clusters:
  - name: jenkins-k8s
    cluster:
      certificate-authority-data: ${CA_DATA}
      server: ${APISERVER}
contexts:
  - name: jenkins-k8s
    context:
      cluster: jenkins-k8s
      namespace: jenkins-agents
      user: jenkins-agent
current-context: jenkins-k8s
users:
  - name: jenkins-agent
    user:
      token: ${TOKEN}
EOF

kubectl --kubeconfig "$HOME/rke2/jenkins-agents/jenkins-agent.kubeconfig" \
  auth can-i create pods -n jenkins-agents
kubectl --kubeconfig "$HOME/rke2/jenkins-agents/jenkins-agent.kubeconfig" \
  get pods -n jenkins-agents
```

기대 결과:

- `yes`가 출력됨
- `No resources found in jenkins-agents namespace.` 또는 Pod 목록이 출력됨

## 4. Jenkins VM에 kubectl 설치

Jenkins VM에서 `kubectl` 검증을 수행하려면 CLI를 먼저 설치합니다.

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl

kubectl version --client
```

기대 결과:

- `Client Version`이 출력됨

운영 메모:

- Jenkins Kubernetes 플러그인 자체는 `kubectl` 없이도 동작할 수 있습니다.
- 다만 이 문서는 Jenkins VM에서 `kubeconfig` 검증까지 수행하는 흐름을 기준으로 하므로
  `kubectl` 설치를 포함합니다.

## 5. Jenkins VM에 kubeconfig 배치

생성한 kubeconfig를 Jenkins 서비스 계정 홈으로 복사합니다.

```bash
scp "$HOME/rke2/jenkins-agents/jenkins-agent.kubeconfig" \
  <JENKINS-VM-USER>@<JENKINS-VM-IP>:/tmp/jenkins-agent.kubeconfig
```

Jenkins VM에서 아래 명령을 실행합니다.

```bash
sudo install -d -m 700 -o jenkins -g jenkins /var/lib/jenkins/.kube
sudo mv /tmp/jenkins-agent.kubeconfig /var/lib/jenkins/.kube/config
sudo chown jenkins:jenkins /var/lib/jenkins/.kube/config
sudo chmod 600 /var/lib/jenkins/.kube/config
```

Jenkins JVM이 같은 kubeconfig를 명시적으로 사용하도록 systemd 환경 변수를 설정합니다.
이 설정은 `kubernetes-credentials-provider` 플러그인이 기본값인
`kubernetes.default.svc`로 빠지지 않게 하는 데 중요합니다.

```bash
sudo systemctl edit jenkins
```

아래 내용을 입력합니다.

```ini
[Service]
Environment="HOME=/var/lib/jenkins"
Environment="KUBECONFIG=/var/lib/jenkins/.kube/config"
```

설정을 적용하고 Jenkins를 재시작합니다.

```bash
sudo systemctl daemon-reload
sudo systemctl restart jenkins
```

검증:

```bash
sudo systemctl show jenkins -p Environment

sudo -u jenkins KUBECONFIG=/var/lib/jenkins/.kube/config \
  kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}{"\n"}'
sudo -u jenkins KUBECONFIG=/var/lib/jenkins/.kube/config \
  kubectl auth can-i create pods -n jenkins-agents
sudo -u jenkins KUBECONFIG=/var/lib/jenkins/.kube/config \
  kubectl auth can-i list secrets -n jenkins-agents
sudo -u jenkins KUBECONFIG=/var/lib/jenkins/.kube/config \
  kubectl auth can-i watch secrets -n jenkins-agents
sudo -u jenkins KUBECONFIG=/var/lib/jenkins/.kube/config \
  kubectl get pods -n jenkins-agents
```

기대 결과:

- `Environment=`에 `HOME=/var/lib/jenkins`와
  `KUBECONFIG=/var/lib/jenkins/.kube/config`가 포함됨
- Kubernetes API 서버 주소가 `https://192.168.0.181:6443`처럼
  Jenkins VM에서 접근 가능한 주소로 출력됨
- `yes`가 출력됨
- Secret 목록 권한 확인도 `yes`가 출력됨
- `No resources found in jenkins-agents namespace.` 또는 Pod 목록이 출력됨

운영 메모:

- `kubectl get ns`는 cluster-scope 권한이 필요하므로 이 문서의 최소권한
  `ServiceAccount` 검증 명령으로는 사용하지 않습니다.
- `kubernetes-credentials-provider`를 설치한 상태에서는 Jenkins 재시작 후
  `Manage Jenkins -> System Log`에서 `kubernetes.default.svc` 관련
  `UnknownHostException`이 더 이상 발생하지 않아야 합니다.

## 6. [Jenkins Web UI] Kubernetes Cloud 설정

Jenkins UI 경로:

`Manage Jenkins -> Clouds -> New cloud -> Kubernetes`

빠른 입력 요약:

```text
Name: kubernetes
Kubernetes URL: https://192.168.0.181:6443
Use Jenkins Proxy: OFF
Kubernetes server certificate key: (비움)
Disable https certificate check: ON
Kubernetes Namespace: jenkins-agents
Agent Docker Registry: (비움)
Inject restricted PSS security context in agent container definition: OFF
Credentials: - none -
WebSocket: ON
Direct Connection: OFF
Jenkins URL: https://jenkins.semtl.synology.me/
Jenkins tunnel: (비움)
Connection Timeout: 5
Read Timeout: 15
Concurrency Limit: 10
Pod Labels:
- Key: k8s
- Value: true
Pod Retention: Never
Max connections to Kubernetes API: 32
Seconds to wait for pod to be running: 600
Container Cleanup Timeout: 5
Transfer proxy related environment variables from controller to agent: OFF
Restrict pipeline support to authorized folders: OFF
Defaults Provider Template Name: (비움)
Enable garbage collection: OFF
```

입력 기준:

- Name: `kubernetes`
- Kubernetes URL: `https://192.168.0.181:6443`
- Use Jenkins Proxy: `OFF`
- Kubernetes server certificate key: 비움
- Disable https certificate check: `ON`
- Kubernetes Namespace: `jenkins-agents`
- Agent Docker Registry: 비움
- Inject restricted PSS security context in agent container definition: `OFF`
- Credentials: `- none -`
- WebSocket: `ON`
- Direct Connection: `OFF`
- Jenkins URL: `https://jenkins.semtl.synology.me/`
- Jenkins tunnel: 비움
- Connection Timeout: `5`
- Read Timeout: `15`
- Concurrency Limit: `10`
- Pod Labels:
  - Key: `k8s`
  - Value: `true`
- Pod Retention: `Never`
- Max connections to Kubernetes API: `32`
- Seconds to wait for pod to be running: `600`
- Container Cleanup Timeout: `5`
- Transfer proxy related environment variables from controller to agent: `OFF`
- Restrict pipeline support to authorized folders: `OFF`
- Defaults Provider Template Name: 비움
- Enable garbage collection: `OFF`

설정 기준:

- 이 문서는 Jenkins 서비스 계정 홈의 `/var/lib/jenkins/.kube/config`를 사용하는 기준입니다.
- 현재 구성은 `Credentials`를 따로 만들지 않고 Jenkins 로컬 kubeconfig를
  사용하는 기준입니다.
- `Test Connection`을 눌렀을 때 성공해야 다음 단계로 진행합니다.
- `WebSocket`을 켜면 별도 `50000/TCP` 공개 없이 Agent 연결이 가능합니다.
- `Jenkins URL`은 Agent Pod 안에서 도달 가능한 주소여야 합니다.
- 현재 화면 기준으로는 `Disable https certificate check`를 `ON`으로 두고
  빠르게 검증하는 방식을 사용합니다.
- `Cloud` 이름과 플러그인 이름은 `Kubernetes`로 보이지만
  실제 연결 대상은 `RKE2` API 서버입니다.

## 7. [Jenkins Web UI] Pod Template 생성

같은 `Kubernetes Cloud` 화면에서 기본 Pod Template을 추가합니다.

이미지 기준 입력 순서:

```text
Name: k8s-default
Namespace: jenkins-agents
Labels: k8s
Usage: Only build jobs with label expressions matching this node
Pod template to inherit from: (비움)
Name of the container that will run the Jenkins agent: jnlp
Inject Jenkins agent in agent container: OFF
Containers:
- Name: jnlp
- Docker image: jenkins/inbound-agent:latest-jdk17
- Always pull image: OFF
- Working directory: /home/jenkins/agent
- Command to run: (비움)
- Arguments to pass to the command: (비움)
- Allocate pseudo-TTY: OFF
Environment variables: (비움)
Volumes: (비움)
Annotations: (비움)
Concurrency Limit: 10
Pod Retention: Never
Time in minutes to retain agent when idle: 0
Time in seconds for Pod deadline: 600
Timeout in seconds for Jenkins connection: 100
Raw YAML for the Pod: (비움)
Yaml merge strategy: Override
Inherit yaml merge strategy: OFF
Show raw yaml in console: OFF
ImagePullSecrets: (비움)
Service Account: jenkins-agent
Run As User ID: 1000
Run As Group ID: 1000
Supplemental Groups: (비움)
Host Network: OFF
Node Selector: (비움)
Workspace Volume: Empty Dir Workspace Volume
Size limit: 10Gi
In Memory: OFF
Tool Locations: OFF
```

권장 입력값:

- Name: `k8s-default`
- Namespace: `jenkins-agents`
- Labels: `k8s`
- Usage: `Only build jobs with label expressions matching this node`
- Pod template to inherit from: 비움
- Name of the container that will run the Jenkins agent: `jnlp`
- Inject Jenkins agent in agent container: `OFF`
- Environment variables: 비움
- Volumes: 비움
- Annotations: 비움
- Concurrency Limit: `10`
- Pod Retention: `Never`
- Time in minutes to retain agent when idle: `0`
- Time in seconds for Pod deadline: `600`
- Timeout in seconds for Jenkins connection: `100`
- Raw YAML for the Pod: 비움
- Yaml merge strategy: `Override`
- Inherit yaml merge strategy: `OFF`
- Show raw yaml in console: `OFF`
- ImagePullSecrets: 비움
- Service Account: `jenkins-agent`
- Run As User ID: `1000`
- Run As Group ID: `1000`
- Supplemental Groups: 비움
- Host Network: `OFF`
- Node Selector: 비움
- Workspace Volume: `Empty Dir Workspace Volume`
- Size limit: `10Gi`
- In Memory: `OFF`
- Tool Locations: `OFF`

컨테이너 추가:

- `Add Container`를 눌러 아래 값으로 `jnlp` 컨테이너를 추가합니다.
- Name: `jnlp`
- Docker image: `jenkins/inbound-agent:latest-jdk17`
- Always pull image: `OFF`
- Working directory: `/home/jenkins/agent`
- Command to run: 비움
- Arguments to pass to the command: 비움
- Allocate pseudo-TTY: `OFF`

운영 메모:

- `Name of the container that will run the Jenkins agent` 값은
  아래 `Containers`에 추가한 컨테이너 이름과 동일하게 `jnlp`로 맞춥니다.
- `jnlp` 컨테이너는 Jenkins inbound agent 프로세스를 직접 시작해야 하므로
  `Command to run`, `Arguments to pass to the command`는 비워 두는 것을 권장합니다.
- 여기서 `sleep 9999999`처럼 엔트리포인트를 덮어쓰면 Pod는 떠 있어도
  Jenkins agent가 Controller에 연결되지 않아 `is offline` 상태가 날 수 있습니다.
- `Service Account`는 앞 단계에서 생성한 `jenkins-agent`를 그대로 사용합니다.
- `Run As User ID`와 `Run As Group ID`를 `1000`으로 맞추면
  일반적인 Jenkins inbound agent 이미지 기준 파일 권한 충돌을 줄이기 쉽습니다.
- `Workspace Volume`은 별도 PVC 없이 시작하기 위해
  `Empty Dir Workspace Volume`을 기본값으로 사용합니다.
- 빌드에 `docker`, `kubectl`, `helm`, `node`, `maven` 등이 필요하면
  `jnlp` 단일 컨테이너 대신 팀 표준 빌드 이미지를 별도 추가합니다.
- 운영 안정성을 위해 `latest` 계열 태그 대신 검증된 사내 표준 태그로 고정하는 것을 권장합니다.

## 8. Jenkins devops Folder 생성

Jenkins UI에서 운영 Job을 묶을 `devops` Folder를 생성합니다.

Jenkins UI 경로:

`Dashboard -> New Item`

입력값:

- Item name: `devops`
- Job type: `Folder`

입력 후 `OK`를 선택합니다.

Folder 설정 입력값:

- Display Name: `devops`
- Description: `DevOps CI jobs and Kubernetes agent tests`
- Health metrics: 기본값 유지
- Docker Label: 비움
- Docker registry URL: 비움
- Registry credentials: `- none -`
- Pipeline libraries: 추가하지 않음
- Kubernetes: `-- none --`

입력 후 `Save`를 선택합니다.

생성 확인:

- Jenkins Dashboard에 `devops` Folder가 표시됨
- `devops` Folder 상세 화면에 진입 가능

운영 메모:

- GitLab group, Harbor project 이름과 맞춰 `devops`를 사용합니다.
- Folder 단위로 Job, Credential, 권한을 묶으면 운영 범위를 이해하기 쉽습니다.
- `Docker registry URL`과 `Registry credentials`는 Folder 기본값으로 쓰는 항목입니다.
  개별 Pipeline에서 Credential을 직접 사용할 경우 비워 둡니다.
- `Kubernetes` 제한 항목은 특정 Cloud만 허용할 때 사용합니다.
  기본 검증 Job은 `agent { label 'k8s' }`로 Agent를 선택하므로 기본값을 유지합니다.
- Jenkins Folder 항목이 보이지 않으면 `CloudBees Folder` 플러그인 설치 여부를 확인합니다.

## 9. 검증용 Pipeline 생성

Jenkins UI에서 `devops` Folder 안에 새 Pipeline Job을 생성합니다.

Jenkins UI 경로:

`Dashboard -> devops -> New Item`

권장값:

- Item name: `k8s-agent-smoke-test`
- Job type: `Pipeline`

운영 메모:

- Job 전체 경로는 `devops/k8s-agent-smoke-test`입니다.

Pipeline 스크립트 예시:

```groovy
pipeline {
  agent { label 'k8s' }

  stages {
    stage('Environment Check') {
      steps {
        sh 'hostname'
        sh 'id'
        sh 'pwd'
        sh 'printenv | sort | grep -E \"JENKINS_URL|JOB_NAME|NODE_NAME\" || true'
      }
    }
  }
}
```

실행 중 확인:

```bash
sudo -u jenkins kubectl --kubeconfig /var/lib/jenkins/.kube/config \
  -n jenkins-agents get pods -w
```

설명:

- Jenkins Agent Pod 확인은 일반 사용자 셸 기본 kubeconfig가 아니라
  `jenkins` 계정이 실제로 사용하는 `/var/lib/jenkins/.kube/config` 기준으로 확인합니다.
- 이 명령은 watch 모드이므로 현재 Pod가 없으면 출력 없이 대기할 수 있습니다.
- 문서 기준 `Pod Retention: Never`에서는 빌드 종료 후 Agent Pod가 빠르게 삭제될 수 있으므로
  Job 실행 전에 미리 watch를 걸어 두고 확인하는 편이 가장 확실합니다.

기대 결과:

- 빌드 시작 시 `jenkins-agent` Pod가 생성됨
- `Console Output`에 `Agent <pod-name> is provisioned from template k8s-default`가
  출력됨
- `Running on <pod-name> in /home/jenkins/agent/workspace/<job-name>`가 출력됨
- `Console Output`에 shell 명령 결과가 출력됨
- `id` 결과에 `uid=1000(jenkins) gid=1000(jenkins)`가 출력됨
- `pwd` 결과가 `/home/jenkins/agent/workspace/devops/k8s-agent-smoke-test`
  또는 Jenkins가 Folder 경로를 인코딩한 workspace 경로로 출력됨
- `printenv` 결과에 `JENKINS_URL`, `JOB_NAME`, `NODE_NAME`이 표시됨
- 마지막에 `Finished: SUCCESS`가 출력됨
- 빌드 종료 후 Pod가 자동 삭제되거나 `Completed` 후 정리됨

성공 예시 해석:

- `Agent k8s-default-xxxxx is provisioned from template k8s-default`
  Agent Pod가 `k8s-default` Pod Template 기준으로 정상 생성됐다는 뜻입니다.
- `Running on k8s-default-xxxxx in /home/jenkins/agent/workspace/...`
  실제 빌드가 Controller가 아니라 Kubernetes Agent Pod 내부에서 실행 중이라는 뜻입니다.
- `uid=1000(jenkins) gid=1000(jenkins)`
  문서에서 설정한 `Run As User ID`, `Run As Group ID`가 기대대로 적용됐는지 확인할 수 있습니다.
- `JENKINS_URL=...`, `JOB_NAME=...`, `NODE_NAME=...`
  Jenkins agent가 Controller와 연결된 상태로 필요한 환경변수를 전달받았는지 확인할 수 있습니다.
- `kubectl get pods -w`에서 마지막 상태가 `Error`로 보여도
  Jenkins 콘솔이 `Finished: SUCCESS`면 정상 완료로 봅니다.

실패 예시와 해석:

- `Still waiting to schedule task`가 오래 지속되면서
  ``k8s-default-xxxxx is offline`` 이 출력되면 Pod는 생성됐지만
  Jenkins agent가 Controller에 연결되지 못한 상태입니다.
- 이 경우 가장 먼저 `Pod Template -> Containers -> jnlp`의
  `Command to run`, `Arguments to pass to the command`가 비어 있는지 확인합니다.
- `sleep 9999999`처럼 값을 넣어 이미지 기본 엔트리포인트를 덮어쓰면
  컨테이너는 떠 있어도 Jenkins inbound agent 프로세스가 시작되지 않습니다.
- Jenkins 로그에 `java.net.UnknownHostException: kubernetes.default.svc`와
  `Credentials from Kubernetes Secrets will not be available`가 함께 표시되면
  Jenkins JVM이 `/var/lib/jenkins/.kube/config`를 읽지 못하고 Kubernetes 내부
  기본 주소로 API 서버를 찾는 상태입니다.
- 이 경우 `sudo systemctl show jenkins -p Environment` 결과에
  `HOME=/var/lib/jenkins`와 `KUBECONFIG=/var/lib/jenkins/.kube/config`가
  포함되어 있는지 확인하고, kubeconfig의 `server` 값이
  `https://192.168.0.181:6443`처럼 Jenkins VM에서 접근 가능한 주소인지 확인합니다.
- `kubernetes-credentials-provider`를 사용하는 경우 `jenkins-agent`
  ServiceAccount에 `secrets`의 `get`, `list`, `watch` 권한이 있어야 합니다.

## 검증 방법

아래 항목을 모두 확인합니다.

- Jenkins UI `Clouds`의 `Test Connection` 성공
- `devops/k8s-agent-smoke-test` Job 성공
- `sudo -u jenkins kubectl --kubeconfig /var/lib/jenkins/.kube/config`
  명령으로 Agent Pod 생성 이력 확인
- Controller에서 실제 빌드가 실행되지 않고 `RKE2` Pod에서만 실행됨

## 참고

- [Jenkins 설치](./installation.md)
- [RKE2 설치](../rke2/installation.md)
- [MinIO Jenkins 연동](../minio/jenkins-integration.md)
