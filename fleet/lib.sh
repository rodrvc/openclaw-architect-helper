# shellcheck shell=bash
# fleet/lib.sh — helpers shared by export.sh / bootstrap.sh / verify.sh.
# Sourced, never executed directly.

FLEET_VERSION=1

# --- output -----------------------------------------------------------------
_c() { if [ -t 1 ]; then printf '\033[%sm%s\033[0m' "$1" "$2"; else printf '%s' "$2"; fi; }
info()  { printf '%s %s\n' "$(_c '36' '::')" "$*"; }
ok()    { printf '%s %s\n' "$(_c '32' 'OK  ')" "$*"; }
warn()  { printf '%s %s\n' "$(_c '33' 'WARN')" "$*" >&2; }
die()   { printf '%s %s\n' "$(_c '31' 'ERR ')" "$*" >&2; exit 1; }

# --- paths ------------------------------------------------------------------
# Fleet files store paths relative to the home dir as "~/..." so an export made
# on one machine applies on another whose home dir has a different name.
tildify()  { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}";; *) printf '%s' "$1";; esac; }
untildify() { case "$1" in "~/"*) printf '%s' "$HOME/${1#\~/}";; *) printf '%s' "$1";; esac; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

# Resolve the config path / state dir the way OpenClaw itself does, so the
# scripts act on a test instance when the env vars point at one.
fleet_config_path() { printf '%s' "${OPENCLAW_CONFIG_PATH:-${OPENCLAW_STATE_DIR:-$HOME/.openclaw}/openclaw.json}"; }
fleet_state_dir()   { printf '%s' "${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"; }

# --- secret scan ------------------------------------------------------------
# Runs over an exported fleet dir. Anything matching is a hard failure: an
# export that leaks a credential must never reach a git remote.
SECRET_PATTERNS=(
  'AIza[0-9A-Za-z_-]{10,}'
  'sk-[A-Za-z0-9]{10,}'
  'ghp_[A-Za-z0-9]{10,}'
  'xox[bp]-[A-Za-z0-9-]{10,}'
  'BEGIN (RSA|OPENSSH) PRIVATE KEY'
  '"(api[_-]?key|token|secret|password|credential)"[[:space:]]*:[[:space:]]*"[^"]{8,}"'
)

scan_secrets() {
  local dir="$1" pat hits found=0
  [ -d "$dir" ] || die "scan_secrets: not a directory: $dir"
  for pat in "${SECRET_PATTERNS[@]}"; do
    # grep exits 1 when there are no matches; that is the good path here.
    if hits=$(grep -rInE "$pat" "$dir" 2>/dev/null); then
      found=1
      warn "secret pattern matched: $pat"
      printf '%s\n' "$hits" | head -20 >&2
    fi
  done
  [ "$found" -eq 0 ] || die "secret scan FAILED on $dir — fix the export before committing"
  ok "secret scan clean ($dir)"
}

# --- timeouts ---------------------------------------------------------------
# macOS ships no coreutils `timeout`. Commands that talk to the Gateway block
# forever when no gateway is listening, so every such call gets a deadline.
# Returns 124 on timeout, like GNU timeout does.
with_timeout() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@"; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"; return $?; fi
  "$@" &
  local pid=$! waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$secs" ]; then
      kill -TERM "$pid" 2>/dev/null; sleep 1; kill -KILL "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1; waited=$((waited+1))
  done
  wait "$pid"
}

# --- json -------------------------------------------------------------------
# node ships with openclaw, so it is the one JSON processor we can rely on.
json_node() { need_cmd node; node "$@"; }
