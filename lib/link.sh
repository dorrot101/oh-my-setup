#!/usr/bin/env bash
# oh-my-setup — 닷파일 심링크 관리 (repo → 시스템)

OMS_LINK_BACKUP_DIR="${OMS_LINK_BACKUP_DIR:-$HOME/.oh-my-setup-backup}"

# ── 프로파일에서 활성 모듈 목록 가져오기 ─────────
_link_get_enabled_modules() {
  local setup_toml
  setup_toml="$(oms_setup_toml)"

  # 1. setup.toml의 modules.enabled
  local enabled=()
  if [[ -f "$setup_toml" ]]; then
    while IFS= read -r mod; do
      [[ -n "$mod" ]] && enabled+=("$mod")
    done < <(oms_config_get_array "$setup_toml" "modules.enabled" 2>/dev/null)
  fi

  # 2. 프로파일의 modules.enabled (있으면 병합)
  local profile
  profile="$(oms_config_get "$setup_toml" "meta.profile" 2>/dev/null || true)"
  if [[ -n "$profile" ]]; then
    local profile_toml="${OMS_HOME}/templates/profiles/${profile}.toml"
    if [[ -f "$profile_toml" ]]; then
      # 프로파일에 enabled가 있으면 그걸 기본으로 사용
      local profile_enabled=()
      while IFS= read -r mod; do
        [[ -n "$mod" ]] && profile_enabled+=("$mod")
      done < <(oms_config_get_array "$profile_toml" "modules.enabled" 2>/dev/null)

      if [[ ${#profile_enabled[@]} -gt 0 && ${#enabled[@]} -eq 0 ]]; then
        enabled=("${profile_enabled[@]}")
      fi

      # skip 목록 적용
      local skip_mods=()
      while IFS= read -r mod; do
        [[ -n "$mod" ]] && skip_mods+=("$mod")
      done < <(oms_config_get_array "$profile_toml" "modules.skip" 2>/dev/null)

      if [[ ${#skip_mods[@]} -gt 0 ]]; then
        local filtered=()
        local e s found
        for e in "${enabled[@]}"; do
          found=false
          for s in "${skip_mods[@]}"; do
            [[ "$e" == "$s" ]] && found=true && break
          done
          [[ "$found" == "false" ]] && filtered+=("$e")
        done
        if [[ ${#filtered[@]} -gt 0 ]]; then
        enabled=("${filtered[@]}")
      else
        enabled=()
      fi
      fi
    fi
  fi

  # 3. machines/<name>.toml의 extra/skip 오버라이드
  local machine_toml
  machine_toml="$(oms_machine_toml)"
  if [[ -n "$machine_toml" && -f "$machine_toml" ]]; then
    while IFS= read -r mod; do
      [[ -n "$mod" ]] && enabled+=("$mod")
    done < <(oms_config_get_array "$machine_toml" "modules.extra" 2>/dev/null)

    local machine_skip=()
    while IFS= read -r mod; do
      [[ -n "$mod" ]] && machine_skip+=("$mod")
    done < <(oms_config_get_array "$machine_toml" "modules.skip" 2>/dev/null)

    if [[ ${#machine_skip[@]} -gt 0 ]]; then
      local filtered=()
      local e s found
      for e in "${enabled[@]}"; do
        found=false
        for s in "${machine_skip[@]}"; do
          [[ "$e" == "$s" ]] && found=true && break
        done
        [[ "$found" == "false" ]] && filtered+=("$e")
      done
      if [[ ${#filtered[@]} -gt 0 ]]; then
        enabled=("${filtered[@]}")
      else
        enabled=()
      fi
    fi
  fi

  # 중복 제거 후 출력
  if [[ ${#enabled[@]} -gt 0 ]]; then
    printf '%s\n' "${enabled[@]}" | sort -u
  fi
}

# ── 모듈 디렉토리 찾기 ──────────────────────────
_link_find_module_dir() {
  local mod_name="$1"

  # 사용자 커스텀 모듈 우선 (개인 닷파일은 private dotfiles repo에)
  local dir="${OMS_DOTFILES}/modules/${mod_name}"
  [[ -d "$dir" ]] && echo "$dir" && return 0

  # 프레임워크 내장 모듈 (템플릿/기본값)
  dir="${OMS_HOME}/modules/${mod_name}"
  [[ -d "$dir" ]] && echo "$dir" && return 0

  return 1
}

# ── 단일 파일 심링크 생성 ────────────────────────
_link_create_symlink() {
  local src="$1"     # repo 내 소스 파일/디렉토리 절대경로
  local target="$2"  # 시스템 대상 경로 (확장 완료)

  # 소스 존재 확인 (파일 또는 디렉토리)
  if [[ ! -e "$src" ]]; then
    oms_debug "소스 없음, 건너뜀: $src"
    return 0
  fi

  local src_kind="파일"
  [[ -d "$src" ]] && src_kind="디렉토리"

  # 대상 디렉토리 생성
  oms_ensure_dir "$(dirname "$target")"

  # 이미 올바른 심링크인 경우
  if [[ -L "$target" ]]; then
    local current_target
    current_target="$(readlink "$target")"
    if [[ "$current_target" == "$src" ]]; then
      oms_skip "이미 연결됨: $target"
      return 0
    fi
  fi

  # 기존 파일이 있는 경우 백업
  if [[ -e "$target" || -L "$target" ]]; then
    if [[ "${OMS_DRY_RUN}" == "true" ]]; then
      echo -e "  ${YELLOW}백업 예정:${NC} $target → ${OMS_LINK_BACKUP_DIR}/"
    else
      local backup_path="${OMS_LINK_BACKUP_DIR}/$(date +%Y%m%d-%H%M%S)"
      local rel_path="${target#$HOME/}"
      oms_ensure_dir "$(dirname "${backup_path}/${rel_path}")"
      mv "$target" "${backup_path}/${rel_path}"
      oms_debug "백업: $target → ${backup_path}/${rel_path}"
    fi
  fi

  if [[ "${OMS_DRY_RUN}" == "true" ]]; then
    echo -e "  ${GREEN}링크 예정:${NC} $src → $target"
    return 0
  fi

  ln -sfn "$src" "$target"
  echo -e "  ${GREEN}링크(${src_kind}):${NC} $(basename "$src") → $target"
}

# ── 템플릿 변수 치환 후 파일 생성 ────────────────
_link_render_template() {
  local src="$1"       # .tpl 파일 경로
  local target="$2"    # 대상 경로
  local mod_toml="$3"  # module.toml 경로

  if [[ ! -f "$src" ]]; then
    oms_debug "템플릿 파일 없음, 건너뜀: $src"
    return 0
  fi

  # 변수 수집 (우선순위: module.toml < setup.toml < machine.toml < env)
  local content
  content="$(cat "$src")"

  # module.toml의 [template_vars]
  local setup_toml machine_toml
  setup_toml="$(oms_setup_toml)"
  machine_toml="$(oms_machine_toml)"

  # {{변수명}} 패턴 찾아서 치환
  while [[ "$content" =~ \{\{([a-zA-Z_][a-zA-Z0-9_]*)\}\} ]]; do
    local var_name="${BASH_REMATCH[1]}"
    local var_value=""

    # 1. 환경 변수 OMS_VAR_<NAME> (최우선)
    local env_var="OMS_VAR_${var_name}"
    if [[ -n "${!env_var+x}" ]]; then
      var_value="${!env_var}"
    # 2. machine.toml
    elif [[ -n "$machine_toml" && -f "$machine_toml" ]]; then
      var_value="$(oms_config_get "$machine_toml" "template_vars.${var_name}" 2>/dev/null || true)"
    fi
    # 3. setup.toml
    if [[ -z "$var_value" && -f "$setup_toml" ]]; then
      var_value="$(oms_config_get "$setup_toml" "template_vars.${var_name}" 2>/dev/null || true)"
    fi
    # 4. module.toml 기본값
    if [[ -z "$var_value" ]]; then
      var_value="$(oms_config_get "$mod_toml" "template_vars.${var_name}" 2>/dev/null || true)"
    fi

    # 치환 (빈 값이면 빈 문자열로)
    content="${content//\{\{${var_name}\}\}/${var_value}}"
  done

  # 대상 디렉토리 생성
  oms_ensure_dir "$(dirname "$target")"

  # 기존 파일과 동일한지 확인
  if [[ -f "$target" ]]; then
    local existing
    existing="$(cat "$target")"
    if [[ "$existing" == "$content" ]]; then
      oms_skip "변경 없음: $target"
      return 0
    fi
  fi

  # 기존 파일 백업
  if [[ -e "$target" ]]; then
    if [[ "${OMS_DRY_RUN}" != "true" ]]; then
      local backup_path="${OMS_LINK_BACKUP_DIR}/$(date +%Y%m%d-%H%M%S)"
      local rel_path="${target#$HOME/}"
      oms_ensure_dir "$(dirname "${backup_path}/${rel_path}")"
      cp "$target" "${backup_path}/${rel_path}"
      oms_debug "백업: $target"
    fi
  fi

  if [[ "${OMS_DRY_RUN}" == "true" ]]; then
    echo -e "  ${GREEN}템플릿 생성 예정:${NC} $(basename "$src") → $target"
    return 0
  fi

  echo "$content" > "$target"
  echo -e "  ${GREEN}템플릿:${NC} $(basename "$src") → $target"
}

# ── 메인: 닷파일 심링크 적용 ────────────────────
# Usage: oms_link [options]
oms_link() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)   OMS_DRY_RUN="true" ;;
      -y|--yes)    OMS_YES="true" ;;
      -v|--verbose) OMS_LOG_LEVEL="debug" ;;
      *)           oms_error "알 수 없는 옵션: $1"; return 1 ;;
    esac
    shift
  done

  echo ""
  echo -e "${BOLD}🔗 닷파일 심링크 적용${NC}"
  echo ""

  # 활성 모듈 목록
  local enabled_modules=()
  while IFS= read -r mod; do
    [[ -n "$mod" ]] && enabled_modules+=("$mod")
  done < <(_link_get_enabled_modules)

  if [[ ${#enabled_modules[@]} -eq 0 ]]; then
    # 모듈 목록이 없으면 모든 모듈 디렉토리 스캔
    for mod_dir in "${OMS_HOME}/modules"/*/ "${OMS_DOTFILES}/modules"/*/; do
      [[ -d "$mod_dir" ]] || continue
      [[ -f "${mod_dir}module.toml" ]] || continue
      enabled_modules+=("$(basename "$mod_dir")")
    done
  fi

  oms_info "활성 모듈: ${enabled_modules[*]}"
  echo ""

  local linked=0
  local skipped=0
  local templates=0

  set +e  # grep 실패 방지
  local mod_name
  for mod_name in "${enabled_modules[@]}"; do
    local mod_dir
    mod_dir="$(_link_find_module_dir "$mod_name")" || continue
    local mod_toml="${mod_dir}/module.toml"
    [[ -f "$mod_toml" ]] || continue

    echo -e "${CYAN}[$mod_name]${NC}"

    # module.toml에서 links 파싱
    while IFS= read -r line; do
      local src="" target="" is_template=false

      if [[ "$line" =~ src[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
        src="${BASH_REMATCH[1]}"
      fi
      if [[ "$line" =~ target[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
        target="${BASH_REMATCH[1]}"
      fi
      if [[ "$line" =~ template[[:space:]]*=[[:space:]]*true ]]; then
        is_template=true
      fi

      [[ -z "$src" || -z "$target" ]] && continue

      local abs_src="${mod_dir}/${src}"
      local abs_target
      abs_target="$(oms_expand_path "$target")"

      if [[ "$is_template" == "true" ]]; then
        _link_render_template "$abs_src" "$abs_target" "$mod_toml"
        templates=$((templates + 1))
      else
        _link_create_symlink "$abs_src" "$abs_target"
        linked=$((linked + 1))
      fi
    done < "$mod_toml"
  done
  set -e

  echo ""
  oms_ok "완료 — 심링크 ${linked}개, 템플릿 ${templates}개"
}

# ── CLI 라우터 ───────────────────────────────────
oms_link_cmd() {
  oms_link "$@"
}
