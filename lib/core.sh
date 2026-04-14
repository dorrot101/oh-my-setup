#!/usr/bin/env bash
# oh-my-setup — 공통 유틸리티

# ── 색상 정의 ──────────────────────────────────────
if [[ "${OMS_NO_COLOR:-false}" != "true" ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  DIM='\033[2m'
  NC='\033[0m'  # No Color
else
  RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' NC=''
fi

# ── 로깅 ──────────────────────────────────────────
OMS_LOG_LEVEL="${OMS_LOG_LEVEL:-info}"

_log_level_num() {
  case "$1" in
    debug) echo 0 ;; info)  echo 1 ;;
    warn)  echo 2 ;; error) echo 3 ;;
    *)     echo 1 ;;
  esac
}

_should_log() {
  [[ $(_log_level_num "$1") -ge $(_log_level_num "$OMS_LOG_LEVEL") ]]
}

oms_debug() { _should_log debug && echo -e "${DIM}[DEBUG]${NC} $*" >&2; }
oms_info()  { _should_log info  && echo -e "${BLUE}[INFO]${NC}  $*" >&2; }
oms_ok()    { _should_log info  && echo -e "${GREEN}[OK]${NC}    $*" >&2; }
oms_skip()  { _should_log info  && echo -e "${DIM}[SKIP]${NC}  $*" >&2; }
oms_warn()  { _should_log warn  && echo -e "${YELLOW}[WARN]${NC}  $*" >&2; }
oms_error() { _should_log error && echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── 사용자 확인 ────────────────────────────────────
oms_confirm() {
  local message="${1:-계속하시겠습니까?}"
  if [[ "${OMS_YES:-false}" == "true" ]]; then
    return 0
  fi
  echo -ne "${YELLOW}? ${NC}${message} ${DIM}[Y/n]${NC} "
  read -r answer
  [[ -z "$answer" || "$answer" =~ ^[Yy] ]]
}

# ── 파일/경로 유틸 ─────────────────────────────────
oms_expand_path() {
  echo "${1/#\~/$HOME}"
}

oms_ensure_dir() {
  local dir="$1"
  [[ -d "$dir" ]] || mkdir -p "$dir"
}

# ── 에포크 기반 시간 유틸 ──────────────────────────
oms_epoch_days() {
  echo $(( $(date +%s) / 86400 ))
}

# ── 글로벌 옵션 파싱 ──────────────────────────────
OMS_YES="false"
OMS_DRY_RUN="false"
OMS_VERBOSE="false"

oms_parse_global_opts() {
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes)      OMS_YES="true" ;;
      --dry-run)     OMS_DRY_RUN="true" ;;
      -v|--verbose)  OMS_VERBOSE="true"; OMS_LOG_LEVEL="debug" ;;
      -q|--quiet)    OMS_LOG_LEVEL="error" ;;
      --no-color)    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' NC='' ;;
      *)             args+=("$1") ;;
    esac
    shift
  done
  echo "${args[@]:-}"
}
