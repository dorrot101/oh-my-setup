# oh-my-setup (oms)

> macOS 개발 환경을 **선언적 + Git 기반**으로 여러 기기에 동기화하는 Shell CLI.
> Homebrew 패키지, dotfile, Claude Code 설정, Karabiner/Raycast 등 머신을 옮길 때마다 다시 설정하던 것들을 한 번 정의해두면 새 기기에서도 명령 한 줄로 복원된다.

---

## 0. 한눈에 보는 그림

```
┌──────────────────────────────────────────────────────────────────────┐
│  oms 는 두 개의 분리된 git 저장소로 동작한다.                          │
│                                                                       │
│   ① 프레임워크 (이 repo)            ② 사용자 dotfiles (개인 repo)     │
│   ~/.oh-my-setup/                  ~/dotfiles/                        │
│   - bin/oms (CLI)                  - setup.toml                       │
│   - lib/*.sh (코어 로직)            - Brewfile                         │
│   - modules/ (내장 모듈)            - modules/<my>/ (개인 모듈)        │
│                                    - machines/<host>.toml (선택)      │
│                                                                       │
│   ↑ self-update (oms self-update)  ↑↓ oms sync = git pull/push        │
└──────────────────────────────────────────────────────────────────────┘

  Mac A ──[ oms snapshot → oms sync ]──▶ GitHub ◀──[ oms sync → oms apply ]── Mac B
        새 설정 캡처 후 push                              pull 후 적용
```

핵심: **`~/.oh-my-setup`은 손대지 않는 코어**, **`~/dotfiles`는 사용자가 채워가는 개인 데이터**. 동기화의 SSoT(single source of truth)는 `~/dotfiles`의 git remote.

---

## 1. 사전 요구사항

- macOS Ventura (13.0+)
- Git이 설치되어 있고 GitHub 같은 원격 저장소를 사용할 수 있어야 함
- (선택) Homebrew — `apply`/`brew` 명령에서 사용

---

## 2. 첫 기기 셋업 (= 업로더)

> 새로 만든 환경을 다른 기기로 보내려는 첫 번째 머신에서 한 번만 한다.

### 2.1 프레임워크 설치

```bash
git clone https://github.com/dorrot101/oh-my-setup.git ~/.oh-my-setup
```

> `~/.oh-my-setup` 이외의 위치에 두려면 `OMS_HOME` 환경변수를 export. 예:
> `export OMS_HOME="$HOME/Documents/codespace/private/util/oh-my-setup"`

### 2.2 PATH 등록 + 환경변수

`~/.zshrc` 또는 `~/.zprofile` 끝에 추가:

```bash
export OMS_HOME="$HOME/.oh-my-setup"          # 위치를 바꿨다면 그 경로
export OMS_DOTFILES="$HOME/dotfiles"          # 개인 dotfiles repo 위치
export PATH="$OMS_HOME/bin:$PATH"
```

새 셸을 띄우거나 `source ~/.zshrc`.

### 2.3 개인 dotfiles repo 만들기

> ⚠️ `oms init` 은 현재 미구현 (Phase 2 예정). 수동으로 진행한다.

```bash
mkdir -p ~/dotfiles && cd ~/dotfiles
git init
git remote add origin git@github.com:<YOUR-GH-USER>/dotfiles.git   # private repo 권장
```

`~/dotfiles/setup.toml` 을 직접 만든다 (템플릿: `$OMS_HOME/templates/setup.toml.example`):

```toml
[meta]
version = "1"
machine_name = ""              # 빈 값이면 hostname 자동 사용
profile = "laptop"

[git]
remote = "git@github.com:<YOUR-GH-USER>/dotfiles.git"
branch = "main"
auto_commit = true
auto_push = true

[update]
check_on_shell_open = true
check_interval_days = 1
auto_apply = false

[modules]
# ⚠️ 반드시 한 줄로 — 멀티라인 배열은 oms TOML 파서가 못 읽는다
enabled = ["git", "zsh", "claude"]

[brew]
bundle_file = "Brewfile"
cleanup = false

[link]
strategy = "symlink"
backup = true
backup_dir = "~/.oh-my-setup-backup"

[macos]
apply_defaults = false
defaults_file = "macos-defaults.sh"
```

