#!/usr/bin/env bash
# oh-my-setup 원라인 부트스트랩 스크립트
# 사용법: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/dorrot101/oh-my-setup/master/scripts/install.sh)"
set -euo pipefail

OMS_HOME="${OMS_HOME:-$HOME/.oh-my-setup}"
OMS_REPO="${OMS_REPO:-https://github.com/username/oh-my-setup.git}"

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
skip()  { echo -e "${DIM}[SKIP]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

echo ""
echo -e "${BOLD}oh-my-setup 설치를 시작합니다.${NC}"
echo ""

# ── 1. 사전 요구사항 확인 ─────────────────────────
info "사전 요구사항 확인 중..."

# macOS 확인
if [[ "$(uname -s)" != "Darwin" ]]; then
  error "oh-my-setup은 macOS 전용입니다."
fi

# macOS 버전 확인
macos_version="$(sw_vers -productVersion)"
macos_major="$(echo "$macos_version" | cut -d. -f1)"
if [[ "$macos_major" -lt 13 ]]; then
  error "macOS Ventura (13.0) 이상이 필요합니다. 현재: ${macos_version}"
fi
ok "macOS ${macos_version}"

# Xcode CLI Tools 확인
if ! xcode-select -p >/dev/null 2>&1; then
  info "Xcode Command Line Tools 설치 중..."
  xcode-select --install
  echo "설치 완료 후 이 스크립트를 다시 실행해주세요."
  exit 0
fi
ok "Xcode Command Line Tools"

# Git 확인
if ! command -v git >/dev/null 2>&1; then
  error "Git을 찾을 수 없습니다. Xcode CLI Tools 설치를 확인해주세요."
fi
ok "Git $(git --version | awk '{print $3}')"

# ── 2. Homebrew 설치 ─────────────────────────────
if ! command -v brew >/dev/null 2>&1; then
  info "Homebrew를 설치합니다..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Apple Silicon PATH 설정
  if [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  if command -v brew >/dev/null 2>&1; then
    ok "Homebrew $(brew --version | head -1 | awk '{print $2}')"
  else
    error "Homebrew 설치에 실패했습니다."
  fi
else
  skip "Homebrew 이미 설치됨 ($(brew --version | head -1 | awk '{print $2}'))"
fi

# ── 3. GitHub CLI 설치 & 인증 ────────────────────
if ! command -v gh >/dev/null 2>&1; then
  info "GitHub CLI를 설치합니다..."
  brew install gh
  ok "GitHub CLI $(gh --version | head -1 | awk '{print $3}')"
else
  skip "GitHub CLI 이미 설치됨 ($(gh --version | head -1 | awk '{print $3}'))"
fi

if ! gh auth status >/dev/null 2>&1; then
  info "GitHub 인증이 필요합니다. 브라우저가 열립니다."
  echo ""
  gh auth login -p https -w
  echo ""
  if gh auth status >/dev/null 2>&1; then
    ok "GitHub 인증 완료"
  else
    error "GitHub 인증에 실패했습니다. 'gh auth login'으로 다시 시도하세요."
  fi
else
  skip "GitHub 이미 인증됨 ($(gh auth status 2>&1 | grep 'Logged in' | awk '{print $NF}'))"
fi

# GitHub username 가져오기
GH_USER="$(gh api user --jq '.login' 2>/dev/null || true)"
if [[ -z "$GH_USER" ]]; then
  echo -ne "${YELLOW}? ${NC}GitHub username을 입력하세요: "
  read -r GH_USER
  [[ -z "$GH_USER" ]] && error "GitHub username이 필요합니다."
fi
ok "GitHub 사용자: ${GH_USER}"

# ── 4. 프레임워크 설치 ────────────────────────────
if [[ -d "$OMS_HOME/.git" ]]; then
  skip "oh-my-setup 프레임워크 이미 설치됨: ${OMS_HOME}"
  # 최신 버전으로 업데이트
  info "프레임워크를 최신 버전으로 업데이트합니다..."
  git -C "$OMS_HOME" pull --quiet 2>/dev/null || warn "업데이트 실패. 나중에 'oms self-update'를 실행하세요."
else
  # OMS_REPO에 username 플레이스홀더가 있으면 실제 사용자로 치환
  OMS_REPO="${OMS_REPO//username/$GH_USER}"

  info "oh-my-setup 프레임워크를 다운로드합니다..."
  git clone --depth=1 "$OMS_REPO" "$OMS_HOME" 2>/dev/null || \
    error "Git clone 실패. 저장소 URL을 확인해주세요: ${OMS_REPO}"
  ok "프레임워크 설치 완료: ${OMS_HOME}"
fi

# ── 5. 실행 파일 연결 ─────────────────────────────
chmod +x "${OMS_HOME}/bin/oms"

if command -v oms >/dev/null 2>&1; then
  skip "oms 명령어 이미 등록됨"
else
  # Apple Silicon: /opt/homebrew/bin, Intel: /usr/local/bin
  OMS_LINKED=false
  for bin_dir in /opt/homebrew/bin /usr/local/bin; do
    if [[ -d "$bin_dir" ]]; then
      ln -sf "${OMS_HOME}/bin/oms" "${bin_dir}/oms" 2>/dev/null && OMS_LINKED=true && break
    fi
  done

  if [[ "$OMS_LINKED" != "true" ]]; then
    # 심링크 실패 시 .zshrc에 PATH 추가
    if ! grep -q 'oh-my-setup/bin' "$HOME/.zshrc" 2>/dev/null; then
      echo 'export PATH="$HOME/.oh-my-setup/bin:$PATH"' >> "$HOME/.zshrc"
    fi
  fi
  ok "oms 명령어 등록"
fi

# ── 6. 셸 통합 ───────────────────────────────────
SHELL_RC="$HOME/.zshrc"
OMS_HOOK='# oh-my-setup: 업데이트 확인
[ -f ~/.oh-my-setup/lib/update.sh ] && source ~/.oh-my-setup/lib/update.sh && oms_check_update'

if [[ -f "$SHELL_RC" ]] && grep -q "oh-my-setup" "$SHELL_RC"; then
  skip ".zshrc에 이미 등록되어 있음"
elif [[ -f "$SHELL_RC" ]]; then
  echo "" >> "$SHELL_RC"
  echo "$OMS_HOOK" >> "$SHELL_RC"
  ok ".zshrc에 업데이트 훅 추가"
else
  echo "$OMS_HOOK" > "$SHELL_RC"
  ok ".zshrc 생성 및 훅 추가"
fi

# ── 7. dotfiles 저장소 clone ─────────────────────
OMS_DOTFILES="${OMS_DOTFILES:-$HOME/dotfiles}"
OMS_DOTFILES_REPO="${OMS_DOTFILES_REPO:-}"

if [[ -d "$OMS_DOTFILES/.git" ]]; then
  skip "dotfiles 이미 존재: ${OMS_DOTFILES}"
elif [[ -d "$OMS_DOTFILES" ]]; then
  warn "dotfiles 디렉토리가 있지만 Git 저장소가 아닙니다: ${OMS_DOTFILES}"
else
  if [[ -z "$OMS_DOTFILES_REPO" ]]; then
    default_dotfiles="https://github.com/${GH_USER}/dotfiles.git"
    echo ""
    echo -ne "${YELLOW}? ${NC}dotfiles 저장소 URL ${DIM}[${default_dotfiles}]${NC}: "
    read -r OMS_DOTFILES_REPO
    OMS_DOTFILES_REPO="${OMS_DOTFILES_REPO:-$default_dotfiles}"
  fi

  if [[ -n "$OMS_DOTFILES_REPO" ]]; then
    info "dotfiles 저장소를 다운로드합니다..."
    git clone "$OMS_DOTFILES_REPO" "$OMS_DOTFILES" 2>/dev/null || \
      warn "dotfiles clone 실패. 나중에 수동으로 clone하세요."
    if [[ -d "$OMS_DOTFILES" ]]; then
      ok "dotfiles 설치 완료: ${OMS_DOTFILES}"
    fi
  else
    info "dotfiles 건너뜀. 나중에 'git clone <url> ~/dotfiles'로 설치하세요."
  fi
fi

# ── 8. oh-my-zsh 설치 ────────────────────────────
# zsh 모듈의 .zshrc가 oh-my-zsh에 의존하므로 심링크 전에 먼저 설치
if [[ -d "$HOME/.oh-my-zsh" ]]; then
  skip "oh-my-zsh 이미 설치됨"
else
  info "oh-my-zsh 설치 중..."
  # --unattended: 프롬프트 없이 설치
  # --keep-zshrc: 기존 ~/.zshrc 덮어쓰지 않음 (심링크 보호)
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc >/dev/null 2>&1 \
    || warn "oh-my-zsh 설치 실패. 수동으로 설치하세요."
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    ok "oh-my-zsh 설치 완료"
  fi
fi

# ── 9. 완료 ──────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}oh-my-setup 설치가 완료되었습니다!${NC}"
echo ""
echo "  설치된 항목:"
echo "    ✓ Homebrew"
echo "    ✓ GitHub CLI (gh)"
echo "    ✓ oh-my-setup 프레임워크: ${OMS_HOME}"
[[ -d "$HOME/.oh-my-zsh" ]] && echo "    ✓ oh-my-zsh"
[[ -d "$OMS_DOTFILES" ]] && echo "    ✓ dotfiles: ${OMS_DOTFILES}"
echo ""
echo "  다음 단계:"
[[ ! -d "$OMS_DOTFILES" ]] && echo "    1. git clone <dotfiles-url> ~/dotfiles"
echo "    • oms apply      — 패키지 설치 & 설정 적용 (선택 가능)"
echo "    • oms status     — 상태 확인"
echo "    • oms sync       — 동기화"
echo "    • oms --help     — 도움말"
echo ""
