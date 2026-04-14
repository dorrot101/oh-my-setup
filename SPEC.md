# oh-my-setup — 사양서 (Specification)

> macOS 개발 환경을 Git 기반으로 선언적 관리하는 Shell CLI 도구

---

## 1. 프로젝트 개요

### 1.1 목적

여러 macOS 기기에서 동일한 개발 환경을 보장하기 위한 CLI 도구.
Homebrew 패키지, 닷파일(.gitconfig, .zshrc, Karabiner 설정 등), 시스템 설정을
하나의 Git 저장소로 관리하고, 기기 간 동기화 및 업데이트 알림을 제공한다.

### 1.2 핵심 원칙

- **선언적(Declarative)**: 설정 파일에 원하는 상태를 정의하면, 도구가 현재 상태와 비교하여 필요한 작업만 수행
- **멱등성(Idempotent)**: 몇 번을 실행해도 동일한 결과. 이미 설치된 소프트웨어는 건너뜀
- **Git 중심**: 모든 설정 변경은 Git 커밋으로 추적. 기기 간 동기화는 git push/pull
- **모듈식(Modular)**: 패키지 그룹을 선택적으로 설치/제거 가능
- **비침습적(Non-intrusive)**: 터미널 열 때 업데이트 확인은 하되, 강제 적용하지 않음

### 1.3 기술 스택

| 항목 | 선택 |
|------|------|
| 언어 | Bash/Zsh (POSIX 호환 지향, macOS 기본 셸 활용) |
| 대상 OS | macOS 전용 (Ventura 13.0+) |
| 패키지 관리 | Homebrew, mas (Mac App Store) |
| 동기화 | Git (GitHub/GitLab 원격 저장소) |
| 설정 형식 | TOML (파싱: 경량 셸 파서 또는 `dasel` 활용) |
| 인터랙티브 UI | Bash `select`, `read`, 선택적으로 `gum` (Charm CLI) |

---

## 2. 디렉토리 구조

### 2.1 프레임워크 설치 위치

```
~/.oh-my-setup/                          # 프레임워크 코어 (git clone)
├── bin/
│   └── oms                              # 메인 CLI 엔트리포인트
├── lib/
│   ├── core.sh                          # 공통 유틸리티 (로깅, 색상, 에러 핸들링)
│   ├── config.sh                        # TOML 설정 파싱
│   ├── detect.sh                        # 소프트웨어 감지 엔진
│   ├── sync.sh                          # Git 동기화 로직
│   ├── update.sh                        # 업데이트 확인 & 알림
│   ├── link.sh                          # 심링크 관리 (dotfiles)
│   ├── brew.sh                          # Homebrew 패키지 관리
│   ├── macos.sh                         # macOS 시스템 설정
│   └── hooks.sh                         # 라이프사이클 훅 실행
├── modules/                             # 내장 모듈 (선택 설치 단위)
│   ├── git/
│   │   ├── module.toml                  # 모듈 메타데이터
│   │   ├── install.sh                   # 설치 스크립트
│   │   └── dotfiles/
│   │       └── .gitconfig.tpl           # 템플릿 (변수 치환용)
│   ├── zsh/
│   │   ├── module.toml
│   │   ├── install.sh
│   │   └── dotfiles/
│   │       ├── .zshrc.tpl
│   │       └── .zprofile.tpl
│   ├── karabiner/
│   │   ├── module.toml
│   │   ├── install.sh
│   │   └── dotfiles/
│   │       └── karabiner.json
│   ├── vscode/
│   │   ├── module.toml
│   │   ├── install.sh
│   │   └── dotfiles/
│   │       └── settings.json
│   └── ...
├── templates/
│   └── setup.toml.example              # 사용자 설정 파일 템플릿
├── hooks/
│   ├── pre-sync.sh                      # 동기화 전 실행
│   └── post-sync.sh                     # 동기화 후 실행
├── scripts/
│   ├── install.sh                       # 원라인 부트스트랩 스크립트
│   └── uninstall.sh                     # 제거 스크립트
└── .version                             # 프레임워크 버전
```

### 2.2 사용자 설정 저장소 (별도 Git 저장소)

