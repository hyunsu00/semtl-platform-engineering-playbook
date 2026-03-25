# tmux Installation And Usage

## 개요

이 문서는 `tmux` 설치 방법과, 원격 서버 운영에 바로 사용할 수 있는 기본 사용법을
정리합니다.

`tmux`는 터미널 멀티플렉서입니다.
하나의 터미널 화면 안에서 여러 세션, 윈도우, 패인을 관리할 수 있고, SSH가 끊겨도
세션을 유지한 뒤 다시 붙을 수 있습니다.

이 저장소 기준으로는 다음과 같은 상황에서 사용합니다.

- SSH 접속 중 작업 세션 유지
- 장시간 실행 작업(`backup`, `restore`, `tail`, `docker logs`) 유지
- 한 서버에서 여러 셸 화면 분할 운영

## 핵심 개념

- `session`: 작업 전체 묶음
- `window`: 세션 안의 탭
- `pane`: 한 윈도우 안의 분할 터미널

운영 메모:

- SSH 연결이 끊겨도 `tmux` 세션은 서버에 남아 있습니다.
- 다시 접속한 뒤 같은 세션에 붙어서 이어서 작업할 수 있습니다.
- 기본 prefix 키는 `Ctrl+b`입니다.
- `Ctrl+b`는 `tmux` 명령 시작 키(prefix key)입니다.
  먼저 `Ctrl+b`를 누르고, 그다음에 `d`, `c`, `n` 같은 실제 명령 키를 입력합니다.

## 1. 설치

### Ubuntu

```bash
sudo apt update
sudo apt install -y tmux
```

### Alpine Linux

```sh
apk update
apk add tmux
```

### 설치 확인

```bash
tmux -V
```

정상 예시:

- `tmux 3.x`

## 2. 가장 많이 쓰는 명령

새 세션 시작:

```bash
tmux
```

이 명령은 새 세션을 만들고 바로 접속합니다.

이름을 지정해서 시작:

```bash
tmux new -s work
```

운영 팁:

- 세션 이름을 붙이면 재접속 시 구분이 쉬워집니다.
- 운영용 서버에서는 `work`, `main`, `logs`, `restore`처럼 목적별 이름을 권장합니다.

## 3. 세션 분리와 재접속

현재 세션에서 빠져나오기:

```text
Ctrl+b, d
```

설명:

- `Ctrl+b`를 누른 뒤 손을 떼고 `d`
- 세션은 종료되지 않고 백그라운드에 유지됨
- 뜻: `d = detach`
  현재 화면에서만 빠져나오고 세션은 남겨둔다는 의미로 기억하면 쉽습니다.

현재 세션 목록 확인:

```bash
tmux ls
```

세션 다시 붙기:

```bash
tmux attach
```

특정 세션에 다시 붙기:

```bash
tmux attach -t work
```

## 4. 핵심 단축키

기본 prefix:

```text
Ctrl+b
```

뜻:

- `tmux` 명령 시작 키(prefix key)
- 먼저 `Ctrl+b`를 누르고, 그다음에 실제 명령 키를 입력합니다.

### 4-1. 세션 관련

| 기능 | 단축키 | 뜻 |
| --- | --- | --- |
| detach | `Ctrl+b, d` | `d = detach`, 현재 화면에서 빠져나오기 |

### 4-2. 창(window)

| 기능 | 단축키 | 뜻 |
| --- | --- | --- |
| 새 창 | `Ctrl+b, c` | `c = create` |
| 창 이동 | `Ctrl+b, 0~9` | 보이는 번호의 창으로 이동 |
| 창 이름 변경 | `Ctrl+b, ,` | 현재 창 이름 변경 |

### 4-3. 화면 분할(pane)

| 기능 | 단축키 | 뜻 |
| --- | --- | --- |
| 좌우 분할 | `Ctrl+b, %` | `%` 모양처럼 좌우 분할 |
| 상하 분할 | `Ctrl+b, "` | `"` 모양처럼 상하 분할 |
| pane 이동 | `Ctrl+b, 방향키` | 원하는 방향의 pane으로 이동 |
| pane 닫기 | `exit` | 현재 pane 종료 |
| pane 최대화/복귀 | `Ctrl+b, z` | `z = zoom` |

### 4-4. 스크롤과 복사

| 기능 | 단축키 | 뜻 |
| --- | --- | --- |
| 스크롤 모드 | `Ctrl+b, [` | 과거 로그 보기 시작 |
| 종료 | `q` | `q = quit` |
| 복사/선택 | `vi` 모드 사용 | `mode-keys vi` 설정 시 더 편리 |

운영 메모:

