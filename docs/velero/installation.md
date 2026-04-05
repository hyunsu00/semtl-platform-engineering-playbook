# Velero Installation (작업중)

## 개요

이 문서는 이 저장소의 Kubernetes 표준 환경에 `Velero`를 설치하고,
`MinIO`를 백업 저장소로 연결한 뒤 초기 백업 검증까지 수행하는 절차를 정리합니다.

이 문서의 기준은 다음과 같습니다.

- 대상 클러스터는 [`k8s 설치 문서`](../k8s/installation.md) 기준으로 이미 구축되어 있습니다.
- 스토리지 기준은 [`K8s Storage Guide`](../k8s/storage-guide.md)를 따릅니다.
- 운영 핵심 스택 PVC는 `Longhorn`을 사용합니다.
- Velero 백업 저장소는 `MinIO`의 S3 호환 API를 사용합니다.
- 초기 설치는 `node-agent` 기반 파일시스템 백업을 기본값으로 사용합니다.

이 문서의 목표는 실패 사례를 배제하고, 최소 설정으로 한 번에 설치가 끝나는
성공 경로를 제공하는 것입니다.

## 사전 조건

- Kubernetes 클러스터가 정상이며 `kubectl` 접근이 가능합니다.
- `helm` CLI가 설치되어 있습니다.
- `Longhorn`이 정상 동작 중입니다.
- `MinIO`가 이미 설치되어 있고 S3 API endpoint 접근이 가능합니다.
- `vm-admin` 또는 운영 노드에서 `mc`로 MinIO를 관리할 수 있습니다.

사전 확인 명령:

```bash
kubectl get nodes
kubectl get storageclass
kubectl -n longhorn-system get pods
helm version
mc --version
```

정상 기준:

- 모든 노드가 `Ready`
- `longhorn` StorageClass가 존재
- `longhorn-system` 주요 파드가 `Running`
- `helm version`이 정상 응답
- `mc --version`이 정상 응답

공식 기준 참고:

- Velero는 백업 데이터를 저장할 `object storage`가 필요합니다.
- `node-agent`는 파일시스템 백업용 DaemonSet으로 동작합니다.
- `BackupStorageLocation`은 백업 메타데이터와 파일시스템 백업 데이터의 저장 위치입니다.

## 권장 아키텍처

- 설치 네임스페이스: `velero`
- 백업 저장소: `MinIO`
- 백업 버킷 예시: `velero`
- MinIO API endpoint 예시: `http://192.168.0.171:9000`
- Velero provider: `aws` 플러그인
- 볼륨 백업 방식: `node-agent` 기반 파일시스템 백업

운영 메모:

- 이 문서 기준 초기 설치는 `VolumeSnapshotLocation`을 만들지 않습니다.
- `Longhorn` CSI 스냅샷 연동보다 먼저 `node-agent` 기반 백업이 정상 동작하는지 확인합니다.
- 백업 저장소 credentials는 Velero 전용 MinIO 계정을 따로 만들어 사용하는 것을 권장합니다.

## 설치 절차

### 1. MinIO 버킷과 전용 계정 준비

이 단계는 `MinIO` 관리가 가능한 노드에서 수행합니다.

예시:

```bash
mc alias set local http://192.168.0.171:9000 admin '<change-required>'
mc mb -p local/velero
```

Velero 전용 정책 파일 예시:

```bash
cat <<'EOF' > ~/k8s/velero/velero-minio-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads"
      ],
      "Resource": [
        "arn:aws:s3:::velero"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:AbortMultipartUpload",
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:ListMultipartUploadParts",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::velero/*"
      ]
    }
  ]
}
EOF
```

정책과 계정 생성:

```bash
mkdir -p ~/k8s/velero

mc admin policy create local velero-policy ~/k8s/velero/velero-minio-policy.json
mc admin user add local velero '<change-required>'
mc admin policy attach local velero-policy --user velero
```

확인:

```bash
mc ls local/velero
mc admin user info local velero
```

### 2. Velero credentials 파일 작성

운영 기준 파일을 `~/k8s/velero/credentials-velero`로 관리합니다.