```
~/dotfiles/                              # 사용자 개인 설정 (별도 git repo)
├── setup.toml                           # 마스터 설정 파일
├── Brewfile                             # Homebrew 번들 파일
├── machines/
│   ├── MacBook-Pro.toml                 # 기기별 오버라이드
│   └── Mac-Mini.toml
├── modules/                             # 사용자 커스텀 모듈
│   └── my-scripts/
│       ├── module.toml
│       ├── install.sh
│       └── dotfiles/
│           └── .my-aliases
├── dotfiles/                            # 직접 관리 닷파일 (모듈에 속하지 않는)
│   ├── .vimrc
│   └── .tmux.conf
├── .oms-state/                          # oh-my-setup 상태 추적
│   ├── last-sync                        # 마지막 동기화 시간 (epoch)
│   ├── installed-modules.list           # 설치된 모듈 목록
│   ├── installed-brews.list             # 설치된 brew 패키지 목록
│   └── machine-id                       # 현재 기기 식별자
└── .gitignore
```

---

## 3. 설정 파일 형식

### 3.1 setup.toml (마스터 설정)

```toml
[meta]
version = "1"
machine_name = ""  # 빈 값이면 hostname 자동 사용

[git]
remote = "git@github.com:username/dotfiles.git"
branch = "main"
auto_commit = true         # 변경사항 자동 커밋
auto_push = true           # 커밋 후 자동 푸시

[update]
check_on_shell_open = true
check_interval_days = 1    # 업데이트 확인 주기 (일)
auto_apply = false         # true면 자동 적용, false면 알림만

[modules]
# 활성화할 모듈 목록. 순서대로 설치됨.
enabled = [
  "git",
  "zsh",
  "karabiner",
  "vscode",
]

[brew]
# Brewfile 경로 (상대경로: dotfiles repo 루트 기준)
bundle_file = "Brewfile"
cleanup = false            # true면 Brewfile에 없는 패키지 제거

[brew.taps]
extra = []                 # 추가 tap 목록

[link]
# 심링크 전략
strategy = "symlink"       # "symlink" | "copy"
backup = true              # 기존 파일 백업 (.bak)
backup_dir = "~/.oh-my-setup-backup"

[macos]
# macOS 시스템 기본 설정 적용 여부
apply_defaults = true
defaults_file = "macos-defaults.sh"  # 실행할 defaults 스크립트
```

### 3.2 module.toml (모듈 정의)

```toml
[module]
name = "git"
description = "Git 설정 및 글로벌 gitconfig 관리"
version = "1.0.0"
category = "dev-tools"     # 카테고리: dev-tools, shell, editor, system, custom

[dependencies]
# 이 모듈이 필요로 하는 다른 모듈
modules = []
# 이 모듈이 필요로 하는 brew 패키지
brews = ["git", "git-delta", "gh"]
# 이 모듈이 필요로 하는 cask
casks = []

[dotfiles]
# 심링크 매핑: source(모듈 내 상대경로) → target(홈 기준 경로)
links = [
  { src = "dotfiles/.gitconfig.tpl", target = "~/.gitconfig", template = true },
]

[template_vars]
# 템플릿에서 사용할 변수 (setup.toml이나 machine.toml에서 오버라이드 가능)
git_user_name = ""
git_user_email = ""
git_default_branch = "main"

[hooks]
pre_install = ""           # 설치 전 실행할 스크립트 (상대경로)
post_install = ""          # 설치 후 실행할 스크립트
```

### 3.3 기기별 오버라이드 (machines/MacBook-Pro.toml)

```toml
[meta]
machine_name = "MacBook-Pro"

# 이 기기에서만 추가로 활성화할 모듈
[modules]
extra = ["docker", "figma"]
skip = []                  # 이 기기에서 제외할 모듈

# 모듈 변수 오버라이드
[template_vars]
git_user_name = "Dorrot"
git_user_email = "hyunwoo.kim@sazo.shop"

# 이 기기에서만 추가로 설치할 brew 패키지
[brew]
extra_formulas = ["postgresql@16"]
extra_casks = ["docker"]
```

---

## 4. 핵심 기능 상세

### 4.1 소프트웨어 감지 엔진 (`lib/detect.sh`)

소프트웨어 설치 여부를 판단하는 핵심 모듈. 멱등성 보장의 기반.

**감지 우선순위:**

1. `command -v <binary>` — PATH에 실행 파일 존재 여부
2. `brew list --formula | grep -q <name>` — Homebrew formula 설치 여부
3. `brew list --cask | grep -q <name>` — Homebrew cask 설치 여부
4. `/Applications/<Name>.app` 존재 여부 — App Store 또는 수동 설치 앱
5. `mas list | grep -q <id>` — Mac App Store 앱

**인터페이스:**

