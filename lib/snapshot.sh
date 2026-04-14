#!/usr/bin/env bash
# oh-my-setup — 현재 상태 스냅샷 (캡처 & 덮어쓰기)
# 현재 맥북의 실제 상태를 dotfiles 저장소에 반영

# ── 메인 스냅샷 명령 ──────────────────────────────
# Usage: oms_snapshot [options]
oms_snapshot() {
  local do_brew=true
  local do_dotfiles=true
  local do_apps=true
  local do_backup=true
  local do_commit=true
  local do_push=""  # 빈 값이면 setup.toml의 auto_push 따름

  # 옵션 파싱
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --brew-only)      do_dotfiles=false; do_apps=false ;;
      --dotfiles-only)  do_brew=false; do_apps=false ;;
      --apps-only)      do_brew=false; do_dotfiles=false ;;
      --no-backup)      do_backup=false ;;
      --no-commit)      do_commit=false ;;
      --no-push)        do_push=false ;;
      -y|--yes)         OMS_YES="true" ;;
      --dry-run)        OMS_DRY_RUN="true" ;;
      -v|--verbose)     OMS_LOG_LEVEL="debug" ;;
      *)                oms_error "알 수 없는 옵션: $1"; return 1 ;;
    esac
    shift
  done

  local machine_name
  machine_name="$(hostname -s 2>/dev/null || echo "unknown")"

  echo ""
  echo -e "${BOLD}📸 oh-my-setup 스냅샷${NC}"
  echo -e "${DIM}현재 ${machine_name}의 상태를 캡처합니다.${NC}"
  echo ""

  # dotfiles 저장소 확인
  if [[ ! -d "$OMS_DOTFILES" ]]; then
    oms_error "dotfiles 저장소를 찾을 수 없습니다: $OMS_DOTFILES"
    oms_error "'oms init'을 먼저 실행하세요."
    return 1
  fi

  local total_phases=5
  local phase=0

  # Phase 1: 백업
  phase=$((phase + 1))
  if [[ "$do_backup" == "true" ]]; then
    oms_info "Phase ${phase}/${total_phases}: 현재 상태 백업"
    if [[ "${OMS_DRY_RUN}" == "true" ]]; then
      oms_info "[DRY-RUN] 백업 생성 건너뜀"
    else
      oms_backup_create "pre-snapshot" > /dev/null
    fi
  else
    oms_skip "Phase ${phase}/${total_phases}: 백업 건너뜀 (--no-backup)"
  fi

  # Phase 2: Brew 스냅샷
  phase=$((phase + 1))
  if [[ "$do_brew" == "true" ]]; then
    oms_info "Phase ${phase}/${total_phases}: Homebrew 스냅샷"
    _snapshot_brew
  else
    oms_skip "Phase ${phase}/${total_phases}: Brew 건너뜀"
  fi

  # Phase 3: Application 목록 캡처
  phase=$((phase + 1))
  if [[ "$do_apps" == "true" ]]; then
    oms_info "Phase ${phase}/${total_phases}: Application 목록 캡처"
    _snapshot_apps
  else
    oms_skip "Phase ${phase}/${total_phases}: Application 건너뜀"
  fi

  # Phase 4: 닷파일 & Raycast 캡처
  phase=$((phase + 1))
  if [[ "$do_dotfiles" == "true" ]]; then
    oms_info "Phase ${phase}/${total_phases}: 닷파일 & 앱 설정 캡처"
    _snapshot_dotfiles
    _snapshot_raycast
  else
    oms_skip "Phase ${phase}/${total_phases}: 닷파일 건너뜀"
  fi

  # Phase 5: 커밋 & 푸시
  phase=$((phase + 1))
  if [[ "$do_commit" == "true" ]]; then
    oms_info "Phase ${phase}/${total_phases}: 커밋"
    _snapshot_commit "$do_push"
  else
    oms_skip "Phase ${phase}/${total_phases}: 커밋 건너뜀 (--no-commit)"
  fi

  echo ""
  oms_ok "스냅샷 완료!"
}

