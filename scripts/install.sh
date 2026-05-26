#!/usr/bin/env bash
# =============================================================================
# OpenSOP self-host installer
# Usage:
#   Interactive: bash scripts/install.sh
#   One-liner:   curl -fsSL https://raw.githubusercontent.com/Chosen9115/opensop/main/scripts/install.sh | bash
#   Flags:       bash scripts/install.sh --mode=local-dev --non-interactive
# =============================================================================
set -euo pipefail

# ─── ASCII_BANNER ─────────────────────────────────────────────────────────────
print_banner() {
  # Detect repo root: if REPO_ROOT is not set, default to the directory
  # containing this script (handles both `bash scripts/install.sh` and `curl|bash`).
  local _root="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd || echo ".")}"
  if [ -f "${_root}/docs/branding/banner-install.txt" ]; then
    cat "${_root}/docs/branding/banner-install.txt"
    echo ""
  else
    # Fallback when running over curl|bash before the repo is cloned
    cat <<'EOF'
  ╔═════════════════════════════════╗
  ║  OpenSOP                        ║
  ║  Processes as APIs              ║
  ╚═════════════════════════════════╝

  [ form ] ──▶ [ decision ] ──▶ [ done ]

EOF
  fi
}
# ─── end ASCII_BANNER ─────────────────────────────────────────────────────────

# ─── Colour helpers ───────────────────────────────────────────────────────────
# Respect NO_COLOR (https://no-color.org/) and non-TTY stdout.
_use_color() {
  [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]
}

_red()   { _use_color && printf '\033[0;31m%s\033[0m\n' "$*" || printf '%s\n' "$*"; }
_green() { _use_color && printf '\033[0;32m%s\033[0m\n' "$*" || printf '%s\n' "$*"; }
_yellow(){ _use_color && printf '\033[0;33m%s\033[0m\n' "$*" || printf '%s\n' "$*"; }
_bold()  { _use_color && printf '\033[1m%s\033[0m\n'    "$*" || printf '%s\n' "$*"; }

_info()  { printf '  [info]  %s\n' "$*"; }
_ok()    { _green "  [ok]    $*"; }
_warn()  { _yellow "  [warn]  $*"; }
_err()   { _red   "  [error] $*" >&2; }
_die()   { _err "$*"; echo "" >&2; echo "  See the README or open an issue: https://github.com/Chosen9115/opensop/issues" >&2; exit 1; }

# ─── Defaults ─────────────────────────────────────────────────────────────────
INSTALL_PATH="./opensop"
OPENSOP_MODE="local-dev"
OPENSOP_DOMAIN=""
OPENSOP_AUTH="passkeys"
OPENSOP_LLM="none"
OPENSOP_ADMIN_EMAIL=""
OPENSOP_PORT="3000"
RESEND_KEY=""
MAILER_FROM=""
ANTHROPIC_KEY=""

NON_INTERACTIVE=false
ACCEPT_DEFAULTS=false

# ─── Argument parsing ─────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --mode=*)            OPENSOP_MODE="${arg#--mode=}" ;;
    --domain=*)          OPENSOP_DOMAIN="${arg#--domain=}" ;;
    --auth=*)            OPENSOP_AUTH="${arg#--auth=}" ;;
    --llm=*)             OPENSOP_LLM="${arg#--llm=}" ;;
    --admin-email=*)     OPENSOP_ADMIN_EMAIL="${arg#--admin-email=}" ;;
    --port=*)            OPENSOP_PORT="${arg#--port=}" ;;
    --resend-key=*)      RESEND_KEY="${arg#--resend-key=}" ;;
    --mailer-from=*)     MAILER_FROM="${arg#--mailer-from=}" ;;
    --anthropic-key=*)   ANTHROPIC_KEY="${arg#--anthropic-key=}" ;;
    --install-path=*)    INSTALL_PATH="${arg#--install-path=}" ;;
    --non-interactive)   NON_INTERACTIVE=true ;;
    --yes|-y)            ACCEPT_DEFAULTS=true ;;
    --help|-h)
      cat <<'HELP'
