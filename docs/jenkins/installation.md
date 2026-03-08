# Jenkins Installation

## 개요

이 문서는 Kubernetes(HA 클러스터) 위에 Jenkins를 Helm으로 설치하는 절차를 정의합니다.

## 사전 조건

- Kubernetes 클러스터 정상 상태
- `kubectl` 컨텍스트 연결 완료
- MetalLB 등 LoadBalancer 할당 가능
- 설치 방식: Helm
- Jenkins 워크로드 수용 노드 리소스 기준: 최소 `2 vCPU / 8GB RAM`
- Jenkins 워크로드 수용 노드 디스크 기준: `200GB+` (운영 확장 시 `1TB` 디스크 추가 예정)

### Proxmox VM H/W 참고 이미지

아래 이미지는 Jenkins 워크로드를 수용하는 Kubernetes 노드의 Proxmox `Hardware` 탭 기준 예시입니다.

![Proxmox VM Hardware - Jenkins](../assets/images/jenkins/proxmox-vm-hw-jenkins-v1.png)

캡션: `4 vCPU`, `8GB RAM`, Data Disk `200GB+`
향후 Data Disk `1TB` 추가 예정

## 배치 원칙

- Jenkins는 Kubernetes에 배치
- 상태 저장 서비스는 VM 원칙과 분리
- 외부 노출은 Synology Reverse Proxy 경유

## 설치 절차

### 1. Helm 저장소 추가

```bash
# Jenkins Helm 저장소 추가
helm repo add jenkins https://charts.jenkins.io
helm repo update
```

### 2. values 파일 작성

`jenkins-values.yaml` 예시:

```yaml
controller:
  serviceType: LoadBalancer
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "2"
      memory: "4Gi"
  numExecutors: 2
```

운영 시작 기준:

- executor: `2~4`
- workload 증가 시 단계적으로 상향

### 3. Jenkins 설치

```bash
# jenkins 네임스페이스에 설치
helm upgrade --install jenkins jenkins/jenkins \
  --namespace jenkins \
  --create-namespace \
  -f jenkins-values.yaml
```

## 방화벽/포트 체크

- Jenkins 서비스 타입: `LoadBalancer`
- 할당 IP(`192.168.0.20X`)를 Synology Reverse Proxy 대상으로 등록
- 외부 공개 포트는 Reverse Proxy 정책에 맞춰 제한

## 설치 검증

```bash
# 파드 상태 확인
kubectl -n jenkins get pods

# 서비스/외부 IP 확인
kubectl -n jenkins get svc
```

검증 기준:

- `controller` 파드 `Running`
- `EXTERNAL-IP` 할당 완료
- Reverse Proxy 도메인으로 UI 접속 가능

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

- 초기 관리자 비밀번호 확인 후
- 플러그인 대량 설치 전

권장 이름:

- `BASE-Jenkins-on-K8s`

## 참고

- Runner/CI 부하는 Kubernetes로 수용
- CT 기반 Jenkins 배치는 본 표준에서 제외
