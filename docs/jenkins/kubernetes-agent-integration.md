# Jenkins Kubernetes Agent Integration

## 개요

이 문서는 Jenkins VM 설치 이후 Kubernetes Agent 연동 절차를 정의합니다.
기본 설치 단계에서는 Kubernetes 플러그인을 설치하지 않고, 본 문서에서 추가합니다.

## 사전 조건

- Jenkins 기본 설치 완료
- Jenkins 관리자 계정 준비
- Kubernetes API 접근 가능한 `kubeconfig` 준비

## 1. Kubernetes 플러그인 목록 준비

```bash
sudo tee /var/lib/jenkins/plugins-k8s.txt >/dev/null <<'EOF'
kubernetes
kubernetes-credentials
kubernetes-credentials-provider
EOF

sudo chown jenkins:jenkins /var/lib/jenkins/plugins-k8s.txt
```

## 2. kubeconfig 배치

```bash
sudo install -d -m 700 -o jenkins -g jenkins /var/lib/jenkins/.kube
sudo cp ~/.kube/config /var/lib/jenkins/.kube/config
sudo chown jenkins:jenkins /var/lib/jenkins/.kube/config
sudo chmod 600 /var/lib/jenkins/.kube/config
```

## 3. Kubernetes 플러그인 설치

```bash
JENKINS_ADMIN_ID=$(sudo sed -n "s/^JENKINS_ADMIN_ID='\\(.*\\)'$/\\1/p" \
  /var/lib/jenkins/jenkins-admin.env)
JENKINS_ADMIN_PASSWORD=$(
  sudo sed -n "s/^JENKINS_ADMIN_PASSWORD='\\(.*\\)'$/\\1/p" \
  /var/lib/jenkins/jenkins-admin.env
)

PLUGINS_K8S="$(tr '\n' ' ' </var/lib/jenkins/plugins-k8s.txt)"
java -jar /tmp/jenkins-cli.jar -http \
  -s http://127.0.0.1:8080/ \
  -auth "${JENKINS_ADMIN_ID}:${JENKINS_ADMIN_PASSWORD}" \
  install-plugin ${PLUGINS_K8S} -restart
```

## 검증

```bash
curl -fsSL --user "${JENKINS_ADMIN_ID}:${JENKINS_ADMIN_PASSWORD}" \
  "http://127.0.0.1:8080/pluginManager/api/json?depth=1" \
  | grep -E '"shortName":"(kubernetes|kubernetes-credentials|kubernetes-credentials-provider)"'
```