OpenSOP Installer

Usage: bash scripts/install.sh [options]

Options:
  --mode=MODE           Install mode: local-dev (default) | self-host-local | self-host-public
  --domain=DOMAIN       Public domain (required when mode=self-host-public)
  --auth=AUTH           Auth type: passkeys (default) | passkeys+magic-links
  --llm=LLM             LLM provider: none (default) | anthropic
  --admin-email=EMAIL   First admin email address
  --port=PORT           Host port to bind (default: 3000)
  --resend-key=KEY      Resend API key (required when auth=passkeys+magic-links)
  --mailer-from=ADDR    Mailer from address (required when auth=passkeys+magic-links)
  --anthropic-key=KEY   Anthropic API key (required when llm=anthropic)
  --install-path=PATH   Clone destination when not inside a repo (default: ./opensop)
  --non-interactive     Fail instead of prompting for any missing values
  --yes, -y             Accept all defaults without prompting
  --help                Show this help
HELP
      exit 0
      ;;
    *) _warn "Unknown argument: $arg (ignored)" ;;
  esac
done

# ─── Prereq checks ────────────────────────────────────────────────────────────
check_prereqs() {
  _bold "Checking prerequisites..."

  if ! command -v docker &>/dev/null; then
    _die "Docker is not installed. Install it from https://docs.docker.com/get-docker/ and try again."
  fi
  _ok "docker found: $(docker --version 2>&1 | head -1)"

  if ! docker compose version &>/dev/null 2>&1; then
    _die "Docker Compose v2 is required (docker compose, not docker-compose). Upgrade Docker Desktop or install the compose plugin."
  fi
  _ok "docker compose found: $(docker compose version 2>&1 | head -1)"

  if ! command -v curl &>/dev/null; then
    _die "curl is not installed. Install it via your package manager (brew install curl / apt install curl)."
  fi
  _ok "curl found"

  if ! command -v openssl &>/dev/null; then
    _die "openssl is not installed. Install it via your package manager and try again."
  fi
  _ok "openssl found"
}

# ─── Detect environment ───────────────────────────────────────────────────────
INSIDE_CLONE=false
detect_environment() {
  if [[ -f "docker-compose.yml" ]]; then
    INSIDE_CLONE=true
    _info "Detected existing OpenSOP directory (docker-compose.yml found) — skipping clone."
  fi
}

# ─── Already-installed guard ──────────────────────────────────────────────────
check_not_already_installed() {
  if [[ -f ".env" ]]; then
    _yellow ""
    _yellow "  OpenSOP is already configured here (.env exists)."
    _yellow ""
    _yellow "  To start:         docker compose up -d"
    _yellow "  To reconfigure:   rm .env && bash scripts/install.sh"
    _yellow ""
    exit 0
  fi
}

# ─── Clone repo ───────────────────────────────────────────────────────────────
clone_repo() {
  if $INSIDE_CLONE; then
    return
  fi

  if ! command -v git &>/dev/null; then
    _die "git is required to clone the repo. Install git and try again, or cd into an existing clone before running."
  fi

  _bold "Cloning OpenSOP to $INSTALL_PATH ..."
  if [[ -d "$INSTALL_PATH" ]]; then
    _die "Directory $INSTALL_PATH already exists. Remove it or choose a different --install-path."
  fi

  git clone --depth=1 https://github.com/Chosen9115/opensop.git "$INSTALL_PATH" \
    || _die "git clone failed. Check your network connection and try again."

  cd "$INSTALL_PATH" || _die "Cannot cd into $INSTALL_PATH"
  _ok "Cloned to $INSTALL_PATH"
}