- 긴 로그를 볼 때 일반 터미널 스크롤보다 `tmux` 복사 모드가 더 안정적입니다.

## 5. 실전 사용 예시

### 예시 1: 서버 운영

- pane1: app 로그
- pane2: DB 상태
- pane3: shell 작업

운영 흐름 예시:

1. 새 창 생성: `Ctrl+b, c`
1. 세로/가로 분할: `Ctrl+b, %` 또는 `Ctrl+b, "`
1. 각 pane에서 필요한 명령 실행

### 예시 2: 배포 작업

- window1: 빌드
- window2: 로그 모니터링
- window3: `kubectl`

운영 흐름 예시:

1. 새 창 생성: `Ctrl+b, c`
1. 창 이름 변경: `Ctrl+b, ,`
1. 역할별로 창 이름을 `build`, `logs`, `k8s`처럼 설정

## 6. 가장 많이 쓰는 패턴

이 섹션은 `tmux`를 쓰는 두 가지 방식을 구분해서 설명합니다.

- 기본 소켓 방식: `default` 소켓 하나만 사용
- 커스텀 소켓 방식: `-L`로 소켓을 나눠서 사용

### 6-1. 기본 소켓 방식

가장 단순한 기본 방식입니다.
보통 SSH에서만 `tmux`를 쓴다면 이 방식이 가장 이해하기 쉽습니다.

세션 생성:

```bash
tmux new -s main
```

이미 있으면 붙고, 없으면 새로 만들기:

```bash
tmux new -A -s main
```

뜻:

- `new`: 새 세션 생성
- `-s main`: 세션 이름을 `main`으로 지정
- `-A`: 같은 이름의 세션이 이미 있으면 새로 만들지 않고 그 세션에 붙기

쉽게 기억하면:

- `A = attach if exists`

이 패턴은 운영 서버에서 가장 자주 쓰는 방식입니다.

기본 소켓 방식에서는 아래 명령들이 모두 같은 `default` 소켓을 봅니다.

```bash
tmux ls
tmux attach -t main
tmux kill-server
```

의미:

- `tmux ls`: 기본 소켓 `default`의 세션 목록 확인
- `tmux attach -t main`: 기본 소켓 `default`의 `main` 세션에 붙기
- `tmux kill-server`: 기본 소켓 `default` 서버 종료

### 6-2. 커스텀 소켓 방식

기본적으로는 `default` 소켓 방식이면 충분합니다.
다만 `SSH`와 `ttyd`처럼 서로 다른 터미널 환경을 함께 쓰면서 충돌이 있으면,
그때 `-L`로 소켓을 나눠 쓰는 편이 안전합니다.

권장 예시:

```bash
tmux -L ssh new -A -s main
tmux -L web new -A -s main
```

뜻:

- `-L ssh`: `ssh`라는 이름의 tmux 소켓 사용
- `-L web`: `web`이라는 이름의 tmux 소켓 사용
- `new`: 새 세션 생성
- `-A`: 같은 이름의 세션이 있으면 그 세션에 붙기
- `-s main`: SSH용/웹용 기본 세션 이름을 `main`으로 지정

쉽게 기억하면:

- `L = socket Label`
  tmux 서버를 이름표로 구분한다고 생각하면 쉽습니다.

운영 권장:

- 먼저는 기본 소켓 방식으로 단순하게 사용
- `ttyd`에서만 쓸 세션이라면 `tmux new -A -s webmain`
- SSH와 `ttyd`가 같은 `tmux` 서버를 공유하면서 문제가 생길 때만 `-L`로 분리

즉, `ttyd`에서 굳이 커스텀 소켓이 꼭 필요한 것은 아닙니다.
문제가 없다면 `default` 소켓 + 세션 이름 분리만으로도 충분합니다.

### 6-3. 커스텀 소켓 확인 방법

커스텀 소켓 방식에서는 소켓 이름까지 같이 써서 확인해야 합니다.

```bash
tmux -L ssh ls
tmux -L web ls
```

뜻:

- `tmux -L ssh ls`: `ssh` 소켓의 세션 목록 확인
- `tmux -L web ls`: `web` 소켓의 세션 목록 확인

주의:

- 그냥 `tmux ls`를 실행하면 기본 소켓 `default`만 확인합니다.
- `-L ssh`, `-L web`로 만든 세션은 같은 이름의 소켓으로 확인해야 합니다.

예:

```bash
tmux ls
```

결과:

```text
no server running on /tmp/tmux-1000/default
```

이 경우 `tmux`가 없는 것이 아니라, `default` 소켓에 서버가 없다는 뜻입니다.
실제로는 아래처럼 확인해야 합니다.

