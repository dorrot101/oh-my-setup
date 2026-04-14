#!/usr/bin/env bash
# oh-my-setup — TOML 설정 파서
# 경량 TOML 파서: 섹션, 키=값, 배열(단순) 지원
# 복잡한 TOML은 dasel이 설치되어 있으면 활용

# ── TOML 값 읽기 ──────────────────────────────────
# Usage: oms_config_get "setup.toml" "update.check_interval_days"
# 섹션.키 형태의 dot notation 지원
oms_config_get() {
  local file="$1"
  local key="$2"

  if [[ ! -f "$file" ]]; then
    oms_error "설정 파일을 찾을 수 없습니다: $file"
    return 1
  fi

  # dasel 사용 가능하면 우선 사용
  if command -v dasel >/dev/null 2>&1; then
    dasel -f "$file" -r toml "$key" 2>/dev/null
    return $?
  fi

  # 폴백: 순수 Bash 파서
  _toml_parse_value "$file" "$key"
}

# ── 순수 Bash TOML 파서 ───────────────────────────
_toml_parse_value() {
  local file="$1"
  local dotkey="$2"
  local section="" target_section="" target_key=""

  # "update.check_interval_days" → section="update", key="check_interval_days"
  if [[ "$dotkey" == *.* ]]; then
    target_section="${dotkey%.*}"
    target_key="${dotkey##*.}"
  else
    target_section=""
    target_key="$dotkey"
  fi

  local in_target_section=false
  [[ -z "$target_section" ]] && in_target_section=true

  while IFS= read -r line; do
    # 빈 줄, 주석 건너뛰기
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    # 섹션 헤더 감지: [section] 또는 [section.subsection]
    if [[ "$line" =~ ^\[([a-zA-Z0-9_.]+)\] ]]; then
      section="${BASH_REMATCH[1]}"
      if [[ "$section" == "$target_section" ]]; then
        in_target_section=true
      else
        in_target_section=false
      fi
      continue
    fi

    # 키 = 값 파싱
    if $in_target_section && [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*) ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"

      if [[ "$key" == "$target_key" ]]; then
        # 값 정리: 따옴표 제거, 불리언/숫자는 그대로
        value="${value%%#*}"          # 인라인 주석 제거
        value="${value%"${value##*[![:space:]]}"}"  # 트레일링 공백 제거
        value="${value#\"}"           # 앞 따옴표 제거
        value="${value%\"}"           # 뒤 따옴표 제거
        echo "$value"
        return 0
      fi
    fi
  done < "$file"

  return 1  # 키를 찾지 못함
}

# ── TOML 배열 읽기 ─────────────────────────────────
# Usage: oms_config_get_array "setup.toml" "modules.enabled"
# 한 줄씩 출력
oms_config_get_array() {
  local file="$1"
  local key="$2"
  local raw

  if command -v dasel >/dev/null 2>&1; then
    dasel -f "$file" -r toml -m "${key}.[*]" 2>/dev/null
    return $?
  fi

  # 폴백: 간단한 배열 파싱 (한 줄 또는 여러 줄)
  raw="$(oms_config_get "$file" "$key" 2>/dev/null || true)"
  if [[ -n "$raw" ]]; then
    # "[" ... "]" 형태에서 값 추출
    echo "$raw" | tr -d '[]' | tr ',' '\n' | while read -r item; do
      item="${item#"${item%%[![:space:]]*}"}"  # trim leading
      item="${item%"${item##*[![:space:]]}"}"  # trim trailing
      item="${item#\"}"
      item="${item%\"}"
      [[ -n "$item" ]] && echo "$item"
    done
  fi
}

# ── 설정 파일 경로 헬퍼 ────────────────────────────
oms_setup_toml() {
  echo "${OMS_DOTFILES}/setup.toml"
}

oms_machine_toml() {
  local machine_name
  machine_name="$(hostname -s 2>/dev/null || echo "unknown")"
  local machine_file="${OMS_DOTFILES}/machines/${machine_name}.toml"
  [[ -f "$machine_file" ]] && echo "$machine_file" || echo ""
}