# ─── Prompts ──────────────────────────────────────────────────────────────────
_prompt() {
  local var_name="$1"
  local prompt_text="$2"
  local default_val="${3:-}"
  local current_val

  # Resolve the variable by name using indirect expansion
  current_val="${!var_name:-}"

  # If already set (via flag) skip prompting
  if [[ -n "$current_val" ]]; then
    return
  fi

  if $NON_INTERACTIVE; then
    [[ -z "$default_val" ]] && _die "Required value '$var_name' is missing and --non-interactive was set."
    printf -v "$var_name" '%s' "$default_val"
    return
  fi

  if $ACCEPT_DEFAULTS && [[ -n "$default_val" ]]; then
    printf -v "$var_name" '%s' "$default_val"
    return
  fi

  local display_prompt
  if [[ -n "$default_val" ]]; then
    display_prompt="  $prompt_text [$default_val]: "
  else
    display_prompt="  $prompt_text: "
  fi

  local input=""
  read -r -p "$display_prompt" input </dev/tty
  if [[ -z "$input" && -n "$default_val" ]]; then
    input="$default_val"
  fi
  printf -v "$var_name" '%s' "$input"
}

_prompt_secret() {
  local var_name="$1"
  local prompt_text="$2"
  local current_val

  current_val="${!var_name:-}"
  if [[ -n "$current_val" ]]; then
    return
  fi

  if $NON_INTERACTIVE; then
    _die "Required secret '$var_name' is missing and --non-interactive was set."
  fi

  local input=""
  read -r -s -p "  $prompt_text: " input </dev/tty
  echo "" >/dev/tty
  printf -v "$var_name" '%s' "$input"
}

run_prompts() {
  _bold ""
  _bold "Configure your OpenSOP install:"
  _bold ""

  _prompt "OPENSOP_MODE" \
    "Install mode (local-dev / self-host-local / self-host-public)" \
    "local-dev"

  case "$OPENSOP_MODE" in
    local-dev|self-host-local|self-host-public) ;;
    *) _die "Invalid mode '$OPENSOP_MODE'. Must be: local-dev, self-host-local, or self-host-public." ;;
  esac

  if [[ "$OPENSOP_MODE" == "self-host-public" ]]; then
    _prompt "OPENSOP_DOMAIN" "Public domain (e.g. opensop.yourcompany.com)" ""
    [[ -z "$OPENSOP_DOMAIN" ]] && _die "Domain is required for self-host-public mode."
  fi

  _prompt "OPENSOP_AUTH" \
    "Auth type (passkeys / passkeys+magic-links)" \
    "passkeys"

  case "$OPENSOP_AUTH" in
    passkeys|passkeys+magic-links) ;;
    *) _die "Invalid auth '$OPENSOP_AUTH'. Must be: passkeys or passkeys+magic-links." ;;
  esac

  if [[ "$OPENSOP_AUTH" == "passkeys+magic-links" ]]; then
    _prompt_secret "RESEND_KEY" "Resend API key (from https://resend.com)"
    [[ -z "$RESEND_KEY" ]] && _die "Resend API key is required for magic-link auth."
    _prompt "MAILER_FROM" "Mailer from address (e.g. OpenSOP <noreply@yourcompany.com>)" ""
    [[ -z "$MAILER_FROM" ]] && _die "Mailer from address is required for magic-link auth."
  fi

  _prompt "OPENSOP_LLM" \
    "LLM provider (none / anthropic)" \
    "none"

  case "$OPENSOP_LLM" in
    none|anthropic) ;;
    *) _die "Invalid LLM '$OPENSOP_LLM'. Must be: none or anthropic." ;;
  esac

  if [[ "$OPENSOP_LLM" == "anthropic" ]]; then
    _prompt_secret "ANTHROPIC_KEY" "Anthropic API key (from https://console.anthropic.com)"
    [[ -z "$ANTHROPIC_KEY" ]] && _die "Anthropic API key is required when llm=anthropic."
  fi

  _prompt "OPENSOP_ADMIN_EMAIL" "First admin email address" ""
  [[ -z "$OPENSOP_ADMIN_EMAIL" ]] && _die "Admin email is required."

  _prompt "OPENSOP_PORT" "Host port to bind" "3000"
}