### 2.4 모듈 추가

자세한 모듈 작성법은 §5. 일단 한 줄 요약: `~/dotfiles/modules/<name>/module.toml` + `~/dotfiles/modules/<name>/dotfiles/...`

### 2.5 적용 + 첫 push

```bash
oms status              # 어떤 모듈이 어디서 인식되는지 확인
oms link --dry-run      # 어떤 symlink가 만들어질지 미리보기
oms link                # 실제 적용
git -C ~/dotfiles add -A
git -C ~/dotfiles commit -m "initial dotfiles snapshot"
oms sync                # = git pull --rebase + push (자동 백업 포함)
```

---

## 3. 새 기기에서 받기 (= 다운로더)

> 위에서 push 해둔 환경을 받아오는 다른 머신에서 한다. **개인 데이터 입력 없이 명령만**.

```bash
# 1. 프레임워크 클론
git clone https://github.com/dorrot101/oh-my-setup.git ~/.oh-my-setup

# 2. 환경변수 export (~/.zshrc 또는 ~/.zprofile)
export OMS_HOME="$HOME/.oh-my-setup"
export OMS_DOTFILES="$HOME/dotfiles"
export PATH="$OMS_HOME/bin:$PATH"

# 3. 개인 dotfiles 클론
git clone git@github.com:<YOUR-GH-USER>/dotfiles.git ~/dotfiles

# 4. 적용
oms link                # 모든 활성 모듈의 symlink 생성 (기존 파일은 자동 백업)
# 또는 brew/macOS까지 한 번에:
oms apply
```

이게 끝. `~/.zshrc`, `~/.gitconfig`, `~/.claude/CLAUDE.md` 등이 전부 `~/dotfiles` repo의 심볼릭 링크가 된다.

⚠️ **충돌 시 동작** — 대상 경로에 기존 파일이 있으면 `~/.oh-my-setup-backup/<timestamp>/<원본경로>` 로 옮긴 뒤 symlink로 교체한다. 절대 덮어쓰기/삭제하지 않으니 안전하지만, 옮겨진 백업 위치를 한 번 확인할 것.

---

## 4. 일상 워크플로우

### 4.1 한 기기에서 dotfile/스킬을 수정했을 때 (= 다른 기기로 보내기)

```bash
# 수정은 평소처럼 ~/.zshrc, ~/.claude/CLAUDE.md 등에 직접 한다.
# (그 파일들은 dotfiles repo로 가는 symlink이므로 repo가 자동으로 변경됨)

oms diff                # 무엇이 바뀌었는지 확인 (= git diff in dotfiles)
oms sync                # pull → 충돌 처리 → 자동 commit → push
```

### 4.2 다른 기기에서 받아오기 (= 풀어오기)

```bash
oms sync --pull         # push는 안 하고 받아만 옴
# 또는 양방향
oms sync
```

### 4.3 새 패키지/모듈을 추가했을 때

```bash
# Brewfile 변경 시
oms brew snapshot       # 현재 brew 상태를 ~/dotfiles/Brewfile에 캡처
oms apply               # 다른 기기에서 받아와 적용

# 모듈 추가/제거 시
# setup.toml의 [modules] enabled 배열 편집 → oms link
```

### 4.4 상태 확인

```bash
oms status              # 활성 모듈, git ahead/behind, 마지막 sync 시간
oms log                 # 최근 dotfiles 커밋 히스토리 20개
oms diff                # 아직 commit 안 한 변경
```

---

## 5. 모듈 작성하기

모듈 = 한 묶음의 dotfile/패키지/설정. 예: `git`, `zsh`, `karabiner`, `claude`.

### 5.1 디렉터리 구조