# ── Brew 스냅샷 ───────────────────────────────────
_snapshot_brew() {
  if ! command -v brew >/dev/null 2>&1; then
    oms_warn "Homebrew가 설치되어 있지 않습니다. 건너뜁니다."
    return 0
  fi

  local brewfile="${OMS_DOTFILES}/Brewfile"
  local old_brewfile=""

  # 기존 Brewfile 내용 저장 (diff용)
  if [[ -f "$brewfile" ]]; then
    old_brewfile="$(cat "$brewfile")"
  fi

  if [[ "${OMS_DRY_RUN}" == "true" ]]; then
    oms_info "[DRY-RUN] brew bundle dump 실행 예정"
    echo ""

    # 현재 상태와 Brewfile 차이를 미리보기
    local temp_brewfile
    temp_brewfile="$(mktemp)"
    brew bundle dump --force --file="$temp_brewfile" 2>/dev/null

    if [[ -f "$brewfile" ]]; then
      local added removed
      added="$(comm -13 <(sort "$brewfile") <(sort "$temp_brewfile") | head -20)"
      removed="$(comm -23 <(sort "$brewfile") <(sort "$temp_brewfile") | head -20)"

      if [[ -n "$added" ]]; then
        echo -e "  ${GREEN}추가될 항목:${NC}"
        echo "$added" | sed 's/^/    + /'
      fi
      if [[ -n "$removed" ]]; then
        echo -e "  ${RED}제거될 항목:${NC}"
        echo "$removed" | sed 's/^/    - /'
      fi
      if [[ -z "$added" && -z "$removed" ]]; then
        oms_skip "Brewfile 변경 없음"
      fi
    else
      local count
      count="$(wc -l < "$temp_brewfile" | tr -d ' ')"
      oms_info "새 Brewfile 생성 예정 (${count}개 항목)"
    fi

    rm -f "$temp_brewfile"
    return 0
  fi

  # 실제 Brewfile 덤프
  oms_ensure_dir "$(dirname "$brewfile")"
  brew bundle dump --force --file="$brewfile" 2>/dev/null

  if [[ $? -ne 0 ]]; then
    oms_error "brew bundle dump 실패"
    return 1
  fi

  # diff 출력
  if [[ -n "$old_brewfile" ]]; then
    local new_brewfile
    new_brewfile="$(cat "$brewfile")"

    if [[ "$old_brewfile" == "$new_brewfile" ]]; then
      oms_skip "Brewfile 변경 없음"
    else
      local added removed
      added="$(comm -13 <(echo "$old_brewfile" | sort) <(echo "$new_brewfile" | sort))"
      removed="$(comm -23 <(echo "$old_brewfile" | sort) <(echo "$new_brewfile" | sort))"

      if [[ -n "$added" ]]; then
        local add_count
        add_count="$(echo "$added" | wc -l | tr -d ' ')"
        echo -e "  ${GREEN}+${add_count}개 추가:${NC}"
        echo "$added" | head -10 | sed 's/^/    /'
        [[ $(echo "$added" | wc -l) -gt 10 ]] && echo "    ... 외 더 있음"
      fi
      if [[ -n "$removed" ]]; then
        local rm_count
        rm_count="$(echo "$removed" | wc -l | tr -d ' ')"
        echo -e "  ${RED}-${rm_count}개 제거:${NC}"
        echo "$removed" | head -10 | sed 's/^/    /'
      fi

      oms_ok "Brewfile 업데이트 완료"
    fi
  else
    local count
    count="$(wc -l < "$brewfile" | tr -d ' ')"
    oms_ok "새 Brewfile 생성 (${count}개 항목)"
  fi
}

