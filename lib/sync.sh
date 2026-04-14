#!/usr/bin/env bash
# oh-my-setup — Git 동기화 & 충돌 처리

# ── 메인 동기화 명령 ──────────────────────────────
# Usage: oms_sync [options]
oms_sync() {
  local mode="both"  # both | pull | push
  local force=""     # "" | remote | local

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pull)          mode="pull" ;;
      --push)          mode="push" ;;
      --force-remote)  force="remote" ;;
      --force-local)   force="local" ;;
      --dry-run)       OMS_DRY_RUN="true" ;;
      -y|--yes)        OMS_YES="true" ;;
      -v|--verbose)    OMS_LOG_LEVEL="debug" ;;
      *)               oms_error "알 수 없는 옵션: $1"; return 1 ;;
    esac
    shift
  done

  local machine_name
  machine_name="$(hostname -s 2>/dev/null || echo "unknown")"

  echo ""
  echo -e "${BOLD}🔄 oh-my-setup 동기화${NC}"
  echo -e "${DIM}기기: ${machine_name}${NC}"
  echo ""

  # dotfiles 저장소 확인
  if [[ ! -d "$OMS_DOTFILES/.git" ]]; then
    oms_error "dotfiles 저장소를 찾을 수 없습니다: $OMS_DOTFILES"
    return 1
  fi

  cd "$OMS_DOTFILES" || return 1

  # 원격 설정 확인
  local remote_url
  remote_url="$(git remote get-url origin 2>/dev/null || true)"
  if [[ -z "$remote_url" ]]; then
    oms_error "원격 저장소가 설정되어 있지 않습니다."
    oms_info "'git remote add origin <url>'로 원격 저장소를 추가하세요."
    return 1
  fi

  # Phase 1: 백업 생성
  if [[ "${OMS_DRY_RUN}" != "true" ]]; then
    oms_info "동기화 전 백업 생성"
    oms_backup_create "pre-sync" > /dev/null
  fi

  # 강제 모드 처리
  if [[ "$force" == "remote" ]]; then
    _sync_force_remote
    return $?
  elif [[ "$force" == "local" ]]; then
    _sync_force_local
    return $?
  fi

  # Phase 2: 로컬 변경사항 커밋
  if [[ "$mode" != "pull" ]]; then
    _sync_commit_local
  fi

  # Phase 3: 원격 변경 가져오기
  if [[ "$mode" != "push" ]]; then
    _sync_pull
    local pull_result=$?
    if [[ $pull_result -ne 0 ]]; then
      return $pull_result
    fi
  fi

  # Phase 4: 푸시
  if [[ "$mode" != "pull" ]]; then
    _sync_push
  fi

  # 마지막 동기화 시간 기록
  if [[ "${OMS_DRY_RUN}" != "true" ]]; then
    oms_ensure_dir "${OMS_DOTFILES}/.oms-state"
    date +%s > "${OMS_DOTFILES}/.oms-state/last-sync"
  fi

  echo ""
  oms_ok "동기화 완료!"
}

# ── 로컬 변경사항 커밋 ────────────────────────────
_sync_commit_local() {
  cd "$OMS_DOTFILES" || return 1

  local changes
  changes="$(git status --porcelain 2>/dev/null)"

  if [[ -z "$changes" ]]; then
    oms_skip "로컬 변경사항 없음"
    return 0
  fi

  local machine_name
  machine_name="$(hostname -s 2>/dev/null || echo "unknown")"
  local date_str
  date_str="$(date '+%Y-%m-%d %H:%M')"

  echo -e "${DIM}로컬 변경 파일:${NC}"
  git status --short | head -15 | sed 's/^/  /'
  local total
  total="$(echo "$changes" | wc -l | tr -d ' ')"
  [[ $total -gt 15 ]] && echo "  ... 외 $((total - 15))개"

  # auto_commit 설정 확인
  local auto_commit="true"
  local setup_toml
  setup_toml="$(oms_setup_toml)"
  if [[ -f "$setup_toml" ]]; then
    auto_commit="$(oms_config_get "$setup_toml" "git.auto_commit" 2>/dev/null || echo "true")"
  fi

  if [[ "$auto_commit" != "true" ]]; then
    if ! oms_confirm "로컬 변경사항을 커밋하시겠습니까?"; then
      oms_warn "커밋하지 않은 변경사항이 있으면 동기화 충돌이 발생할 수 있습니다."
      return 0
    fi
  fi

  if [[ "${OMS_DRY_RUN}" == "true" ]]; then
    oms_info "[DRY-RUN] 로컬 변경사항 커밋 예정"
    return 0
  fi

  git add -A
  git commit -m "[oms] sync from ${machine_name}: ${date_str}" --quiet
  oms_ok "로컬 변경사항 커밋 완료"
}

