#!/usr/bin/env bash
# oh-my-setup — 상태 대시보드

# ── Git 상태 요약 (branch / ahead / behind / dirty) ──
_status_git_summary() {
  local dir="$1"
  [[ -d "$dir/.git" ]] || { echo "— (git repo 아님)"; return; }

  local branch ahead_behind dirty
  branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")"

  # fetch 없이 로컬 tracking 기준으로 ahead/behind
  local counts
  counts="$(git -C "$dir" rev-list --left-right --count HEAD...@{u} 2>/dev/null || echo "0 0")"
  local ahead="${counts%%[[:space:]]*}"
  local behind="${counts##*[[:space:]]}"

  if [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then
    dirty="${YELLOW}● 변경 있음${NC}"
  else
    dirty="${GREEN}✓ clean${NC}"
  fi

  local sync=""
  if [[ "$ahead" -gt 0 && "$behind" -gt 0 ]]; then
    sync=" ${YELLOW}↕ ${ahead}↑/${behind}↓${NC}"
  elif [[ "$ahead" -gt 0 ]]; then
    sync=" ${YELLOW}↑${ahead}${NC}"
  elif [[ "$behind" -gt 0 ]]; then
    sync=" ${YELLOW}↓${behind}${NC}"
  fi

  echo -e "${branch}${sync}  ${dirty}"
}

# ── 활성 모듈 목록 ───────────────────────────────
_status_modules() {
  # link.sh의 함수 재사용
  if ! declare -f _link_get_enabled_modules >/dev/null 2>&1; then
    source "${OMS_HOME}/lib/link.sh"
  fi
  _link_get_enabled_modules 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//'
}

# ── 심링크 건강도 (ok / 깨짐 / 없음) ────────────────
_status_links() {
  if ! declare -f _link_find_module_dir >/dev/null 2>&1; then
    source "${OMS_HOME}/lib/link.sh"
  fi

  local ok=0 broken=0 missing=0
  local mods
  mods="$(_link_get_enabled_modules 2>/dev/null || true)"
  [[ -z "$mods" ]] && { echo "0 0 0"; return; }

  local mod mod_dir mod_toml
  while IFS= read -r mod; do
    [[ -z "$mod" ]] && continue
    mod_dir="$(_link_find_module_dir "$mod" 2>/dev/null)" || continue
    mod_toml="${mod_dir}/module.toml"
    [[ -f "$mod_toml" ]] || continue

    while IFS= read -r line; do
      local src="" target=""
      if [[ "$line" =~ src[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
        src="${BASH_REMATCH[1]}"
      fi
      if [[ "$line" =~ target[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
        target="${BASH_REMATCH[1]}"
      fi
      [[ -z "$src" || -z "$target" ]] && continue

      local abs_src="${mod_dir}/${src}"
      local abs_target="${target/#\~/$HOME}"

      if [[ ! -e "$abs_target" ]]; then
        missing=$((missing + 1))
      elif [[ -L "$abs_target" ]]; then
        local actual
        actual="$(readlink "$abs_target")"
        if [[ "$actual" == "$abs_src" ]]; then
          ok=$((ok + 1))
        else
          broken=$((broken + 1))
        fi
      else
        # 실제 파일 — 심링크 아님 (apply 필요)
        missing=$((missing + 1))
      fi
    done < "$mod_toml"
  done <<< "$mods"

  echo "$ok $broken $missing"
}

# ── Brew 패키지 카운트 (설치됨 / Brewfile 총) ───────
_status_brew() {
  local brewfile="${OMS_DOTFILES}/Brewfile"
  [[ ! -f "$brewfile" ]] && { echo "— (Brewfile 없음)"; return; }

  local total installed=0
  total="$(grep -cE '^(brew|cask|tap|mas|vscode) ' "$brewfile" 2>/dev/null || echo 0)"

  if command -v brew >/dev/null 2>&1; then
    local installed_brews installed_casks
    installed_brews="$(brew list --formula 2>/dev/null | wc -l | tr -d ' ')"
    installed_casks="$(brew list --cask 2>/dev/null | wc -l | tr -d ' ')"
    installed=$((installed_brews + installed_casks))
  fi

  echo "${installed} 설치됨 / Brewfile ${total}개"
}

# ── 백업 디렉토리 용량 ────────────────────────────
_status_backup() {
  local backup_dir="${HOME}/.oh-my-setup-backup"
  [[ ! -d "$backup_dir" ]] && { echo "— (없음)"; return; }

  local count size
  count="$(find "$backup_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
  size="$(du -sh "$backup_dir" 2>/dev/null | awk '{print $1}')"
  echo "${count}개 스냅샷 / ${size}"
}

# ── 메인: 대시보드 ──────────────────────────────
oms_status() {
  # 설정 읽기
  if ! declare -f oms_setup_toml >/dev/null 2>&1; then
    source "${OMS_HOME}/lib/config.sh"
  fi

  local setup_toml machine_toml
  setup_toml="$(oms_setup_toml 2>/dev/null || echo "")"
  machine_toml="$(oms_machine_toml 2>/dev/null || echo "")"

  local profile="" machine_name="" dotfiles_branch=""
  if [[ -f "$setup_toml" ]]; then
    profile="$(oms_config_get "$setup_toml" "meta.profile" 2>/dev/null || true)"
    machine_name="$(oms_config_get "$setup_toml" "meta.machine_name" 2>/dev/null || true)"
  fi
  [[ -z "$machine_name" ]] && machine_name="$(hostname -s 2>/dev/null || hostname)"

  # 모듈 / 링크 상태
  local modules link_stats
  modules="$(_status_modules)"
  link_stats="$(_status_links)"
  local link_ok link_broken link_missing
  read -r link_ok link_broken link_missing <<< "$link_stats"

  # 헤더
  echo ""
  echo -e "${BOLD}┌─ oh-my-setup 상태${NC}"
  echo -e "${BOLD}│${NC}"

  # 시스템
  echo -e "${BOLD}├─ 시스템${NC}"
  echo -e "${BOLD}│${NC}   호스트        ${machine_name}"
  echo -e "${BOLD}│${NC}   macOS         $(sw_vers -productVersion 2>/dev/null || echo "?")"
  echo -e "${BOLD}│${NC}   셸           $(basename "${SHELL:-zsh}")"
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    echo -e "${BOLD}│${NC}   oh-my-zsh     ${GREEN}✓${NC} 설치됨"
  else
    echo -e "${BOLD}│${NC}   oh-my-zsh     ${YELLOW}✗${NC} 미설치"
  fi
  echo -e "${BOLD}│${NC}"

  # 프레임워크
  echo -e "${BOLD}├─ 프레임워크${NC}"
  echo -e "${BOLD}│${NC}   버전          v${OMS_VERSION}"
  echo -e "${BOLD}│${NC}   경로          ${OMS_HOME}"
  echo -e "${BOLD}│${NC}   git           $(_status_git_summary "$OMS_HOME")"
  echo -e "${BOLD}│${NC}"

  # dotfiles
  echo -e "${BOLD}├─ dotfiles${NC}"
  if [[ -d "$OMS_DOTFILES" ]]; then
    echo -e "${BOLD}│${NC}   경로          ${OMS_DOTFILES}"
    echo -e "${BOLD}│${NC}   git           $(_status_git_summary "$OMS_DOTFILES")"
    [[ -n "$profile" ]] && echo -e "${BOLD}│${NC}   프로파일      ${CYAN}${profile}${NC}" \
                        || echo -e "${BOLD}│${NC}   프로파일      ${DIM}(미설정)${NC}"
    if [[ -n "$machine_toml" && -f "$machine_toml" ]]; then
      echo -e "${BOLD}│${NC}   머신 설정     $(basename "$machine_toml")"
    fi
  else
    echo -e "${BOLD}│${NC}   ${YELLOW}dotfiles 미설치${NC} (${OMS_DOTFILES})"
  fi
  echo -e "${BOLD}│${NC}"

  # 모듈 & 링크
  echo -e "${BOLD}├─ 모듈 & 심링크${NC}"
  if [[ -n "$modules" ]]; then
    echo -e "${BOLD}│${NC}   활성 모듈     ${modules}"
  else
    echo -e "${BOLD}│${NC}   활성 모듈     ${DIM}(없음)${NC}"
  fi
  local link_status=""
  [[ "$link_ok" -gt 0 ]]       && link_status+="${GREEN}✓ ${link_ok}${NC} "
  [[ "$link_broken" -gt 0 ]]   && link_status+="${RED}✗ ${link_broken} 깨짐${NC} "
  [[ "$link_missing" -gt 0 ]]  && link_status+="${YELLOW}◌ ${link_missing} 미적용${NC}"
  [[ -z "$link_status" ]]      && link_status="${DIM}(없음)${NC}"
  echo -e "${BOLD}│${NC}   심링크        ${link_status}"
  echo -e "${BOLD}│${NC}"

  # Brew
  echo -e "${BOLD}├─ Brew 패키지${NC}"
  echo -e "${BOLD}│${NC}   $(_status_brew)"
  echo -e "${BOLD}│${NC}"

  # 백업
  echo -e "${BOLD}├─ 백업${NC}"
  echo -e "${BOLD}│${NC}   $(_status_backup)"
  echo -e "${BOLD}│${NC}"

  # 추천 액션
  local actions=()
  [[ ! -d "$HOME/.oh-my-zsh" ]] && actions+=("oh-my-zsh 설치 필요 (install.sh 재실행)")
  [[ "$link_missing" -gt 0 ]]   && actions+=("oms apply — 미적용 심링크 ${link_missing}개")
  [[ "$link_broken" -gt 0 ]]    && actions+=("oms apply — 깨진 심링크 ${link_broken}개 재설정")
  if [[ -d "$OMS_DOTFILES/.git" ]]; then
    local dot_dirty
    dot_dirty="$(git -C "$OMS_DOTFILES" status --porcelain 2>/dev/null | head -1)"
    [[ -n "$dot_dirty" ]] && actions+=("oms sync — dotfiles 변경사항 푸시")
  fi

  if [[ ${#actions[@]} -gt 0 ]]; then
    echo -e "${BOLD}└─ 추천 액션${NC}"
    local a
    for a in "${actions[@]}"; do
      echo -e "    ${YELLOW}→${NC} $a"
    done
  else
    echo -e "${BOLD}└─${NC} ${GREEN}모든 것이 정상입니다 ✓${NC}"
  fi
  echo ""
}

oms_status_cmd() {
  oms_status "$@"
}
