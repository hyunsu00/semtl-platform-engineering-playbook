# K8s Storage Guide

## 개요

이 문서는 이 저장소의 Kubernetes 환경에서 사용할 스토리지 표준을 정리합니다.

핵심 목적은 다음과 같습니다.

- 앱별로 어떤 스토리지를 써야 하는지 기준을 통일
- 설치 문서마다 중복되는 스토리지 설명을 줄임
- Rancher, Prometheus, Grafana 같은 운영 핵심 스택의 저장소 전략을 미리 정리

이 문서의 기본 방향은 아래와 같습니다.

- `Longhorn`: 운영 핵심 스택용 기본 스토리지
- `NFS`: 일반 앱 데이터 및 공유성 높은 데이터용
- `local`: 임시 테스트용

## 스토리지 표준

### 1. Longhorn

권장 사용 대상:

- `Rancher`
- `Prometheus`
- `Grafana`
- 운영 핵심 관리 스택
- 노드 장애 시에도 상대적으로 유연한 복구가 필요한 워크로드

장점:

- Kubernetes 내부에서 분산 스토리지처럼 운영 가능
- 볼륨 복제, 스냅샷, 백업 같은 기능을 활용하기 좋음
- NAS 단일 장애점 의존도를 줄일 수 있음

주의:

- NFS보다 구성과 운영 복잡도가 높음
- 디스크와 네트워크 리소스를 더 사용함
- 홈랩에서도 충분히 쓸 수 있지만 운영 부담은 더 큼

### 2. NFS (`nfs-client`)

권장 사용 대상:

- 일반 앱 데이터
- 공유성 높은 파일 데이터
- 백업, 업로드 파일, 문서, 첨부 파일
- NAS 의존을 감수할 수 있는 워크로드

장점:

- 구조가 단순하고 이해하기 쉬움
- Synology NAS와 쉽게 연결 가능
- 여러 앱에서 재사용하기 편함

주의:

- NAS 장애 시 NFS PVC를 쓰는 앱도 영향을 받음
- Prometheus 같은 지속 쓰기 성격 워크로드에는 Longhorn보다 덜 적합할 수 있음

### 3. Local

권장 사용 대상:

- 임시 테스트
- 실험성 워크로드
- 성능 비교용

주의:

- 특정 노드에 강하게 종속됨
- 노드 이동이나 장애 복구에 취약함
- 운영 기본 스토리지로는 사용하지 않음

## 앱별 권장 기준

| 분류 | 권장 StorageClass | 비고 |
| --- | --- | --- |
| Rancher | `longhorn` | 운영 핵심 스택 |
| Prometheus | `longhorn` | 메트릭 저장소 |
| Grafana | `longhorn` | 운영 핵심 스택 |
| 일반 앱 데이터 | `nfs-client` | 파일성/공유성 데이터 |
| 임시 테스트 앱 | `local` | 운영 비권장 |

## 기본 원칙

### 기본 StorageClass

권장 기본값:

- `longhorn`

이유:

- 운영 핵심 스택이 실수로 `NFS`나 `local`에 올라가는 일을 줄일 수 있음
- 이후 Rancher, Prometheus, Grafana 설치 시 별도 예외 처리가 줄어듦

운영 원칙:

- `nfs-client`는 필요한 앱에서 명시적으로 사용
- `local`은 기본값으로 두지 않음

### 명시적 지정

앱 설치 문서에서는 가능하면 아래처럼 `storageClassName`을 명시합니다.

예:

```yaml
storageClassName: longhorn
```

또는:

```yaml
storageClassName: nfs-client
```

이유:

- 기본 StorageClass 변경 시 의도하지 않은 스토리지 이동을 막을 수 있음
- 앱별 역할이 더 명확해짐

## NFS 기준

이 저장소의 현재 예시 기준은 다음과 같습니다.

- NFS 서버: `192.168.0.2`
- NFS export: `/volume2/nfs`
- Kubernetes용 하위 폴더: `/volume2/nfs/k8s`
- StorageClass 이름: `nfs-client`

운영 메모:

- Synology 공유폴더 `nfs` 아래에 `k8s` 폴더를 미리 만들어 둡니다.
- `nfs-subdir-external-provisioner`는 `/volume2/nfs/k8s` 아래에
  PVC별 하위 폴더를 자동 생성합니다.
- 각 Kubernetes 노드에는 `nfs-common`을 설치해 두는 것을 권장합니다.

관련 문서:

- [`./installation.md`](./installation.md)
- [`./nfs-storageclass.md`](./nfs-storageclass.md)
- [`../prometheus/installation.md`](../prometheus/installation.md)

## Longhorn 기준

Longhorn은 아직 이 저장소에서 상세 설치 문서가 분리되지 않았더라도,
운영 핵심 스택의 기본 저장소 후보로 봅니다.

권장 방향:

- `Rancher`, `Prometheus`, `Grafana`는 장기적으로 `Longhorn` 사용
- `nfs-client`는 일반 앱 데이터용으로 유지

운영 메모:

- Longhorn 설치 전에는 노드 디스크 여유 공간과 복제 정책을 먼저 설계합니다.
- 홈랩에서는 replica 수를 과도하게 높이지 않도록 주의합니다.
- 전 노드에 Longhorn 전제 조건은 준비하되, 실제 저장소 사용은 `worker` 우선으로
  설계하는 것을 권장합니다.
- 현재 표준 디스크 크기는 `cp1`~`cp3` `60GB`, `w1`~`w2` `400GB`입니다.
- `worker 300GB`로도 시작은 가능하지만, 여러 앱을 계속 설치할 계획이면
  `400GB`를 권장합니다.

관련 문서:

- [`./longhorn-installation.md`](./longhorn-installation.md)

## Local 기준

Local 스토리지는 테스트용으로만 사용합니다.

예시:

- 성능 실험
- 일회성 랩
- 삭제해도 되는 임시 앱

운영 원칙:

- 운영 핵심 앱에는 사용하지 않음
- 기본 StorageClass로 지정하지 않음
- `local-path-provisioner`는 기본 설치 대상으로 두지 않고,
  필요할 때만 별도로 설치합니다.
- 별도 공통 설치 문서를 만들기보다 필요할 때 앱 문서나 테스트 문서에서 명시적으로 사용합니다.

## 설치 순서 권장안

스토리지 준비 순서는 아래를 권장합니다.

1. Kubernetes 기본 설치
2. `nfs-client` StorageClass 준비
3. Longhorn 준비
4. 기본 StorageClass 정책 결정
5. Prometheus / Grafana / Rancher 같은 운영 핵심 스택 설치
6. 일반 앱 설치

## 관련 문서

- [K8s Installation](./installation.md)
- [K8s Troubleshooting](./troubleshooting.md)
- [Prometheus Installation](../prometheus/installation.md)
- [Grafana Installation](../grafana/installation.md)
- [Argo CD Installation](../argocd/installation.md)