```bash
# 단일 소프트웨어 확인
oms_detect "git"          # exit code 0 = 설치됨, 1 = 미설치

# 상세 정보 반환
oms_detect_info "git"     # → "installed|/usr/local/bin/git|2.43.0|brew"
                          #   status | path | version | source

# 일괄 확인 (설치 안 된 것만 필터)
oms_detect_missing "git" "node" "python3" "docker"
# → "docker"  (미설치된 항목만 stdout)
```

**동작 규칙:**

- 이미 설치된 소프트웨어는 `[SKIP]` 로그를 남기고 건너뜀
- 버전이 다른 경우 `[OUTDATED]` 로그와 함께 업그레이드 여부를 사용자에게 질문
- 감지 결과는 `.oms-state/installed-brews.list`에 캐시 (TTL: 1시간)

### 4.2 Homebrew 패키지 관리 (`lib/brew.sh`)

**Brewfile 기반 설치:**

```bash
# Brewfile 형식 (표준 Homebrew Bundle 호환)
tap "homebrew/cask-fonts"

brew "git"
brew "node"
brew "python@3.12"
brew "ripgrep"
brew "fzf"

cask "visual-studio-code"
cask "karabiner-elements"
cask "iterm2"
cask "figma"

mas "Xcode", id: 497799835
mas "Slack", id: 803453959
```

**동작 흐름:**

```
1. Homebrew 설치 여부 확인 → 미설치 시 자동 설치
2. Brewfile 파싱
3. 각 항목에 대해 detect 엔진으로 설치 여부 확인
4. 미설치 항목만 설치 큐에 추가
5. 사용자에게 설치할 목록 보여주고 확인 요청
6. 설치 실행 (병렬 가능한 것은 병렬 처리)
7. 설치 결과를 .oms-state/installed-brews.list에 기록
8. 실패한 항목은 별도 로그에 기록하고 요약 출력
```

**Brewfile 자동 생성:**

새 소프트웨어를 `brew install`로 직접 설치한 경우, `oms brew snapshot` 명령으로
현재 설치 상태를 Brewfile에 반영할 수 있어야 한다.

```bash
oms brew snapshot        # 현재 brew list를 Brewfile에 동기화
oms brew diff            # Brewfile과 현재 설치 상태 차이 출력
oms brew cleanup         # Brewfile에 없는 패키지 제거 (확인 후)
```

### 4.3 닷파일 관리 (`lib/link.sh`)

**심링크 기반 관리:**

```
[dotfiles repo] → symlink → [실제 위치]

~/dotfiles/modules/git/dotfiles/.gitconfig → ~/.gitconfig
~/dotfiles/modules/zsh/dotfiles/.zshrc     → ~/.zshrc
~/dotfiles/modules/karabiner/dotfiles/karabiner.json
    → ~/.config/karabiner/karabiner.json
```

**템플릿 엔진:**

`.tpl` 확장자 파일은 변수 치환 후 대상 경로에 생성.

```bash
# .gitconfig.tpl 예시
[user]
    name = {{git_user_name}}
    email = {{git_user_email}}
[init]
    defaultBranch = {{git_default_branch}}
```

변수 치환 규칙:
1. `module.toml`의 `[template_vars]` 기본값
2. `setup.toml`의 전역 오버라이드
3. `machines/<name>.toml`의 기기별 오버라이드
4. 환경 변수 `OMS_VAR_<NAME>` (최종 우선)

**동작 규칙:**

- 대상 경로에 이미 파일이 있고, 심링크가 아닌 경우 → `backup_dir`로 백업 후 심링크 생성
- 이미 올바른 심링크가 걸려 있는 경우 → 건너뜀
- 심링크가 있지만 다른 대상을 가리키는 경우 → 사용자에게 덮어쓸지 확인

### 4.4 Git 동기화 (`lib/sync.sh`)

**기기 → 원격 (Push):**

```
1. 닷파일 저장소에서 변경사항 감지 (git status)
2. 변경된 파일 목록 출력
3. auto_commit=true면 자동 커밋 (메시지: "[oms] sync from <machine_name>: <timestamp>")
4. auto_push=true면 자동 푸시
5. 충돌 발생 시 사용자에게 알림 (자동 해결 시도하지 않음)
```

**원격 → 기기 (Pull):**

```
1. git fetch origin
2. 로컬과 원격 비교 (git rev-list --count HEAD..origin/main)
3. 변경사항이 있으면:
   a. 변경된 파일 목록 출력
   b. 새로 추가된 brew 패키지가 있으면 알림
   c. 사용자 확인 후 git pull
   d. 변경된 모듈 재적용 (심링크 갱신, brew 설치 등)
```