```bash
mkdir -p ~/k8s/velero

cat <<'EOF' > ~/k8s/velero/credentials-velero
[default]
aws_access_key_id=velero
aws_secret_access_key=<change-required>
EOF
```

주의:

- 이 파일은 Git에 커밋하지 않습니다.
- MinIO root 계정 대신 Velero 전용 계정을 사용합니다.

### 3. Helm 저장소 등록

```bash
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update
```

확인:

```bash
helm search repo vmware-tanzu/velero
```

### 4. Values 파일 작성

운영 기준 값을 `~/k8s/velero/values-velero.yaml`로 관리합니다.

```bash
cat <<'EOF' > ~/k8s/velero/values-velero.yaml
credentials:
  useSecret: true
  existingSecret: ""
  secretContents:
    cloud: |
      [default]
      aws_access_key_id=velero
      aws_secret_access_key=<change-required>

configuration:
  backupStorageLocation:
    - name: default
      provider: aws
      bucket: velero
      default: true
      config:
        region: minio
        s3ForcePathStyle: "true"
        s3Url: http://192.168.0.171:9000
  volumeSnapshotLocation: []
  defaultVolumesToFsBackup: true

initContainers:
  - name: velero-plugin-for-aws
    image: velero/velero-plugin-for-aws:v1.13.0
    imagePullPolicy: IfNotPresent
    volumeMounts:
      - mountPath: /target
        name: plugins

deployNodeAgent: true
snapshotsEnabled: false

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
EOF
```

기본 구성 설명:

- `provider: aws`는 S3 호환 저장소를 위한 플러그인 기준입니다.
- `s3Url`은 MinIO API endpoint를 사용합니다.
- `s3ForcePathStyle: "true"`는 MinIO 같은 S3 호환 저장소에서 흔히 필요합니다.
- `deployNodeAgent: true`로 파일시스템 백업 DaemonSet을 함께 설치합니다.
- `defaultVolumesToFsBackup: true`로 PVC가 있는 워크로드를 기본 파일시스템 백업 경로로 처리합니다.
- `volumeSnapshotLocation: []`와 `snapshotsEnabled: false`로 초기 설치는 스냅샷 경로를 비활성화합니다.

### 5. Velero 설치

```bash
helm upgrade --install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  -f ~/k8s/velero/values-velero.yaml
```

설치 직후 확인:

```bash
helm list -n velero
kubectl -n velero get pods
kubectl -n velero get backupstoragelocation
kubectl -n velero get deployment,daemonset
```

정상 기준:

- `helm list -n velero`에 `velero` 릴리스가 조회됨
- `velero` Deployment가 생성되고 `Running`
- `node-agent` DaemonSet이 생성됨
- `BackupStorageLocation`이 생성됨

### 6. BackupStorageLocation 상태 확인

```bash
kubectl -n velero get backupstoragelocation -o wide
kubectl -n velero describe backupstoragelocation default
```

정상 기준:

- `default` BackupStorageLocation이 존재
- `PHASE`가 `Available`

### 7. 초기 백업 검증

Velero CLI가 있으면 아래처럼 바로 검증합니다.

```bash
velero backup create velero-smoke-test \
  --include-namespaces velero \
  --wait
```

확인:

```bash
velero backup get
velero backup describe velero-smoke-test --details
kubectl -n velero get backups
```

정상 기준:

- `velero-smoke-test` 상태가 `Completed`
- 백업 오류가 반복되지 않음

테스트 종료:

```bash
velero backup delete velero-smoke-test --confirm
```

CLI가 없으면 CR 기준으로도 확인할 수 있습니다.

```bash
kubectl -n velero get backups
kubectl -n velero describe backup velero-smoke-test
```

## 설치 검증

아래 검증을 모두 통과하면 기본 설치 완료로 판단합니다.

### 리소스 상태

```bash
kubectl -n velero get pods
kubectl -n velero get backupstoragelocation
kubectl -n velero get deployment,daemonset
```

정상 기준:

- `velero` Deployment `Running`
- `node-agent` DaemonSet 정상 배포
- `BackupStorageLocation` `Available`

### 로그 확인

