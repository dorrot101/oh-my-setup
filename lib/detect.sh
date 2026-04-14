#!/usr/bin/env bash
# oh-my-setup — 소프트웨어 감지 엔진

# 단일 소프트웨어 설치 여부 확인
# Usage: oms_detect "git"
# Returns: 0 (installed), 1 (not installed)
oms_detect() {
  local name="$1"

  # 1. PATH에서 바이너리 확인
  if command -v "$name" >/dev/null 2>&1; then
    return 0
  fi

  # 2. Homebrew formula 확인
  if command -v brew >/dev/null 2>&1; then
    if brew list --formula 2>/dev/null | grep -q "^${name}$"; then
      return 0
    fi
    # 3. Homebrew cask 확인
    if brew list --cask 2>/dev/null | grep -q "^${name}$"; then
      return 0
    fi
  fi

  # 4. /Applications 확인 (대소문자 무관)
  local app_name
  app_name="$(echo "$name" | sed 's/\b\(.\)/\u\1/g')"  # capitalize
  if [[ -d "/Applications/${app_name}.app" ]] || \
     [[ -d "$HOME/Applications/${app_name}.app" ]]; then
    return 0
  fi

  return 1
}

# 상세 정보 반환
# Usage: oms_detect_info "git"
# Output: "installed|/usr/local/bin/git|2.43.0|binary"
oms_detect_info() {
  local name="$1"
  local path version source

  # PATH 바이너리
  if path="$(command -v "$name" 2>/dev/null)"; then
    version="$("$name" --version 2>/dev/null | head -1 || echo "unknown")"
    echo "installed|${path}|${version}|binary"
    return 0
  fi

  # Homebrew
  if command -v brew >/dev/null 2>&1; then
    if brew list --formula 2>/dev/null | grep -q "^${name}$"; then
      path="$(brew --prefix)/opt/${name}"
      version="$(brew info --json=v2 --formula "$name" 2>/dev/null | \
                 grep -o '"installed":\[{"version":"[^"]*"' | \
                 head -1 | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || echo "unknown")"
      echo "installed|${path}|${version}|brew-formula"
      return 0
    fi
    if brew list --cask 2>/dev/null | grep -q "^${name}$"; then
      version="$(brew info --json=v2 --cask "$name" 2>/dev/null | \
                 grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")"
      echo "installed|/Applications|${version}|brew-cask"
      return 0
    fi
  fi

  echo "not-installed|||"
  return 1
}

# 미설치 항목만 필터링
# Usage: oms_detect_missing "git" "node" "docker"
# Output: 미설치 항목을 한 줄씩 출력
oms_detect_missing() {
  local name
  for name in "$@"; do
    if ! oms_detect "$name"; then
      echo "$name"
    fi
  done
}

# 설치 상태를 예쁘게 출력
oms_detect_print_status() {
  local name="$1"
  if oms_detect "$name"; then
    oms_ok "$name — 설치됨"
  else
    oms_warn "$name — 미설치"
  fi
}
