#!/usr/bin/env bash
# oh-my-setup — 기기별 백업 관리
# 스냅샷/동기화 전 현재 상태를 안전하게 백업하고 복원

# ── 상수 ──────────────────────────────────────────
OMS_BACKUP_BASE="${OMS_DOTFILES}/.oms-state/backups"
OMS_BACKUP_KEEP=5  # 기본 보관 개수

# ── 백업 생성 ─────────────────────────────────────
# Usage: oms_backup_create [label]
# 현재 Brewfile, 닷파일, machine toml을 백업
oms_backup_create() {
  local label="${1:-manual}"
  local machine_name
  machine_name="$(hostname -s 2>/dev/null || echo "unknown")"
  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local backup_dir="${OMS_BACKUP_BASE}/${machine_name}/${timestamp}"

  oms_info "백업 생성 중: ${machine_name}/${timestamp} (${label})"

  oms_ensure_dir "$backup_dir"

  # Brewfile 백업
  local brewfile="${OMS_DOTFILES}/Brewfile"
  if [[ -f "$brewfile" ]]; then
    cp "$brewfile" "${backup_dir}/Brewfile"
    oms_debug "Brewfile 백업 완료"
  fi

  # machine toml 백업
  local machine_toml="${OMS_DOTFILES}/machines/${machine_name}.toml"
  if [[ -f "$machine_toml" ]]; then
    oms_ensure_dir "${backup_dir}/machines"
    cp "$machine_toml" "${backup_dir}/machines/${machine_name}.toml"
    oms_debug "machine toml 백업 완료"
  fi

  # 관리 중인 닷파일 백업
  _backup_managed_dotfiles "$backup_dir"

  # 매니페스트 생성
  cat > "${backup_dir}/manifest.txt" <<EOF
machine: ${machine_name}
timestamp: ${timestamp}
date: $(date '+%Y-%m-%d %H:%M:%S')
label: ${label}
files:
$(cd "$backup_dir" && find . -type f -not -name manifest.txt | sort | sed 's|^./|  |')
EOF

  oms_ok "백업 완료: ${backup_dir}"

  # .gitignore에 backups 디렉토리 추가 (최초 1회)
  _ensure_backups_gitignored

  echo "$backup_dir"
}