```bash
kubectl -n velero logs deploy/velero --tail=100
```

확인 포인트:

- plugin 로딩 오류가 반복되지 않음
- object storage 연결 오류가 없음
- `BackupStorageLocation` validation 오류가 없음

## 운영 메모

별도 운영 가이드를 두지 않는 대신, 설치 직후부터 아래 기준을 기본 운영 원칙으로 사용합니다.

### 일일/주간 확인 항목

- `kubectl -n velero get backups`로 최근 백업 상태 확인
- `kubectl -n velero get backupstoragelocation`으로 저장소 상태 확인
- `kubectl -n velero logs deploy/velero --tail=100`로 최근 오류 확인
- `mc ls local/velero` 또는 MinIO Console에서 백업 데이터 적재 여부 확인

### 변경 관리 기준

- MinIO endpoint, bucket, credentials 변경 전에는 현재 values와 Secret을 먼저 백업합니다.
- `BackupStorageLocation` 변경 후에는 반드시 수동 백업 한 번으로 검증합니다.
- 스냅샷 경로를 나중에 추가할 때는 `VolumeSnapshotLocation`과 CSI 동작을 따로 검증합니다.

## 재설치 전 완전 정리

Values를 크게 바꿨거나 처음부터 다시 설치하고 싶다면 아래 순서로 정리합니다.

### 1. Helm 릴리스 제거

```bash
helm uninstall velero -n velero
```

확인:

```bash
helm list -n velero
```

### 2. 네임스페이스 전체 삭제

```bash
kubectl delete namespace velero
```

확인:

```bash
kubectl get ns velero
```

정상 기준:

- `NotFound`가 나오면 삭제 완료

### 3. 주의

- Helm 릴리스를 삭제해도 MinIO bucket 안의 실제 백업 데이터는 남습니다.
- 재설치 후 같은 bucket과 credentials를 쓰면 기존 백업 메타데이터를 다시 참조할 수 있습니다.
- bucket 자체를 비우는 작업은 운영 데이터 보존 여부를 먼저 확인한 뒤 수행합니다.

## 초기 트러블슈팅

### 증상: `BackupStorageLocation`이 `Unavailable`

확인 명령:

```bash
kubectl -n velero get backupstoragelocation
kubectl -n velero describe backupstoragelocation default
kubectl -n velero logs deploy/velero --tail=100
```

주요 원인:

- MinIO endpoint 오입력
- bucket 미생성
- access key / secret key 오류
- 네트워크 경로 또는 방화벽 문제

조치:

- `s3Url`, bucket 이름, credentials 값을 다시 확인합니다.
- MinIO bucket이 실제로 존재하는지 확인합니다.
- MinIO API endpoint가 클러스터 노드에서 접근 가능한지 확인합니다.

### 증상: `node-agent`가 일부 노드에 뜨지 않음

확인 명령:

```bash
kubectl -n velero get daemonset
kubectl -n velero get pods -o wide
kubectl describe node <node-name>
```

주요 원인:

- 특정 노드 taint
- 자원 부족
- 보안 정책 또는 hostPath 제약

조치:

- `node-agent`가 어떤 노드에 빠졌는지 먼저 확인합니다.
- 해당 노드의 taint와 자원 상태를 확인합니다.
- 플랫폼별 hostPath 수정이 필요한 특수 배포판인지 공식 문서를 다시 확인합니다.

## 참고

- Kubernetes 클러스터 기본 설치: [`../k8s/installation.md`](../k8s/installation.md)
- 스토리지 역할 구분: [`../k8s/storage-guide.md`](../k8s/storage-guide.md)
- MinIO 설치: [`../minio/installation.md`](../minio/installation.md)
- [Velero 개요](https://velero.io/docs/main/)
- [Velero Basic Install](https://velero.io/docs/main/basic-install/)
- [Velero File System Backup](https://velero.io/docs/main/file-system-backup/)
- [Velero BackupStorageLocation / VolumeSnapshotLocation](https://velero.io/docs/main/locations/)
- [Velero Helm chart](https://github.com/vmware-tanzu/helm-charts/tree/main/charts/velero)