```bash
tmux -L ssh ls
tmux -L web ls
```

### 6-4. 커스텀 소켓 다시 붙기와 종료

다시 붙을 때도 같은 소켓 이름을 써야 합니다.

```bash
tmux -L ssh attach -t main
tmux -L web attach -t main
```

종료도 같은 방식입니다.

```bash
tmux -L ssh kill-server
tmux -L web kill-server
```

주의:

- `tmux kill-server`만 실행하면 기본 소켓 `default` 서버만 종료합니다.
- `ssh`, `web`처럼 `-L`로 나눈 tmux 서버는 같은 `-L` 옵션을 붙여서 종료해야
  합니다.

### 6-5. 로그 전용 윈도우

먼저 새 윈도우를 하나 만든 뒤:

```text
Ctrl+b, c
```

이름을 `logs`처럼 바꾸면 관리가 더 쉽습니다.

```text
Ctrl+b, ,
```

뜻:

- 현재 윈도우 이름을 바꾸는 키

그 윈도우에서 아래처럼 로그를 실행합니다.

예:

```bash
docker logs -f upsnap
```

또는:

```bash
tail -f /var/log/syslog
```

### 6-6. 장시간 실행 작업 유지

필요하면 작업 전용 윈도우를 하나 더 만든 뒤:

```text
Ctrl+b, c
```

이름을 `backup`, `restore`, `sync`처럼 작업 목적에 맞게 바꿔두는 것을 권장합니다.

```text
Ctrl+b, ,
```

그 윈도우에서 아래 작업을 실행합니다.

예:

```bash
rsync -avh /src /dst
```

또는:

```bash
restic backup /data
```

SSH가 끊겨도 `tmux` 세션에 작업이 남아 있어 다시 붙어서 진행 상황을 볼 수
있습니다.

## 7. 추천 설정 (`~/.tmux.conf`)

개인 사용자 설정 파일:

```bash
vi ~/.tmux.conf
```

예시:

```conf
set -g mouse on
set -g prefix C-a
unbind C-b
bind C-a send-prefix
bind | split-window -h
bind - split-window -v
set -g history-limit 100000
setw -g mode-keys vi
```

설정 의미:

- `mouse on`: 마우스 선택, 스크롤, 패인 선택 활성화
- `prefix C-a`: prefix를 `Ctrl+a`로 변경
- `unbind C-b`: 기존 기본 prefix 해제
- `bind C-a send-prefix`: 새 prefix 전달
- `bind | split-window -h`: `|`로 좌우 분할
- `bind - split-window -v`: `-`로 상하 분할
- `history-limit`: 스크롤백 확장
- `mode-keys vi`: 복사 모드에서 vi 스타일 키 사용

설정 다시 불러오기:

```bash
tmux source-file ~/.tmux.conf
```

## 8. 검증

세션 생성:

```bash
tmux new -s test
```

분리:

```text
Ctrl+b, d
```

목록 확인:

```bash
tmux ls
```

재접속:

```bash
tmux attach -t test
```

기대 결과:

- `test` 세션이 유지됨
- 분리 후 다시 접속 가능
- SSH 재접속 후에도 작업이 이어짐

## 9. 트러블슈팅

### `no server running` 메시지

원인:

- 활성 세션이 없음

해결:

```bash
tmux new -s work
```

### 이미 다른 클라이언트가 붙어 있는 세션에 접속하고 싶음

```bash
tmux attach -t work
```

필요 시 기존 클라이언트를 떼고 붙기:

```bash
tmux attach -d -t work
```

## 10. 엔지니어 기준 팁

- `kubectl logs`와 `tmux`는 함께 쓰면 매우 편합니다.
- long-running job(빌드, 백업, 복구, 데이터 이동)은 `tmux`에서 실행하는 것을 권장합니다.
- CI 디버깅 시 pane을 분할해 로그와 셸을 동시에 확인하면 편합니다.
- HA 환경 점검 시 노드별 창 또는 pane을 나눠서 보면 비교가 쉽습니다.

## 11. 한 줄 정리

`tmux`는 SSH가 끊겨도 작업이 살아 있는 멀티 터미널 환경입니다.

## 12. 운영 권장사항

- 서버에 SSH로 들어가서 장시간 작업할 때는 먼저 `tmux new -A -s main`으로 시작합니다.
- 로그 확인용 윈도우와 작업용 윈도우를 분리합니다.
- 세션 이름은 역할 기준으로 짧게 통일합니다.
- 복구 작업이나 데이터 이동 작업은 `tmux` 없이 직접 실행하지 않는 편이 안전합니다.