# ─── Generate secrets ─────────────────────────────────────────────────────────
generate_secrets() {
  _bold "Generating secrets..."

  RAILS_MASTER_KEY=$(openssl rand -hex 32) \
    || _die "Failed to generate RAILS_MASTER_KEY. Is openssl working correctly?"

  SECRET_KEY_BASE=$(openssl rand -hex 64) \
    || _die "Failed to generate SECRET_KEY_BASE."

  OPENSOP_API_TOKEN=$(openssl rand -hex 32) \
    || _die "Failed to generate OPENSOP_API_TOKEN."

  # Base64 then strip special chars and truncate to 24 chars
  POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d '=+/' | head -c 24) \
    || _die "Failed to generate POSTGRES_PASSWORD."

  _ok "Secrets generated"
}

# ─── Write .env ───────────────────────────────────────────────────────────────
write_env() {
  _bold "Writing .env ..."

  # Derive mode-specific values
  local rp_id="localhost"
  local origin="http://localhost:${OPENSOP_PORT}"
  local allowed_hosts="localhost,127.0.0.1"
  local base_url="http://localhost:${OPENSOP_PORT}"
  local mailer_mode="log"
  local rails_env="production"
  # The Solid Queue supervisor runs inside Puma for the production modes
  # (single-server deploys). local-dev runs RAILS_ENV=development, which uses
  # the async queue adapter and never migrates the Solid Queue tables — so
  # starting the supervisor there crashes Puma. Keep it off for local-dev.
  local solid_queue_in_puma="true"

  if [[ "$OPENSOP_MODE" == "self-host-public" && -n "$OPENSOP_DOMAIN" ]]; then
    rp_id="$OPENSOP_DOMAIN"
    origin="https://${OPENSOP_DOMAIN}"
    allowed_hosts="${OPENSOP_DOMAIN}"
    base_url="https://${OPENSOP_DOMAIN}"
  fi

  if [[ "$OPENSOP_AUTH" == "passkeys+magic-links" ]]; then
    mailer_mode="send"
  fi

  if [[ "$OPENSOP_MODE" == "local-dev" ]]; then
    rails_env="development"
    solid_queue_in_puma="false"
  fi

  cat > .env <<EOF
# OpenSOP — generated by scripts/install.sh
# Do NOT commit this file. It is listed in .gitignore.
# To regenerate: rm .env && bash scripts/install.sh

# ── Rails ──────────────────────────────────────────────────────────────────
RAILS_ENV=${rails_env}
RAILS_MASTER_KEY=${RAILS_MASTER_KEY}
SECRET_KEY_BASE=${SECRET_KEY_BASE}
RAILS_LOG_LEVEL=info
RAILS_ALLOWED_HOSTS=${allowed_hosts}
SOLID_QUEUE_IN_PUMA=${solid_queue_in_puma}

# ── Database ───────────────────────────────────────────────────────────────
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# ── OpenSOP core ───────────────────────────────────────────────────────────
OPENSOP_PORT=${OPENSOP_PORT}
OPENSOP_API_TOKEN=${OPENSOP_API_TOKEN}
OPENSOP_BASE_URL=${base_url}
OPENSOP_BOOTSTRAP_EMAIL=${OPENSOP_ADMIN_EMAIL}

# ── WebAuthn / passkeys ────────────────────────────────────────────────────
OPENSOP_RP_ID=${rp_id}
OPENSOP_ORIGIN=${origin}
OPENSOP_RP_NAME=OpenSOP

# ── Email / magic links ────────────────────────────────────────────────────
RESEND_API_KEY=${RESEND_KEY}
OPENSOP_MAILER_FROM=${MAILER_FROM}
OPENSOP_MAILER_MODE=${mailer_mode}

# ── LLM ───────────────────────────────────────────────────────────────────
ANTHROPIC_API_KEY=${ANTHROPIC_KEY}
EOF

  chmod 600 .env
  _ok ".env written (mode 600)"
}

# ─── Handle credentials.yml.enc gotcha ────────────────────────────────────────
handle_credentials() {
  # The committed credentials.yml.enc was encrypted with the original author's
  # master key. A fresh installer cannot decrypt it. Since Rails reads
  # SECRET_KEY_BASE from the environment directly (set above), the encrypted
  # file is not needed. Delete it so Rails doesn't attempt to decrypt it.
  if [[ -f "config/credentials.yml.enc" ]]; then
    rm -f config/credentials.yml.enc
    _ok "Removed config/credentials.yml.enc (SECRET_KEY_BASE served from env)"
  fi
}

