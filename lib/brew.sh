#!/usr/bin/env bash
# oh-my-setup — Homebrew 패키지 관리 (인터랙티브 설치)

# ── Brewfile 파싱 ────────────────────────────────
# Brewfile을 읽어 type|name 형태의 배열로 반환
# 예: "brew|git", "cask|ghostty", "tap|homebrew/cask-fonts"
_brew_parse_brewfile() {
  local brewfile="$1"
  [[ -f "$brewfile" ]] || return 1

  while IFS= read -r line; do
    # 빈 줄, 주석 건너뛰기
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    local type="" name=""
    if [[ "$line" =~ ^brew[[:space:]]+\"([^\"]+)\" ]]; then
      type="brew"
      name="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^cask[[:space:]]+\"([^\"]+)\" ]]; then
      type="cask"
      name="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^tap[[:space:]]+\"([^\"]+)\" ]]; then
      type="tap"
      name="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^mas[[:space:]]+\"([^\"]+)\" ]]; then
      type="mas"
      name="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^vscode[[:space:]]+\"([^\"]+)\" ]]; then
      type="vscode"
      name="${BASH_REMATCH[1]}"
    else
      continue
    fi

    echo "${type}|${name}"
  done < "$brewfile"
}

# ── 설치 여부 확인 ───────────────────────────────
_brew_is_installed() {
  local type="$1" name="$2"

  case "$type" in
    tap)
      brew tap 2>/dev/null | grep -q "^${name}$" && return 0
      ;;
    brew)
      # @버전 포함된 이름 처리 (예: python@3.14)
      brew list --formula 2>/dev/null | grep -q "^${name}$" && return 0
      # 바이너리명으로도 확인 (예: python@3.14 → python3)
      local bin_name="${name%%@*}"
      command -v "$bin_name" >/dev/null 2>&1 && return 0
      ;;
    cask)
      brew list --cask 2>/dev/null | grep -q "^${name}$" && return 0
      ;;
    mas)
      # mas는 이름으로 확인 어려움, 기본적으로 미설치로 처리
      return 1
      ;;
    vscode)
      if command -v code >/dev/null 2>&1; then
        code --list-extensions 2>/dev/null | grep -qi "^${name}$" && return 0
      fi
      ;;
  esac
  return 1
}

# ── 단일 항목 설치 ───────────────────────────────
_brew_install_item() {
  local type="$1" name="$2"

  case "$type" in
    tap)    brew tap "$name" 2>/dev/null ;;
    brew)   brew install "$name" 2>/dev/null ;;
    cask)   brew install --cask "$name" 2>/dev/null ;;
    mas)    mas install "$name" 2>/dev/null ;;
    vscode) code --install-extension "$name" 2>/dev/null ;;
  esac
}

