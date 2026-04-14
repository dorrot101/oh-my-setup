#!/usr/bin/env bash
# oh-my-setup — macOS 시스템 설정 적용 (프로파일 기반)

# ── 지원하는 설정 키 → 명령어 매핑 ──────────────
_macos_apply_setting() {
  local key="$1" value="$2"

  case "$key" in
    lid_close_action)
      if [[ "$value" == "no-sleep" ]]; then
        echo "sudo pmset -a disablesleep 1"
      elif [[ "$value" == "sleep" ]]; then
        echo "sudo pmset -a disablesleep 0"
      fi
      ;;
    display_sleep)
      echo "sudo pmset -a displaysleep ${value}"
      ;;
    system_sleep)
      echo "sudo pmset -a sleep ${value}"
      ;;
    disk_sleep)
      echo "sudo pmset -a disksleep ${value}"
      ;;
    show_scroll_bars)
      # "Always", "WhenScrolling", "Automatic"
      echo "defaults write NSGlobalDomain AppleShowScrollBars -string '${value}'"
      ;;
    dock_autohide)
      if [[ "$value" == "true" ]]; then
        echo "defaults write com.apple.dock autohide -bool true"
      else
        echo "defaults write com.apple.dock autohide -bool false"
      fi
      ;;
    dock_size)
      echo "defaults write com.apple.dock tilesize -int ${value}"
      ;;
    key_repeat_rate)
      echo "defaults write NSGlobalDomain KeyRepeat -int ${value}"
      ;;
    key_initial_repeat)
      echo "defaults write NSGlobalDomain InitialKeyRepeat -int ${value}"
      ;;
    *)
      oms_warn "알 수 없는 macOS 설정: ${key}"
      return 1
      ;;
  esac
}

# ── 메인: macOS 설정 적용 ────────────────────────
# Usage: oms_macos_apply [options]
oms_macos_apply() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)   OMS_DRY_RUN="true" ;;
      -y|--yes)    OMS_YES="true" ;;
      -v|--verbose) OMS_LOG_LEVEL="debug" ;;
      *)           ;;
    esac
    shift
  done

  # 프로파일 찾기
  local setup_toml
  setup_toml="$(oms_setup_toml)"
  local profile=""

  if [[ -f "$setup_toml" ]]; then
    profile="$(oms_config_get "$setup_toml" "meta.profile" 2>/dev/null || true)"
  fi

  if [[ -z "$profile" ]]; then
    oms_skip "프로파일 미설정 — macOS 시스템 설정 건너뜀"
    oms_info "setup.toml의 [meta] profile 값을 설정하세요 (예: laptop, server)"
    return 0
  fi

  local profile_toml="${OMS_HOME}/templates/profiles/${profile}.toml"
  if [[ ! -f "$profile_toml" ]]; then
    oms_warn "프로파일 파일을 찾을 수 없습니다: ${profile_toml}"
    return 1
  fi

  echo ""
  echo -e "${BOLD}⚙️  macOS 시스템 설정 (프로파일: ${profile})${NC}"
  echo ""

  # [macos.defaults] 섹션에서 키-값 추출
  local commands=()
  local labels=()
  local in_section=false

  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    # 섹션 감지
    if [[ "$line" =~ ^\[([a-zA-Z0-9_.]+)\] ]]; then
      local section="${BASH_REMATCH[1]}"
      if [[ "$section" == "macos.defaults" ]]; then
        in_section=true
      else
        in_section=false
      fi
      continue
    fi

    if $in_section; then
      if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*) ]]; then
        local key="${BASH_REMATCH[1]}"
        local value="${BASH_REMATCH[2]}"
        # 값 정리
        value="${value%%#*}"
        value="${value%"${value##*[![:space:]]}"}"
        value="${value#\"}"
        value="${value%\"}"

        local cmd
        cmd="$(_macos_apply_setting "$key" "$value")"
        if [[ -n "$cmd" ]]; then
          commands+=("$cmd")
          labels+=("$key = $value")
        fi
      fi
    fi
  done < "$profile_toml"

  if [[ ${#commands[@]} -eq 0 ]]; then
    oms_skip "적용할 macOS 설정이 없습니다."
    return 0
  fi

  # 설정 목록 출력
  local i
  for i in "${!labels[@]}"; do
    echo -e "  ${CYAN}•${NC} ${labels[$i]}"
    echo -e "    ${DIM}${commands[$i]}${NC}"
  done
  echo ""

  if [[ "${OMS_DRY_RUN}" == "true" ]]; then
    oms_info "[DRY-RUN] ${#commands[@]}개 설정 적용 예정"
    return 0
  fi

  # sudo 필요 여부 확인
  local needs_sudo=false
  for cmd in "${commands[@]}"; do
    [[ "$cmd" == sudo* ]] && needs_sudo=true && break
  done

  if [[ "$needs_sudo" == "true" ]]; then
    oms_warn "일부 설정에 관리자 권한이 필요합니다."
  fi

  if ! oms_confirm "macOS 시스템 설정을 적용하시겠습니까?"; then
    oms_info "건너뜀."
    return 0
  fi

  # 실행
  local success=0 failed=0
  for i in "${!commands[@]}"; do
    echo -ne "  적용 중: ${labels[$i]} ... "
    if eval "${commands[$i]}" 2>/dev/null; then
      echo -e "${GREEN}완료${NC}"
      success=$((success + 1))
    else
      echo -e "${RED}실패${NC}"
      failed=$((failed + 1))
    fi
  done

  echo ""
  oms_ok "${success}개 설정 적용 완료"
  [[ $failed -gt 0 ]] && oms_warn "${failed}개 설정 적용 실패"
}