```
~/dotfiles/modules/<모듈명>/
├── module.toml          # 메타 + 어떤 파일을 어디로 symlink 할지
├── dotfiles/            # symlink 대상 파일들의 source
│   └── <원본 파일들>
└── install.sh           # (선택) post_install 훅
```

### 5.2 module.toml 최소 예시

```toml
[module]
name = "claude"
description = "Claude Code 사용자 자산 동기화"
version = "1.0.0"
category = "dev-tools"

[dependencies]
modules = []
brews = []
casks = []

[dotfiles]
# 한 줄에 하나의 link. template=true 로 두면 {{var}} 치환 가능
links = [
  { src = "dotfiles/CLAUDE.md", target = "~/.claude/CLAUDE.md", template = false },
  { src = "dotfiles/skills",    target = "~/.claude/skills",    template = false },
]

[template_vars]
# 비워두거나, template = true 인 link가 있을 때만 채움

[hooks]
pre_install = ""
post_install = ""        # "install.sh" 형태로 같은 모듈 내 스크립트 실행
```

### 5.3 모듈 활성화

`~/dotfiles/setup.toml` 의 `[modules] enabled = [...]` 배열에 모듈명을 추가 (한 줄 배열로!).

### 5.4 디렉터리도 통째로 symlink 가능

`src = "dotfiles/skills"` 처럼 디렉터리를 가리키면 디렉터리 자체가 symlink 된다. 안에 있는 파일을 따로 일일이 등록할 필요 없음.

### 5.5 모듈 검색 우선순위

`oms link` 가 모듈을 찾는 순서:
1. `$OMS_DOTFILES/modules/<name>/` (개인 모듈 — 우선)
2. `$OMS_HOME/modules/<name>/` (프레임워크 내장 — 폴백)

같은 이름이면 개인 dotfiles 의 것이 이긴다 → 프레임워크 기본값을 자기 입맛에 맞게 덮어쓸 수 있다.

---

## 6. 명령 레퍼런스

| 명령 | 동작 | 상태 |
|---|---|---|
| `oms sync [--pull / --push]` | git pull → 충돌 해결 → commit → push (자동 백업) | ✅ |
| `oms link [--dry-run]` | 활성 모듈의 symlink 적용 | ✅ |
| `oms apply` | brew install + link + macOS defaults 일괄 적용 | ✅ |
| `oms snapshot` | 현재 시스템 상태를 dotfiles repo에 캡처 | ✅ |
| `oms backup [list/restore/cleanup]` | 백업 관리 | ✅ |
| `oms brew [snapshot/diff/cleanup]` | Brew 패키지 관리 | ✅ |
| `oms status` | 활성 모듈 + git 상태 대시보드 | ✅ |
| `oms diff` | dotfiles repo 의 미커밋 변경 = `git diff` | ✅ |
| `oms log` | dotfiles repo 최근 커밋 20개 | ✅ |
| `oms self-update` | 프레임워크 자체 업데이트 | ✅ |
| `oms uninstall` | 프레임워크 제거 | ✅ |
| `oms init` | 초기 설정 마법사 | ⚠️ 미구현 — 위 §2 따라 수동 진행 |
| `oms doctor` | 환경 건강 진단 | ⚠️ 미구현 |
| `oms module <sub>` | 모듈 enable/disable/create | ⚠️ TODO 스텁 |
| `oms config <sub>` | 설정 get/set/edit | ⚠️ TODO 스텁 |
| `oms rollback` | 이전 상태로 복원 | ⚠️ TODO 스텁 |

공통 옵션: `--dry-run`, `-y/--yes` (확인 자동 승인), `-v/--verbose`, `--no-color`.

---

## 7. 자주 쓰는 워크플로우 치트시트