# ── Pull (원격 → 로컬) ───────────────────────────
_sync_pull() {
  cd "$OMS_DOTFILES" || return 1

  oms_info "원격 저장소 확인 중..."
  git fetch origin --quiet 2>/dev/null

  if [[ $? -ne 0 ]]; then
    oms_error "원격 저장소에 연결할 수 없습니다."
    return 1
  fi

  # 현재 브랜치 확인
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")"

  # 원격과 로컬 차이 확인
  local behind
  behind="$(git rev-list --count "HEAD..origin/${branch}" 2>/dev/null || echo "0")"

  if [[ "$behind" == "0" ]]; then
    oms_skip "원격에 새로운 변경사항 없음"
    return 0
  fi

  oms_info "원격에 ${behind}개의 새 커밋이 있습니다."

  # 변경 요약 출력
  echo -e "\n${DIM}원격 변경 내용:${NC}"
  git log --oneline "HEAD..origin/${branch}" | head -10 | sed 's/^/  /'
  echo ""

  # 변경된 파일 목록
  local changed_files
  changed_files="$(git diff --name-only "HEAD..origin/${branch}" 2>/dev/null)"

  if [[ -n "$changed_files" ]]; then
    echo -e "${DIM}변경된 파일:${NC}"
    echo "$changed_files" | head -10 | sed 's/^/  /'
    echo ""

    # 새 brew 패키지 알림
    if echo "$changed_files" | grep -q "Brewfile"; then
      local new_brews
      new_brews="$(git diff "HEAD..origin/${branch}" -- Brewfile 2>/dev/null | grep '^+' | grep -v '^+++' | head -5)"
      if [[ -n "$new_brews" ]]; then
        echo -e "  ${GREEN}새 Brew 패키지:${NC}"
        echo "$new_brews" | sed 's/^+/    + /'
        echo ""
      fi
    fi
  fi

  if [[ "${OMS_DRY_RUN}" == "true" ]]; then
    oms_info "[DRY-RUN] git pull 실행 예정"
    return 0
  fi

  # Pull 시도
  local pull_output
  pull_output="$(git pull origin "$branch" --no-rebase 2>&1)"
  local pull_status=$?

  if [[ $pull_status -ne 0 ]]; then
    # 충돌 발생
    _handle_merge_conflict
    return 1
  fi

  oms_ok "원격 변경사항 적용 완료"
  return 0
}

# ── Push (로컬 → 원격) ───────────────────────────
_sync_push() {
  cd "$OMS_DOTFILES" || return 1

  local branch
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")"

  # 푸시할 커밋 확인
  local ahead
  ahead="$(git rev-list --count "origin/${branch}..HEAD" 2>/dev/null || echo "0")"

  if [[ "$ahead" == "0" ]]; then
    oms_skip "푸시할 변경사항 없음"
    return 0
  fi

  # auto_push 설정 확인
  local auto_push="true"
  local setup_toml
  setup_toml="$(oms_setup_toml)"
  if [[ -f "$setup_toml" ]]; then
    auto_push="$(oms_config_get "$setup_toml" "git.auto_push" 2>/dev/null || echo "true")"
  fi

  if [[ "${OMS_DRY_RUN}" == "true" ]]; then
    oms_info "[DRY-RUN] ${ahead}개 커밋 푸시 예정"
    return 0
  fi

  if [[ "$auto_push" != "true" ]]; then
    if ! oms_confirm "${ahead}개 커밋을 푸시하시겠습니까?"; then
      oms_info "푸시 건너뜀. 나중에 'git push'를 실행하세요."
      return 0
    fi
  fi

  git push origin "$branch" --quiet 2>/dev/null
  if [[ $? -eq 0 ]]; then
    oms_ok "${ahead}개 커밋 푸시 완료"
  else
    oms_warn "푸시 실패. 네트워크를 확인하고 'git push'를 수동 실행하세요."
  fi
}