# ── 닷파일 캡처 ───────────────────────────────────
_snapshot_dotfiles() {
  local captured=0
  local skipped=0
  local warnings=0

  # 프레임워크 내장 모듈 + 사용자 커스텀 모듈 순회
  local modules_dir="${OMS_HOME}/modules"
  local user_modules_dir="${OMS_DOTFILES}/modules"

  for mod_dir in "$modules_dir"/*/  "$user_modules_dir"/*/; do
    [[ -d "$mod_dir" ]] || continue
    local mod_toml="${mod_dir}module.toml"
    [[ -f "$mod_toml" ]] || continue

    local mod_name
    mod_name="$(basename "$mod_dir")"

    # links 섹션에서 src/target/template 추출
    while IFS= read -r line; do
      local src="" target="" is_template=false

      # src 추출
      if [[ "$line" =~ src[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
        src="${BASH_REMATCH[1]}"
      fi
      # target 추출
      if [[ "$line" =~ target[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
        target="${BASH_REMATCH[1]}"
      fi
      # template 여부
      if [[ "$line" =~ template[[:space:]]*=[[:space:]]*true ]]; then
        is_template=true
      fi

      [[ -z "$target" ]] && continue

      local expanded_target
      expanded_target="$(oms_expand_path "$target")"

      # 템플릿 파일은 역방향 캡처 불가
      if [[ "$is_template" == "true" ]]; then
        if [[ -f "$expanded_target" ]]; then
          oms_warn "템플릿 파일은 역캡처 불가: ${target} (${mod_name})"
          warnings=$((warnings + 1))
        fi
        continue
      fi

      # 대상 파일이 존재하는지 확인
      if [[ ! -f "$expanded_target" && ! -L "$expanded_target" ]]; then
        oms_debug "파일 없음, 건너뜀: ${target}"
        skipped=$((skipped + 1))
        continue
      fi

      # repo 내 소스 경로 결정
      local repo_src="${mod_dir}${src}"

      # 실제 파일 내용과 repo 내용 비교
      local disk_content repo_content
      if [[ -L "$expanded_target" ]]; then
        disk_content="$(cat "$(readlink "$expanded_target")" 2>/dev/null || true)"
      else
        disk_content="$(cat "$expanded_target" 2>/dev/null || true)"
      fi
      repo_content="$(cat "$repo_src" 2>/dev/null || true)"

      if [[ "$disk_content" == "$repo_content" ]]; then
        oms_debug "변경 없음: ${target}"
        skipped=$((skipped + 1))
        continue
      fi

      # 변경 감지
      if [[ "${OMS_DRY_RUN}" == "true" ]]; then
        echo -e "  ${YELLOW}변경됨:${NC} ${target} (${mod_name})"
        captured=$((captured + 1))
        continue
      fi

      # repo로 복사
      oms_ensure_dir "$(dirname "$repo_src")"
      if [[ -L "$expanded_target" ]]; then
        cp -L "$expanded_target" "$repo_src"
      else
        cp "$expanded_target" "$repo_src"
      fi
      echo -e "  ${GREEN}캡처:${NC} ${target} → ${src} (${mod_name})"
      captured=$((captured + 1))
    done < "$mod_toml"
  done

  # 요약
  echo ""
  if [[ $captured -gt 0 ]]; then
    oms_ok "닷파일 ${captured}개 캡처 완료"
  else
    oms_skip "변경된 닷파일 없음"
  fi
  [[ $warnings -gt 0 ]] && oms_warn "템플릿 파일 ${warnings}개는 수동 업데이트 필요"
}

# ── macOS 기본 앱 목록 (제외 대상) ─────────────────
# /System/Applications 에 있는 앱 + Apple 번들 앱
_is_system_app() {
  local app_name="$1"
  # /System/Applications에 있으면 시스템 앱
  [[ -d "/System/Applications/${app_name}" ]] && return 0
  # Apple 기본 번들 앱 (iLife, iWork 등 — /Applications에 있지만 기본 설치)
  case "$app_name" in
    GarageBand.app|iMovie.app|Keynote.app|Numbers.app|Pages.app|Safari.app)
      return 0 ;;
  esac
  return 1
}

# ── Application 목록 캡처 ─────────────────────────
_snapshot_apps() {
  set +e  # grep/find 실패 시 종료 방지
  local apps_file="${OMS_DOTFILES}/apps.toml"
  local old_content=""

  if [[ -f "$apps_file" ]]; then
    old_content="$(cat "$apps_file")"
  fi

  # brew cask 목록 가져오기
  local brew_casks=""
  if command -v brew >/dev/null 2>&1; then
    brew_casks="$(brew list --cask 2>/dev/null | sort)"
  fi

  # brew cask → app name 매핑 구축 (bash 3.x 호환: 임시 파일 사용)
  local cask_map_file
  cask_map_file="$(mktemp)"
  if [[ -n "$brew_casks" ]]; then
    while IFS= read -r cask; do
      # Caskroom에서 실제 설치된 .app 찾기
      local caskroom_dir="/opt/homebrew/Caskroom/${cask}"
      [[ -d "$caskroom_dir" ]] || caskroom_dir="/usr/local/Caskroom/${cask}"
      if [[ -d "$caskroom_dir" ]]; then
        local app_name
        app_name="$(find "$caskroom_dir" -maxdepth 3 -name '*.app' -type d 2>/dev/null | head -1 | xargs -I{} basename {} 2>/dev/null || true)"
        if [[ -n "$app_name" ]]; then
          echo "${app_name}=${cask}" >> "$cask_map_file"
        fi
      fi
    done <<< "$brew_casks"
  fi

  # /Applications 스캔
  local cask_apps=()
  local manual_apps=()

  for app_path in /Applications/*.app; do
    [[ -d "$app_path" ]] || continue
    local app_name
    app_name="$(basename "$app_path")"

    # 시스템 앱 제외
    if _is_system_app "$app_name"; then
      oms_debug "시스템 앱 제외: ${app_name}"
      continue
    fi

    # Utilities 디렉토리 제외
    [[ "$app_name" == "Utilities" ]] && continue

    # brew cask 여부 판별 (임시 파일에서 lookup)
    local matched_cask
    matched_cask="$(grep "^${app_name}=" "$cask_map_file" 2>/dev/null | head -1 | cut -d= -f2- || true)"
    if [[ -n "$matched_cask" ]]; then
      cask_apps+=("${matched_cask}|${app_name}")
    else
      # brew cask 이름으로 직접 매칭 시도 (app 이름을 소문자+하이픈으로 변환)
      local guess
      guess="$(echo "${app_name%.app}" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"
      if echo "$brew_casks" | grep -q "^${guess}$" 2>/dev/null; then
        cask_apps+=("${guess}|${app_name}")
      else
        manual_apps+=("$app_name")
      fi
    fi
  done

  rm -f "$cask_map_file"

  # apps.toml 생성
  local new_content=""
  new_content+="# oh-my-setup: Application 목록"$'\n'
  new_content+="# 자동 생성됨 — $(date '+%Y-%m-%d %H:%M')"$'\n'
  new_content+="# brew cask 앱은 Brewfile로 설치, manual 앱은 수동 설치 필요"$'\n'
  new_content+=""$'\n'

  new_content+="[brew_cask]"$'\n'
  new_content+="# brew install --cask <name> 으로 설치 가능"$'\n'
  new_content+="apps = ["$'\n'
  if [[ ${#cask_apps[@]} -gt 0 ]]; then
    for entry in "${cask_apps[@]}"; do
      local cask="${entry%%|*}"
      local name="${entry##*|}"
      new_content+="  \"${cask}\",  # ${name}"$'\n'
    done
  fi
  new_content+="]"$'\n'
  new_content+=""$'\n'

  new_content+="[manual]"$'\n'
  new_content+="# 수동 설치 필요 (App Store, 공식 사이트 등)"$'\n'
  new_content+="apps = ["$'\n'
  if [[ ${#manual_apps[@]} -gt 0 ]]; then
    for app in "${manual_apps[@]}"; do
      new_content+="  \"${app%.app}\","$'\n'
    done
  fi
  new_content+="]"$'\n'

  if [[ "${OMS_DRY_RUN}" == "true" ]]; then
    echo -e "  ${CYAN}brew cask 앱:${NC} ${#cask_apps[@]}개"
    if [[ ${#cask_apps[@]} -gt 0 ]]; then
      for entry in "${cask_apps[@]}"; do
        echo "    - ${entry%%|*} (${entry##*|})"
      done
    fi
    echo -e "  ${YELLOW}수동 설치 앱:${NC} ${#manual_apps[@]}개"
    if [[ ${#manual_apps[@]} -gt 0 ]]; then
      for app in "${manual_apps[@]}"; do
        echo "    - ${app%.app}"
      done
    fi
    set -e
    return 0
  fi

  # 변경 여부 확인
  if [[ "$old_content" == "$new_content" ]]; then
    oms_skip "Application 목록 변경 없음"
    return 0
  fi

  echo "$new_content" > "$apps_file"

  echo -e "  ${CYAN}brew cask 앱:${NC} ${#cask_apps[@]}개"
  echo -e "  ${YELLOW}수동 설치 앱:${NC} ${#manual_apps[@]}개"
  oms_ok "Application 목록 저장: apps.toml"
  set -e
}

# ── Raycast 설정 캡처 ─────────────────────────────
_snapshot_raycast() {
  # Raycast가 설치되어 있는지 확인
  if [[ ! -d "/Applications/Raycast.app" ]]; then
    oms_debug "Raycast 미설치, 건너뜀"
    return 0
  fi

  local raycast_mod_dir="${OMS_HOME}/modules/raycast"
  local raycast_dotfiles="${raycast_mod_dir}/dotfiles"
  local captured=0

  oms_ensure_dir "$raycast_dotfiles"

  # 1. Raycast plist 설정 캡처
  local plist_src="$HOME/Library/Preferences/com.raycast.macos.plist"
  local plist_dest="${raycast_dotfiles}/com.raycast.macos.plist"

  if [[ -f "$plist_src" ]]; then
    if [[ "${OMS_DRY_RUN}" == "true" ]]; then
      echo -e "  ${YELLOW}Raycast:${NC} plist 설정 캡처 예정"
      captured=$((captured + 1))
    else
      # binary plist을 XML로 변환하여 저장 (diff 가능하게)
      plutil -convert xml1 -o "$plist_dest" "$plist_src" 2>/dev/null
      if [[ $? -eq 0 ]]; then
        echo -e "  ${GREEN}캡처:${NC} Raycast plist 설정"
        captured=$((captured + 1))
      else
        # 변환 실패 시 바이너리 그대로 복사
        cp "$plist_src" "$plist_dest"
        echo -e "  ${GREEN}캡처:${NC} Raycast plist 설정 (binary)"
        captured=$((captured + 1))
      fi
    fi
  fi

  # 2. Raycast 스크립트 캡처
  local scripts_src="$HOME/.config/raycast/scripts"
  local scripts_dest="${raycast_dotfiles}/scripts"

  if [[ -d "$scripts_src" ]]; then
    local script_count
    script_count="$(find "$scripts_src" -type f -not -name '.*' | wc -l | tr -d ' ')"

    if [[ $script_count -gt 0 ]]; then
      if [[ "${OMS_DRY_RUN}" == "true" ]]; then
        echo -e "  ${YELLOW}Raycast:${NC} 스크립트 ${script_count}개 캡처 예정"
        find "$scripts_src" -type f -not -name '.*' | while read -r f; do
          echo "    - $(basename "$f")"
        done
        captured=$((captured + script_count))
      else
        oms_ensure_dir "$scripts_dest"
        # 기존 스크립트 정리 후 복사
        rm -rf "${scripts_dest:?}"/*
        cp -R "$scripts_src"/* "$scripts_dest"/ 2>/dev/null || true
        echo -e "  ${GREEN}캡처:${NC} Raycast 스크립트 ${script_count}개"
        captured=$((captured + script_count))
      fi
    fi
  fi

  # 3. Raycast 확장 목록 저장 (확장 코드는 너무 크므로 목록만)
  local extensions_src="$HOME/.config/raycast/extensions"
  local extensions_list="${raycast_dotfiles}/extensions.txt"

  if [[ -d "$extensions_src" ]]; then
    local ext_count
    ext_count="$(find "$extensions_src" -maxdepth 1 -type d | wc -l | tr -d ' ')"
    ext_count=$((ext_count - 1))  # 자기 자신 제외

    if [[ $ext_count -gt 0 ]]; then
      if [[ "${OMS_DRY_RUN}" != "true" ]]; then
        # 확장 디렉토리에서 package.json 읽어 이름 추출
        {
          echo "# Raycast Extensions ($(date '+%Y-%m-%d'))"
          echo "# 참고용 목록 — 확장은 Raycast 앱에서 직접 설치"
          echo ""
          for ext_dir in "$extensions_src"/*/; do
            [[ -d "$ext_dir" ]] || continue
            local pkg_json="${ext_dir}package.json"
            if [[ -f "$pkg_json" ]]; then
              local ext_name ext_title
              ext_name="$(grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$pkg_json" | head -1 | cut -d'"' -f4)"
              ext_title="$(grep -o '"title"[[:space:]]*:[[:space:]]*"[^"]*"' "$pkg_json" | head -1 | cut -d'"' -f4)"
              echo "${ext_name:-unknown}  # ${ext_title:-}"
            else
              echo "$(basename "$ext_dir")  # (package.json 없음)"
            fi
          done
        } > "$extensions_list"
        echo -e "  ${GREEN}캡처:${NC} Raycast 확장 목록 (${ext_count}개)"
      else
        echo -e "  ${YELLOW}Raycast:${NC} 확장 목록 ${ext_count}개 저장 예정"
      fi
    fi
  fi

  if [[ $captured -gt 0 || "${OMS_DRY_RUN}" == "true" ]]; then
    [[ "${OMS_DRY_RUN}" != "true" ]] && oms_ok "Raycast 설정 캡처 완료"
  else
    oms_skip "Raycast 설정 변경 없음"
  fi
}

# ── 커밋 & 푸시 ───────────────────────────────────
_snapshot_commit() {
  local force_no_push="$1"
  local machine_name
  machine_name="$(hostname -s 2>/dev/null || echo "unknown")"
  local date_str
  date_str="$(date '+%Y-%m-%d %H:%M')"

  cd "$OMS_DOTFILES" || return 1

  # 변경사항 확인
  local changes
  changes="$(git status --porcelain 2>/dev/null)"

  if [[ -z "$changes" ]]; then
    oms_skip "커밋할 변경사항 없음"
    return 0
  fi

  echo -e "\n${DIM}변경된 파일:${NC}"
  git status --short | head -20 | sed 's/^/  /'
  local total
  total="$(echo "$changes" | wc -l | tr -d ' ')"
  [[ $total -gt 20 ]] && echo "  ... 외 $((total - 20))개"
  echo ""

  if [[ "${OMS_DRY_RUN}" == "true" ]]; then
    oms_info "[DRY-RUN] 커밋 예정: [oms] snapshot from ${machine_name}: ${date_str}"
    return 0
  fi

  if ! oms_confirm "변경사항을 커밋하시겠습니까?"; then
    oms_info "커밋 취소됨. 변경사항은 스테이징되지 않은 상태로 유지됩니다."
    return 0
  fi

  # 커밋
  git add -A
  git commit -m "[oms] snapshot from ${machine_name}: ${date_str}" --quiet

  oms_ok "커밋 완료"

  # 푸시 결정
  local should_push=false
  if [[ "$force_no_push" == "false" ]]; then
    should_push=false
  elif [[ -n "$force_no_push" && "$force_no_push" != "false" ]]; then
    # do_push가 명시적으로 설정되지 않은 경우 setup.toml 확인
    local setup_toml
    setup_toml="$(oms_setup_toml)"
    if [[ -f "$setup_toml" ]]; then
      local auto_push
      auto_push="$(oms_config_get "$setup_toml" "git.auto_push" 2>/dev/null || echo "true")"
      [[ "$auto_push" == "true" ]] && should_push=true
    fi
  fi

  if [[ "$should_push" == "true" ]]; then
    if oms_confirm "원격 저장소에 푸시하시겠습니까?"; then
      git push --quiet 2>/dev/null
      if [[ $? -eq 0 ]]; then
        oms_ok "푸시 완료"
      else
        oms_warn "푸시 실패. 나중에 'git push'를 실행하세요."
      fi
    fi
  fi
}