# ── 관리 닷파일 백업 ──────────────────────────────
_backup_managed_dotfiles() {
  local backup_dir="$1"
  local dotfiles_dir="${backup_dir}/dotfiles"

  # 활성화된 모듈의 링크 대상 파일들을 백업
  local modules_dir="${OMS_HOME}/modules"
  local user_modules_dir="${OMS_DOTFILES}/modules"

  for mod_dir in "$modules_dir"/*/  "$user_modules_dir"/*/; do
    [[ -d "$mod_dir" ]] || continue
    local mod_toml="${mod_dir}module.toml"
    [[ -f "$mod_toml" ]] || continue

    # module.toml에서 links 섹션의 target 추출 (간단 파싱)
    while IFS= read -r line; do
      if [[ "$line" =~ target[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
        local target="${BASH_REMATCH[1]}"
        local expanded
        expanded="$(oms_expand_path "$target")"

        if [[ -f "$expanded" || -L "$expanded" ]]; then
          local rel_path="${target#\~/}"
          oms_ensure_dir "$(dirname "${dotfiles_dir}/${rel_path}")"
          # 심링크면 실제 파일 내용을 복사
          if [[ -L "$expanded" ]]; then
            cp -L "$expanded" "${dotfiles_dir}/${rel_path}" 2>/dev/null || true
          else
            cp "$expanded" "${dotfiles_dir}/${rel_path}" 2>/dev/null || true
          fi
          oms_debug "닷파일 백업: ${target}"
        fi
      fi
    done < "$mod_toml"
  done
}

# ── 백업 목록 ─────────────────────────────────────
# Usage: oms_backup_list
oms_backup_list() {
  local machine_name
  machine_name="$(hostname -s 2>/dev/null || echo "unknown")"
  local machine_backup_dir="${OMS_BACKUP_BASE}/${machine_name}"

  if [[ ! -d "$machine_backup_dir" ]]; then
    oms_info "백업이 없습니다."
    return 0
  fi

  echo -e "\n${BOLD}📦 백업 목록 (${machine_name})${NC}\n"

  local count=0
  for dir in $(ls -1dr "${machine_backup_dir}"/*/ 2>/dev/null); do
    local ts
    ts="$(basename "$dir")"
    local manifest="${dir}manifest.txt"
    local label="unknown"
    local date_str="$ts"

    if [[ -f "$manifest" ]]; then
      label="$(grep '^label:' "$manifest" | cut -d' ' -f2-)"
      date_str="$(grep '^date:' "$manifest" | cut -d' ' -f2-)"
    fi

    local file_count
    file_count="$(find "$dir" -type f -not -name manifest.txt | wc -l | tr -d ' ')"

    printf "  ${CYAN}%-20s${NC}  %-20s  ${DIM}%s개 파일${NC}\n" "$ts" "$label" "$file_count"
    count=$((count + 1))
  done

  if [[ $count -eq 0 ]]; then
    oms_info "백업이 없습니다."
  else
    echo -e "\n  총 ${count}개 백업"
  fi
}

# ── 백업 복원 ─────────────────────────────────────
# Usage: oms_backup_restore <timestamp|"latest">
oms_backup_restore() {
  local target="${1:-latest}"
  local machine_name
  machine_name="$(hostname -s 2>/dev/null || echo "unknown")"
  local machine_backup_dir="${OMS_BACKUP_BASE}/${machine_name}"

  if [[ ! -d "$machine_backup_dir" ]]; then
    oms_error "복원할 백업이 없습니다."
    return 1
  fi

  # latest면 가장 최근 백업 찾기
  if [[ "$target" == "latest" ]]; then
    target="$(ls -1d "${machine_backup_dir}"/*/ 2>/dev/null | sort -r | head -1)"
    target="$(basename "$target")"
  fi

  local restore_dir="${machine_backup_dir}/${target}"
  if [[ ! -d "$restore_dir" ]]; then
    oms_error "백업을 찾을 수 없습니다: ${target}"
    return 1
  fi

  oms_info "백업 복원: ${target}"

  # 복원 전 현재 상태를 백업
  oms_backup_create "pre-restore"

  if [[ "${OMS_DRY_RUN}" == "true" ]]; then
    oms_info "[DRY-RUN] 복원할 파일:"
    find "$restore_dir" -type f -not -name manifest.txt | while read -r file; do
      echo "  ${file#${restore_dir}/}"
    done
    return 0
  fi

  # Brewfile 복원
  if [[ -f "${restore_dir}/Brewfile" ]]; then
    cp "${restore_dir}/Brewfile" "${OMS_DOTFILES}/Brewfile"
    oms_ok "Brewfile 복원 완료"
  fi

  # machine toml 복원
  if [[ -f "${restore_dir}/machines/${machine_name}.toml" ]]; then
    oms_ensure_dir "${OMS_DOTFILES}/machines"
    cp "${restore_dir}/machines/${machine_name}.toml" "${OMS_DOTFILES}/machines/${machine_name}.toml"
    oms_ok "machine toml 복원 완료"
  fi

  # 닷파일 복원
  if [[ -d "${restore_dir}/dotfiles" ]]; then
    local restored=0
    find "${restore_dir}/dotfiles" -type f | while read -r file; do
      local rel="${file#${restore_dir}/dotfiles/}"
      local dest="${HOME}/${rel}"
      oms_ensure_dir "$(dirname "$dest")"
      cp "$file" "$dest"
      oms_debug "복원: ~/${rel}"
      restored=$((restored + 1))
    done
    oms_ok "닷파일 복원 완료"
  fi

  oms_ok "백업 복원 완료: ${target}"
}

# ── 백업 정리 ─────────────────────────────────────
# Usage: oms_backup_cleanup [--keep N]
oms_backup_cleanup() {
  local keep=$OMS_BACKUP_KEEP

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keep) keep="$2"; shift ;;
      *) ;;
    esac
    shift
  done

  local machine_name
  machine_name="$(hostname -s 2>/dev/null || echo "unknown")"
  local machine_backup_dir="${OMS_BACKUP_BASE}/${machine_name}"

  if [[ ! -d "$machine_backup_dir" ]]; then
    oms_info "정리할 백업이 없습니다."
    return 0
  fi

  local all_backups
  all_backups=($(ls -1d "${machine_backup_dir}"/*/ 2>/dev/null | sort -r))
  local total=${#all_backups[@]}

  if [[ $total -le $keep ]]; then
    oms_info "백업 ${total}개 보관 중 (최대 ${keep}개). 정리할 필요 없음."
    return 0
  fi

  local to_remove=$((total - keep))
  oms_info "${to_remove}개 오래된 백업을 삭제합니다. (${keep}개 보관)"

  if ! oms_confirm "계속하시겠습니까?"; then
    oms_info "취소됨."
    return 0
  fi

  local removed=0
  for dir in "${all_backups[@]:$keep}"; do
    if [[ "${OMS_DRY_RUN}" == "true" ]]; then
      oms_info "[DRY-RUN] 삭제 예정: $(basename "$dir")"
    else
      rm -rf "$dir"
      oms_debug "삭제: $(basename "$dir")"
      removed=$((removed + 1))
    fi
  done

  oms_ok "${removed}개 백업 삭제 완료."
}

# ── 백업 CLI 라우터 ───────────────────────────────
# Usage: oms backup <list|restore|cleanup>
oms_backup_cmd() {
  local subcmd="${1:-list}"
  shift 2>/dev/null || true

  case "$subcmd" in
    list)     oms_backup_list "$@" ;;
    restore)  oms_backup_restore "$@" ;;
    cleanup)  oms_backup_cleanup "$@" ;;
    *)        oms_error "알 수 없는 backup 명령어: $subcmd"
              echo "사용법: oms backup <list|restore|cleanup>"
              return 1 ;;
  esac
}

# ── .gitignore 헬퍼 ──────────────────────────────
_ensure_backups_gitignored() {
  local gitignore="${OMS_DOTFILES}/.gitignore"
  if [[ -f "$gitignore" ]]; then
    grep -q '.oms-state/backups/' "$gitignore" 2>/dev/null && return 0
  fi
  echo '.oms-state/backups/' >> "$gitignore"
  oms_debug ".gitignore에 backups 디렉토리 추가"
}