**충돌 처리:**

- 자동 병합 불가 시: 충돌 파일 목록 출력 + 수동 해결 안내
- `oms sync --force-remote`: 원격 기준으로 강제 덮어쓰기
- `oms sync --force-local`: 로컬 기준으로 강제 푸시

### 4.5 업데이트 알림 시스템 (`lib/update.sh`)

oh-my-zsh 스타일로 터미널을 열 때 업데이트를 확인하고 알림.

**메커니즘:**

`.zshrc` (또는 `.bashrc`)에 다음 한 줄을 추가:

```bash
[ -f ~/.oh-my-setup/lib/update.sh ] && source ~/.oh-my-setup/lib/update.sh && oms_check_update
```

**`oms_check_update` 동작:**

```
1. .oms-state/last-sync 파일에서 마지막 확인 시간 읽기
2. 현재 epoch와 비교하여 check_interval_days 경과 여부 확인
3. 경과하지 않았으면 → 아무것도 하지 않음 (빠른 종료)
4. 경과했으면 → 백그라운드에서 git fetch (non-blocking)
5. 원격에 새 커밋이 있으면:
   a. 변경 요약 메시지 출력
   b. 새로 추가된 brew 패키지가 있으면 별도 알림
   c. 어느 기기에서 변경했는지 표시
6. last-sync 타임스탬프 갱신
```

**알림 메시지 형식:**

```
╭─────────────────────────────────────────────────╮
│  oh-my-setup: 업데이트가 있습니다!               │
│                                                  │
│  Mac-Mini에서 2개의 변경사항이 동기화됨:          │
│    • 새 brew 패키지: postgresql@16, redis        │
│    • 변경된 설정: .gitconfig, karabiner.json     │
│                                                  │
│  적용하려면: oms sync                             │
│  자세히 보기: oms sync --dry-run                  │
╰─────────────────────────────────────────────────╯
```

**프레임워크 자체 업데이트:**

oh-my-setup 프레임워크 코드도 Git으로 관리되므로, 프레임워크 업데이트도 별도 확인:

```bash
oms self-update              # 프레임워크 업데이트
oms self-update --check      # 확인만 (적용하지 않음)
```

### 4.6 선택적 설치 (`oms init` 인터랙티브 모드)

처음 새 기기에 설정할 때 create-next-app 스타일의 인터랙티브 설정 마법사 제공.

**흐름:**

```
$ oms init

  oh-my-setup 초기 설정을 시작합니다.

? 닷파일 저장소 URL (비어있으면 새로 생성):
  > git@github.com:dorrot/dotfiles.git

? 이 기기의 이름:
  > MacBook-Pro

? 설치할 모듈을 선택하세요 (space로 토글, enter로 확인):
  ✅ git        - Git 설정 및 글로벌 gitconfig
  ✅ zsh        - Zsh 셸 설정 (.zshrc, .zprofile)
  ✅ karabiner  - Karabiner Elements 키 매핑
  ☐  vscode     - VS Code 설정 및 확장
  ☐  docker     - Docker Desktop 설정
  ☐  node       - Node.js 및 글로벌 npm 패키지

? Brewfile의 패키지를 모두 설치할까요?
  > 예, 모두 설치 / 아니오, 선택적으로 설치 / 건너뛰기

? macOS 시스템 기본 설정을 적용할까요?
  > 예 / 아니오

  설치를 시작합니다...
```

**비인터랙티브 모드 (CI/스크립팅):**

```bash
oms init --repo git@github.com:user/dotfiles.git \
         --machine MacBook-Pro \
         --modules git,zsh,karabiner \
         --brew-all \
         --yes
```

---

## 5. CLI 명령어 체계

### 5.1 명령어 전체 목록

