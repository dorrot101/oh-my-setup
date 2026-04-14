#!/usr/bin/env bash
# oh-my-setup — 업데이트 확인 & 알림
# .zshrc에서 source되어 터미널 열 때 실행

OMS_HOME="${OMS_HOME:-$HOME/.oh-my-setup}"
OMS_DOTFILES="${OMS_DOTFILES:-$HOME/dotfiles}"

# ── 셸 시작 시 업데이트 확인 ──────────────────────
oms_check_update() {
  # 설정 파일 없으면 초기화 안 된 상태 → 종료
  [[ -d "$OMS_DOTFILES/.git" ]] || return 0

  local state_dir="${OMS_DOTFILES}/.oms-state"
  local last_sync_file="${state_dir}/last-sync"
  local interval_days=1

  # 설정에서 check_interval_days 읽기 (가벼운 파싱)
  local setup_toml="${OMS_DOTFILES}/setup.toml"
  if [[ -f "$setup_toml" ]]; then
    local val
    val="$(grep -E '^check_interval_days' "$setup_toml" 2>/dev/null | \
           head -1 | sed 's/.*=[[:space:]]*//' | tr -d '[:space:]')"
    [[ -n "$val" && "$val" =~ ^[0-9]+$ ]] && interval_days="$val"
  fi

  # 마지막 확인 시간 비교
  local current_days last_days
  current_days=$(( $(date +%s) / 86400 ))

  if [[ -f "$last_sync_file" ]]; then
    last_days="$(cat "$last_sync_file" 2>/dev/null)"
    if [[ -n "$last_days" && $(( current_days - last_days )) -lt $interval_days ]]; then
      return 0  # 아직 확인 시간이 아님
    fi
  fi

  # 백그라운드에서 fetch (non-blocking)
  (
    cd "$OMS_DOTFILES" 2>/dev/null || exit
    git fetch origin --quiet 2>/dev/null || exit

    local behind
    behind="$(git rev-list --count HEAD..origin/main 2>/dev/null || echo 0)"

    if [[ "$behind" -gt 0 ]]; then
      # 변경 요약 생성
      local changes
      changes="$(git log --oneline HEAD..origin/main 2>/dev/null)"
      local source_machine
      source_machine="$(git log --format='%s' HEAD..origin/main 2>/dev/null | \
                        grep -oP '(?<=from )[^:]+' | head -1)"

      # 새 brew 패키지 확인
      local new_brews
      new_brews="$(git diff HEAD..origin/main -- Brewfile 2>/dev/null | \
                   grep '^+' | grep -v '^+++' | sed 's/^+//' | \
                   grep -E '^(brew|cask) ' | sed 's/brew "\(.*\)"/\1/; s/cask "\(.*\)"/\1/' || true)"

      # 변경된 닷파일 확인
      local changed_files
      changed_files="$(git diff --name-only HEAD..origin/main 2>/dev/null | \
                       grep -v '.oms-state' | head -5 || true)"

      # 알림 출력
      echo ""
      echo -e "\033[0;36m╭─────────────────────────────────────────────────╮\033[0m"
      echo -e "\033[0;36m│\033[0m  \033[1moh-my-setup:\033[0m 업데이트가 있습니다!               \033[0;36m│\033[0m"
      echo -e "\033[0;36m│\033[0m                                                  \033[0;36m│\033[0m"

      if [[ -n "$source_machine" ]]; then
        printf "\033[0;36m│\033[0m  %-48s\033[0;36m│\033[0m\n" "${source_machine}에서 ${behind}개의 변경사항:"
      else
        printf "\033[0;36m│\033[0m  %-48s\033[0;36m│\033[0m\n" "${behind}개의 변경사항이 있습니다:"
      fi

      if [[ -n "$new_brews" ]]; then
        printf "\033[0;36m│\033[0m    • 새 패키지: %-32s\033[0;36m│\033[0m\n" \
          "$(echo "$new_brews" | tr '\n' ', ' | sed 's/,$//')"
      fi

      if [[ -n "$changed_files" ]]; then
        printf "\033[0;36m│\033[0m    • 변경된 설정: %-30s\033[0;36m│\033[0m\n" \
          "$(echo "$changed_files" | tr '\n' ', ' | sed 's/,$//')"
      fi

      echo -e "\033[0;36m│\033[0m                                                  \033[0;36m│\033[0m"
      echo -e "\033[0;36m│\033[0m  적용하려면: \033[1moms sync\033[0m                             \033[0;36m│\033[0m"
      echo -e "\033[0;36m│\033[0m  자세히 보기: \033[1moms sync --dry-run\033[0m                  \033[0;36m│\033[0m"
      echo -e "\033[0;36m╰─────────────────────────────────────────────────╯\033[0m"
      echo ""
    fi

    # 타임스탬프 갱신
    mkdir -p "$state_dir"
    echo "$current_days" > "$last_sync_file"
  ) &
}

# ── 프레임워크 자체 업데이트 ──────────────────────
oms_self_update() {
  local check_only=false
  [[ "${1:-}" == "--check" ]] && check_only=true

  cd "$OMS_HOME" || { oms_error "프레임워크 디렉토리를 찾을 수 없습니다"; return 1; }

  git fetch origin --quiet 2>/dev/null
  local behind
  behind="$(git rev-list --count HEAD..origin/main 2>/dev/null || echo 0)"

  if [[ "$behind" -eq 0 ]]; then
    oms_ok "oh-my-setup은 최신 버전입니다."
    return 0
  fi

  oms_info "${behind}개의 프레임워크 업데이트가 있습니다."

  if $check_only; then
    git log --oneline HEAD..origin/main
    return 0
  fi

  if oms_confirm "프레임워크를 업데이트하시겠습니까?"; then
    git pull origin main --quiet
    oms_ok "oh-my-setup이 업데이트되었습니다!"
    local new_version
    new_version="$(cat "${OMS_HOME}/.version" 2>/dev/null || echo "unknown")"
    oms_info "현재 버전: ${new_version}"
  fi
}