# ── 충돌 처리 ─────────────────────────────────────
_handle_merge_conflict() {
  oms_error "병합 충돌이 발생했습니다!"
  echo ""

  # 충돌 파일 목록
  local conflicted
  conflicted="$(git diff --name-only --diff-filter=U 2>/dev/null)"

  if [[ -n "$conflicted" ]]; then
    echo -e "${RED}충돌 파일:${NC}"
    echo "$conflicted" | sed 's/^/  ❌ /'
    echo ""
  fi

  # 병합 중단
  git merge --abort 2>/dev/null

  echo -e "${BOLD}해결 방법:${NC}"
  echo ""
  echo -e "  ${CYAN}1)${NC} 수동 해결"
  echo "     cd $OMS_DOTFILES && git pull"
  echo "     (충돌 파일 수정 후 git add & commit)"
  echo ""
  echo -e "  ${CYAN}2)${NC} 원격 기준 덮어쓰기 (로컬 변경 버림)"
  echo "     oms sync --force-remote"
  echo ""
  echo -e "  ${CYAN}3)${NC} 로컬 기준 강제 푸시 (원격 변경 버림)"
  echo "     oms sync --force-local"
  echo ""
  echo -e "  ${CYAN}4)${NC} 백업에서 복원"
  echo "     oms backup list"
  echo "     oms backup restore latest"
  echo ""
}

# ── 강제 원격 덮어쓰기 ───────────────────────────
_sync_force_remote() {
  cd "$OMS_DOTFILES" || return 1

  local branch
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")"

  oms_warn "원격 기준으로 로컬을 덮어씁니다!"
  oms_warn "로컬 변경사항은 백업에 저장됩니다."

  if [[ "${OMS_DRY_RUN}" == "true" ]]; then
    oms_info "[DRY-RUN] git reset --hard origin/${branch} 실행 예정"
    return 0
  fi

  if ! oms_confirm "정말 원격 기준으로 덮어쓰시겠습니까? (로컬 변경 소실)"; then
    oms_info "취소됨."
    return 0
  fi

  # 백업은 이미 Phase 1에서 생성됨
  git fetch origin --quiet 2>/dev/null
  git reset --hard "origin/${branch}"

  oms_ok "원격 기준으로 로컬을 덮어썼습니다."
  oms_info "이전 상태는 백업에서 복원할 수 있습니다: oms backup list"
}

# ── 강제 로컬 푸시 ────────────────────────────────
_sync_force_local() {
  cd "$OMS_DOTFILES" || return 1

  local branch
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")"

  oms_warn "로컬 기준으로 원격을 덮어씁니다!"
  oms_warn "다른 기기의 변경사항이 소실될 수 있습니다."

  if [[ "${OMS_DRY_RUN}" == "true" ]]; then
    oms_info "[DRY-RUN] git push --force origin/${branch} 실행 예정"
    return 0
  fi

  if ! oms_confirm "정말 강제 푸시하시겠습니까? (원격 변경 소실)"; then
    oms_info "취소됨."
    return 0
  fi

  git push --force origin "$branch" 2>/dev/null
  if [[ $? -eq 0 ]]; then
    oms_ok "강제 푸시 완료"
  else
    oms_error "강제 푸시 실패"
    return 1
  fi
}