# ─── Start services ───────────────────────────────────────────────────────────
start_services() {
  _bold "Starting OpenSOP with Docker Compose..."
  docker compose up -d \
    || _die "docker compose up -d failed. Check 'docker compose logs' for details."
  _ok "Containers started"
}

# ─── Wait for healthcheck ─────────────────────────────────────────────────────
wait_for_health() {
  local url="http://localhost:${OPENSOP_PORT}/up"
  local max_wait=120
  local waited=0
  local interval=3

  _bold "Waiting for /up healthcheck (up to ${max_wait}s)..."
  printf "  "

  while true; do
    if curl -fsS --max-time 2 "$url" &>/dev/null; then
      echo ""
      _ok "Health check passed"
      return 0
    fi

    if [[ $waited -ge $max_wait ]]; then
      echo ""
      _err "Health check timed out after ${max_wait}s."
      _err "The app may still be starting. Check: docker compose logs app"
      _err "Common causes: port ${OPENSOP_PORT} already in use; Docker image build failed."
      exit 1
    fi

    printf "."
    sleep "$interval"
    waited=$((waited + interval))
  done
}

# ─── Smoke test ───────────────────────────────────────────────────────────────
smoke_test() {
  local url="http://localhost:${OPENSOP_PORT}/sop/"
  _bold "Running smoke test (GET /sop/) ..."

  local http_code
  http_code=$(curl -fsS --max-time 5 \
    -H "X-SOP-Token: ${OPENSOP_API_TOKEN}" \
    -o /dev/null \
    -w "%{http_code}" \
    "$url" 2>/dev/null) || true

  if [[ "$http_code" == "200" ]]; then
    _ok "Smoke test passed (HTTP 200)"
  else
    _warn "Smoke test returned HTTP $http_code — the app is up but the API may need a moment."
    _warn "Try: curl -H 'X-SOP-Token: ${OPENSOP_API_TOKEN}' ${url}"
  fi
}

# ─── Print success summary ────────────────────────────────────────────────────
print_success() {
  local base_url="http://localhost:${OPENSOP_PORT}"
  if [[ "$OPENSOP_MODE" == "self-host-public" && -n "$OPENSOP_DOMAIN" ]]; then
    base_url="https://${OPENSOP_DOMAIN}"
  fi

  _bold ""

  # Print the running banner, substituting the real URL for PLACEHOLDER_URL
  local _root="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd || echo ".")}"
  if [ -f "${_root}/docs/branding/banner-running.txt" ]; then
    sed "s|PLACEHOLDER_URL|${base_url}|g" "${_root}/docs/branding/banner-running.txt"
  else
    _green "  OpenSOP is running!"
    echo   ""
    echo   "  → Dashboard:     ${base_url}"
    echo   "  → API endpoint:  ${base_url}/sop/"
    echo   ""
  fi

  echo   "  Admin email:   ${OPENSOP_ADMIN_EMAIL}"
  echo   ""
  _bold  "  API Token (saved in .env — keep it secret):"
  echo   "  ${OPENSOP_API_TOKEN}"
  echo   ""
  echo   "  Quick start:"
  echo   "    View logs:     docker compose logs -f app"
  echo   "    Stop:          docker compose down"
  echo   "    Restart:       docker compose restart app"
  echo   "    Shell:         docker compose exec app /bin/bash"
  echo   ""
  if [[ "$OPENSOP_MODE" == "local-dev" ]]; then
    _yellow "  Note: Running in local-dev mode. Not suitable for production."
    _yellow "  For public hosting rerun with --mode=self-host-public --domain=..."
    echo   ""
  fi
  _ok "Install complete."
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  print_banner
  check_prereqs
  detect_environment
  check_not_already_installed
  clone_repo
  run_prompts
  generate_secrets
  write_env
  handle_credentials
  start_services
  wait_for_health
  smoke_test
  print_success
}

main "$@"