# ── 메인: 인터랙티브 Brew 설치 ──────────────────
# Usage: oms_brew_install [options]
oms_brew_install() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)   OMS_DRY_RUN="true" ;;
      -y|--yes)    OMS_YES="true" ;;
      -v|--verbose) OMS_LOG_LEVEL="debug" ;;
      *)           oms_error "알 수 없는 옵션: $1"; return 1 ;;
    esac
    shift
  done

  local brewfile="${OMS_DOTFILES}/Brewfile"
  if [[ ! -f "$brewfile" ]]; then
    oms_error "Brewfile을 찾을 수 없습니다: $brewfile"
    oms_info "'oms snapshot --brew-only'로 먼저 Brewfile을 생성하세요."
    return 1
  fi

  echo ""
  echo -e "${BOLD}📦 Brewfile 패키지 설치${NC}"
  echo ""

  # Brewfile 파싱
  local all_items=()
  while IFS= read -r item; do
    all_items+=("$item")
  done < <(_brew_parse_brewfile "$brewfile")

  if [[ ${#all_items[@]} -eq 0 ]]; then
    oms_info "Brewfile에 패키지가 없습니다."
    return 0
  fi

  # 카테고리별 분류 + 설치 여부 확인
  local installed_items=()
  local missing_items=()
  local missing_nums=()
  local num=0

  # tap은 먼저 처리 (의존성)
  local tap_items=()
  local brew_items=()
  local cask_items=()
  local other_items=()

  local i
  for i in "${all_items[@]}"; do
    local type="${i%%|*}"
    case "$type" in
      tap)   tap_items+=("$i") ;;
      brew)  brew_items+=("$i") ;;
      cask)  cask_items+=("$i") ;;
      *)     other_items+=("$i") ;;
    esac
  done

  # 카테고리별 출력 함수
  _print_category() {
    local label="$1"
    shift
    local items=("$@")

    [[ ${#items[@]} -eq 0 ]] && return

    echo -e "── ${BOLD}${label}${NC} ────────────────────"

    local item
    for item in "${items[@]}"; do
      local type="${item%%|*}"
      local name="${item##*|}"

      if _brew_is_installed "$type" "$name"; then
        printf "  ${GREEN}✓${NC}  %-30s ${DIM}설치됨${NC}\n" "$name"
        installed_items+=("$item")
      else
        num=$((num + 1))
        printf "  ${YELLOW}%2d)${NC} %-30s 미설치\n" "$num" "$name"
        missing_items+=("$item")
        missing_nums+=("$num")
      fi
    done
    echo ""
  }

  set +e  # grep 실패 방지
  if [[ ${#tap_items[@]} -gt 0 ]]; then
    _print_category "Taps" "${tap_items[@]}"
  fi
  if [[ ${#brew_items[@]} -gt 0 ]]; then
    _print_category "Formulae" "${brew_items[@]}"
  fi
  if [[ ${#cask_items[@]} -gt 0 ]]; then
    _print_category "Casks" "${cask_items[@]}"
  fi
  if [[ ${#other_items[@]} -gt 0 ]]; then
    _print_category "기타 (vscode, mas)" "${other_items[@]}"
  fi
  set -e

  # 요약
  echo -e "${DIM}총 ${#all_items[@]}개: ${GREEN}${#installed_items[@]}개 설치됨${NC}, ${YELLOW}${#missing_items[@]}개 미설치${NC}"
  echo ""

  if [[ ${#missing_items[@]} -eq 0 ]]; then
    oms_ok "모든 패키지가 이미 설치되어 있습니다."
    return 0
  fi

  if [[ "${OMS_DRY_RUN}" == "true" ]]; then
    oms_info "[DRY-RUN] ${#missing_items[@]}개 미설치 항목 설치 예정"
    return 0
  fi

  # 선택 UI
  local to_install=()

  if [[ "${OMS_YES}" == "true" ]]; then
    # --yes: 미설치 전부 설치
    to_install=("${missing_items[@]}")
  else
    echo -e "미설치 ${YELLOW}${#missing_items[@]}개${NC} 항목을 모두 설치할까요?"
    echo -ne "  ${DIM}[Y] 전체 설치 / [n] 건너뛰기 / 번호 입력 (예: 1 3 5):${NC} "
    read -r answer

    if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
      # Enter 또는 Y: 전체 설치
      to_install=("${missing_items[@]}")
    elif [[ "$answer" =~ ^[Nn]$ ]]; then
      oms_info "설치를 건너뜁니다."
      return 0
    else
      # 번호 선택
      for sel in $answer; do
        if [[ "$sel" =~ ^[0-9]+$ ]] && [[ "$sel" -ge 1 ]] && [[ "$sel" -le ${#missing_items[@]} ]]; then
          to_install+=("${missing_items[$((sel - 1))]}")
        else
          oms_warn "잘못된 번호 무시: $sel"
        fi
      done

      if [[ ${#to_install[@]} -eq 0 ]]; then
        oms_info "선택된 항목이 없습니다."
        return 0
      fi
    fi
  fi

  # 설치 실행
  echo ""
  oms_info "${#to_install[@]}개 패키지를 설치합니다..."
  echo ""

  local success=0
  local failed=0
  local failed_names=()

  for item in "${to_install[@]}"; do
    local type="${item%%|*}"
    local name="${item##*|}"

    echo -ne "  설치 중: ${name} ... "

    if _brew_install_item "$type" "$name"; then
      echo -e "${GREEN}완료${NC}"
      success=$((success + 1))
    else
      echo -e "${RED}실패${NC}"
      failed=$((failed + 1))
      failed_names+=("$name")
    fi
  done

  # 결과 요약
  echo ""
  oms_ok "${success}개 설치 완료"
  if [[ $failed -gt 0 ]]; then
    oms_warn "${failed}개 설치 실패: ${failed_names[*]}"
  fi
}

# ── CLI 라우터 ───────────────────────────────────
# Usage: oms brew <install|snapshot|diff|cleanup>
oms_brew_cmd() {
  local subcmd="${1:-install}"
  shift 2>/dev/null || true

  case "$subcmd" in
    install)  oms_brew_install "$@" ;;
    snapshot) source "${OMS_HOME}/lib/config.sh"
              source "${OMS_HOME}/lib/backup.sh"
              source "${OMS_HOME}/lib/snapshot.sh"
              oms_snapshot --brew-only "$@" ;;
    diff)     echo "TODO: brew diff 구현" ;;
    cleanup)  echo "TODO: brew cleanup 구현" ;;
    *)        oms_error "알 수 없는 brew 명령어: $subcmd"
              echo "사용법: oms brew <install|snapshot|diff|cleanup>"
              return 1 ;;
  esac
}