```
oms                          # 상태 대시보드 출력 (요약)
oms init                     # 초기 설정 마법사
oms sync                     # 양방향 동기화 (pull → 적용 → push)
oms sync --pull              # 원격 → 로컬만
oms sync --push              # 로컬 → 원격만
oms sync --dry-run           # 변경 사항 미리보기
oms sync --force-remote      # 원격 기준 강제 덮어쓰기
oms sync --force-local       # 로컬 기준 강제 푸시

oms apply                    # 현재 설정 전체 적용 (brew + dotfiles + modules)
oms apply --only brew        # brew만 적용
oms apply --only dotfiles    # 닷파일 심링크만 적용
oms apply --only modules     # 모듈 설치만 적용

oms module list              # 사용 가능한 모듈 목록
oms module enable <name>     # 모듈 활성화
oms module disable <name>    # 모듈 비활성화
oms module status            # 모듈 설치 상태 확인
oms module create <name>     # 새 커스텀 모듈 스캐폴딩 생성

oms brew snapshot            # 현재 brew 상태를 Brewfile로 덤프
oms brew diff                # Brewfile과 현재 상태 비교
oms brew cleanup             # Brewfile에 없는 패키지 제거

oms link                     # 닷파일 심링크 전체 적용
oms link status              # 심링크 상태 확인
oms link check               # 끊어진 심링크 감지

oms diff                     # 닷파일 저장소의 git diff 출력
oms log                      # 동기화 히스토리 출력
oms status                   # 전체 상태 대시보드

oms doctor                   # 환경 건강 진단 (문제 자동 탐지)
oms self-update              # 프레임워크 자체 업데이트
oms uninstall                # oh-my-setup 제거

oms config get <key>         # 설정 값 조회
oms config set <key> <value> # 설정 값 변경
oms config edit              # setup.toml을 $EDITOR로 열기
```

### 5.2 글로벌 옵션

```
--verbose, -v       상세 로그 출력
--quiet, -q         최소 출력 (에러만)
--yes, -y           모든 확인 자동 승인
--dry-run           실제 실행 없이 변경사항 미리보기
--no-color          컬러 출력 비활성화
--help, -h          도움말
--version           버전 정보
```

---

## 6. 부트스트랩 (새 기기 설정)

### 6.1 원라인 설치

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/username/oh-my-setup/main/scripts/install.sh)"
```

### 6.2 install.sh 동작 흐름

```
1. 사전 요구사항 확인:
   - macOS 버전 확인 (최소 Ventura)
   - Xcode Command Line Tools 설치 여부 → 미설치 시 설치
   - Git 사용 가능 여부

2. 프레임워크 설치:
   - ~/.oh-my-setup 으로 git clone
   - bin/oms를 PATH에 추가 (/usr/local/bin/oms 심링크)

3. 셸 통합:
   - .zshrc에 업데이트 체크 훅 추가
   - PATH에 ~/.oh-my-setup/bin 추가

4. 초기 설정:
   - oms init 인터랙티브 마법사 실행
```

---

## 7. 동기화 시나리오

### 7.1 기기 A에서 새 패키지 설치 시

```
[기기 A]
$ brew install postgresql@16
$ oms brew snapshot           # Brewfile 업데이트
  → Brewfile에 'brew "postgresql@16"' 추가됨
  → 자동 커밋: "[oms] brew add: postgresql@16 from MacBook-Pro"
  → 자동 푸시

[기기 B] — 터미널 열 때
╭─────────────────────────────────────────────────╮
│  oh-my-setup: 업데이트가 있습니다!               │
│  MacBook-Pro에서 1개의 새 패키지 추가:           │
│    • brew: postgresql@16                         │
│  적용하려면: oms sync                             │
╰─────────────────────────────────────────────────╯

[기기 B]
$ oms sync
  → git pull
  → Brewfile 변경 감지
  → postgresql@16 설치 여부 확인
  → "postgresql@16을 설치하시겠습니까? [Y/n]"
  → 설치 진행
```

### 7.2 기기 A에서 설정 파일 변경 시

```
[기기 A]
$ vim ~/.gitconfig            # 직접 수정 (심링크이므로 dotfiles repo에 반영)
$ oms sync                    # 변경 감지 → 커밋 → 푸시

[기기 B]
$ oms sync
  → git pull
  → .gitconfig 변경 감지
  → 심링크가 이미 올바르게 걸려 있으므로 자동 반영됨
  → "[UPDATED] .gitconfig이 원격에서 업데이트되었습니다"