```bash
# 새 기기 부트스트랩 (5줄 요약)
git clone https://github.com/dorrot101/oh-my-setup.git ~/.oh-my-setup
echo 'export OMS_HOME="$HOME/.oh-my-setup"; export OMS_DOTFILES="$HOME/dotfiles"; export PATH="$OMS_HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
git clone git@github.com:<YOU>/dotfiles.git ~/dotfiles
oms apply

# 매일 작업 끝나고 push
oms sync

# 다른 기기에서 일어나서 받기
oms sync --pull && oms link

# 변경 미리보기
oms diff
oms link --dry-run
```

---

## 8. 트러블슈팅 / 알려진 함정

### 8.1 `enabled` 배열이 인식 안 됨

`setup.toml` 의 `modules.enabled` 를 멀티라인으로 적으면 oms TOML 파서가 못 읽고 폴백으로 모든 모듈 디렉터리를 스캔한다. **반드시 한 줄**.

```toml
# ❌ 안 됨
enabled = [
  "git",
  "zsh",
]

# ✅ 됨
enabled = ["git", "zsh"]
```

`dasel` 이 설치돼 있으면 멀티라인도 OK. `brew install dasel` 하면 자동으로 그쪽을 쓴다.

### 8.2 `oms link` 가 모든 모듈을 건드린다 (per-module 필터 없음)

현재 CLI는 모듈 단위 필터를 안 받는다. 한 모듈만 조심스럽게 적용하려면:

```bash
SRC=~/dotfiles/modules/<모듈>/dotfiles
DEST=<대상 디렉터리>
for item in <파일1> <파일2>; do
  [[ -e "$DEST/$item" ]] && mv "$DEST/$item" "$DEST/$item.bak"
  ln -sfn "$SRC/$item" "$DEST/$item"
done
```

또는 `setup.toml` 의 `enabled` 를 그 모듈만 남기고 임시로 줄였다가 원복한다.

### 8.3 `~/.claude/` 같은 자기 자신의 설정도 자동화하고 싶다

가능. 별도 모듈 (예: `claude`) 을 만들고 `module.toml` 에 `~/.claude/CLAUDE.md`, `~/.claude/skills` 등을 link 등록하면 끝. **단, sync 대상은 portable 자산만** — `~/.claude/projects`, `sessions/`, `history.jsonl` 등 머신-로컬 데이터는 절대 모듈에 넣지 말 것.

### 8.4 username이 기기마다 다르다

dotfile 안에 `/Users/foo/...` 같은 절대경로가 박혀있으면 다른 username 머신에서 깨진다. 두 가지 옵션:
- 가능하면 `~/...` 또는 `$HOME/...` 으로 바꾼다
- 그래도 절대경로가 필요하면 `template = true` + `template_vars.home_dir` 변수로 치환

### 8.5 `oms init` / `oms doctor` 가 안 됨

현재 미구현 / `lib/<해당명>.sh` 파일이 없는 상태다. 셋업은 §2 매뉴얼 절차를 따른다. 향후 구현 예정.

### 8.6 sync 충돌

`oms sync` 는 pull → push 전에 자동 백업을 하므로 안전하지만, rebase/merge 충돌이 나면 멈춘다. `cd ~/dotfiles` 로 들어가 일반 git 워크플로우로 해결한 뒤 `oms sync` 다시.

### 8.7 백업 위치

기본값: `~/.oh-my-setup-backup/<YYYYMMDD-HHMMSS>/<상대경로>`. `oms backup list` 로 목록 확인, `oms backup restore <stamp>` 로 복원.

---

## 9. 현재 상태 (2026-05 기준)

- ✅ 핵심 sync/apply/link 기능 동작 확인됨
- ⚠️ 일부 명령 미구현 (init, doctor, module, config, rollback)
- ⚠️ TOML 파서가 단순 — 멀티라인 배열/중첩 구조는 `dasel` 의존
- 사용 사례: 본인이 5종(git/zsh/karabiner/raycast/claude) 모듈로 사용 중

자세한 설계 의도는 [SPEC.md](SPEC.md) 참고.

---

## 10. 라이선스

(별도 명시 없음 — 개인 프로젝트)