```

---

## 8. 에러 처리 및 복원

### 8.1 에러 처리 원칙

- 개별 패키지 설치 실패가 전체 프로세스를 중단하지 않음
- 실패 항목은 모아서 마지막에 요약 출력
- 심각한 에러(Git 인증 실패, 디스크 공간 부족)만 즉시 중단

### 8.2 백업 & 복원

```bash
oms apply                    # 적용 전 자동 백업
# 문제 발생 시:
oms rollback                 # 마지막 적용 전 상태로 복원
oms rollback --list          # 복원 가능한 스냅샷 목록
oms rollback <snapshot-id>   # 특정 스냅샷으로 복원
```

백업 위치: `~/.oh-my-setup-backup/<timestamp>/`

### 8.3 doctor 명령 진단 항목

```bash
$ oms doctor

  oh-my-setup 환경 진단
  ─────────────────────
  ✅ macOS Ventura 13.5
  ✅ Homebrew 4.2.0
  ✅ Git 2.43.0
  ✅ 원격 저장소 연결 정상
  ⚠️  끊어진 심링크 1개: ~/.config/karabiner/karabiner.json
  ✅ 모듈 상태 정상 (4/4)
  ⚠️  Brewfile과 현재 설치 상태 불일치: 2개 패키지 누락
  ✅ 디스크 공간 충분 (52GB 여유)

  수정하려면: oms doctor --fix
```

---

## 9. 보안 고려사항

- **민감 정보 제외**: `.gitignore`에 SSH 키, 토큰, `.env` 파일 등 자동 등록
- **템플릿 변수**: 비밀번호나 토큰은 환경 변수(`OMS_VAR_*`)로 주입. Git에 커밋하지 않음
- **SSH 키 관리**: SSH 키는 동기화 대상에서 제외. 기기별 개별 생성 안내
- **Brewfile 검증**: 외부 tap 추가 시 사용자 확인 필요

---

## 10. 구현 우선순위

### Phase 1 — MVP (핵심)
1. `oms init` — 초기 설정 마법사 (인터랙티브)
2. `lib/detect.sh` — 소프트웨어 감지 엔진
3. `lib/brew.sh` — Brewfile 기반 패키지 설치 (감지 후 설치)
4. `lib/link.sh` — 닷파일 심링크 관리 (백업 포함)
5. `oms apply` — 전체 적용
6. `oms status` — 상태 확인

### Phase 2 — 동기화
7. `lib/sync.sh` — Git 동기화 (push/pull)
8. `lib/update.sh` — 터미널 열 때 업데이트 알림
9. `oms sync` — 양방향 동기화
10. `oms brew snapshot` / `oms brew diff`

### Phase 3 — 고급 기능
11. 템플릿 엔진 (변수 치환)
12. 기기별 오버라이드 (machines/*.toml)
13. 모듈 관리 CLI (`oms module *`)
14. `oms doctor` — 환경 진단
15. `oms rollback` — 백업/복원

### Phase 4 — 품질
16. 테스트 스크립트 (bats 기반 Shell 테스트)
17. 문서화 (man page, --help)
18. 원라인 부트스트랩 스크립트
19. `oms self-update`

---

## 11. 기술적 제약 및 의사결정

| 결정 사항 | 선택 | 이유 |
|-----------|------|------|
| 설정 형식 | TOML | YAML보다 간결, JSON보다 사람이 읽기 좋음. `dasel` 또는 순수 Bash 파서 사용 |
| 심링크 vs 복사 | 심링크 기본 | 원본 수정이 즉시 반영됨. 양방향 동기화에 유리 |
| Brewfile 호환 | 표준 Homebrew Bundle 형식 | `brew bundle` 명령과 호환 유지 |
| 인터랙티브 UI | `gum` 선택적 사용 | 없으면 Bash `select`/`read` 폴백. `gum`이 있으면 더 나은 UX |
| 상태 추적 | 파일 기반 (.oms-state/) | 별도 DB 불필요. Git에 포함되어 기기 간 공유 |
| 템플릿 문법 | `{{variable}}` | 셸에서 `sed` 치환으로 구현 가능. 간단하고 직관적 |

---

## 부록 A: 환경 변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `OMS_HOME` | `~/.oh-my-setup` | 프레임워크 설치 경로 |
| `OMS_DOTFILES` | `~/dotfiles` | 사용자 닷파일 저장소 경로 |
| `OMS_BACKUP_DIR` | `~/.oh-my-setup-backup` | 백업 디렉토리 |
| `OMS_LOG_LEVEL` | `info` | 로그 레벨 (debug, info, warn, error) |
| `OMS_NO_COLOR` | `false` | 컬러 출력 비활성화 |
| `OMS_AUTO_COMMIT` | `true` | 변경사항 자동 커밋 |
| `OMS_AUTO_PUSH` | `true` | 커밋 후 자동 푸시 |
| `OMS_VAR_*` | - | 템플릿 변수 오버라이드 (예: `OMS_VAR_GIT_USER_EMAIL`) |
