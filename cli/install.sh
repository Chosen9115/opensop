#!/usr/bin/env bash
#
# install.sh — curl-pipe installer for the OpenSOP CLI
#
# Usage (latest release):
#   curl -fsSL https://raw.githubusercontent.com/Chosen9115/opensop/main/cli/install.sh | bash
#
# Usage (pinned version):
#   curl -fsSL https://raw.githubusercontent.com/Chosen9115/opensop/main/cli/install.sh | bash -s -- --version 0.8.1
#
# Usage (system-wide — writes to /usr/local/bin, may need sudo):
#   curl -fsSL ... | bash -s -- --prefix /usr/local
#
# Flags:
#   --version X.Y.Z   install a specific tagged release (default: latest = main)
#   --prefix  PATH    install directory parent; binary lands at <prefix>/bin/opensop
#                     (default: ~/.local — user-writable, no sudo needed)
#   --dry-run         print what would happen without making changes
#   --help            show this help
#
# Platform notes:
#   Linux   — fully supported; bash 4+ is the distro default everywhere.
#   macOS   — fully supported with bash 4+ (brew install bash).
#             macOS ships bash 3.2 which lacks associative arrays and other
#             bash-4 features the CLI uses.  The installer checks for this
#             and warns clearly if the active bash is too old.
#   Windows — WSL only (install inside a WSL Ubuntu/Debian shell).
#
# Dependencies:
#   bash >= 4.0   required to run opensop
#   jq            required to run opensop  (brew install jq / apt install jq)
#   curl          required for this installer and for opensop upgrade
#
# The installer is idempotent: running it again on an already-installed system
# simply re-downloads and replaces the binary with the same (or newer) version.

set -euo pipefail

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

readonly REPO_OWNER="Chosen9115"
readonly REPO_NAME="opensop"
readonly BINARY_NAME="opensop"
readonly RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}"

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #

_info()    { printf '\033[2m%s\033[0m\n'    "$*" >&2; }
_ok()      { printf '\033[32m✓\033[0m %s\n' "$*" >&2; }
_warn()    { printf '\033[33mwarn:\033[0m %s\n' "$*" >&2; }
_die()     { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
_bold()    { printf '\033[1m%s\033[0m' "$*"; }

# --------------------------------------------------------------------------- #
# Argument parsing
# --------------------------------------------------------------------------- #

PIN_VERSION=""
PREFIX="${HOME}/.local"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || _die "--version requires a value (e.g. --version 0.8.1)"
      PIN_VERSION="$2"; shift
      ;;
    --prefix)
      [[ $# -ge 2 ]] || _die "--prefix requires a path (e.g. --prefix /usr/local)"
      PREFIX="$2"; shift
      ;;
    --dry-run) DRY_RUN=true ;;
    --help|-h)
      grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,2\}//'
      exit 0
      ;;
    *)
      _die "unknown argument '$1' — run with --help for usage"
      ;;
  esac
  shift
done

INSTALL_DIR="${PREFIX}/bin"
INSTALL_PATH="${INSTALL_DIR}/${BINARY_NAME}"

# --------------------------------------------------------------------------- #
# Dependency checks
# --------------------------------------------------------------------------- #

# curl — required for the download itself.
command -v curl >/dev/null 2>&1 \
  || _die "curl is required but was not found on \$PATH"

# bash version check.
# The CLI requires bash 4+ for associative arrays and other 4-only features.
# macOS ships bash 3.2 (GPL-2 licensing prevented Apple from updating it).
_check_bash_version() {
  local major="${BASH_VERSINFO[0]:-0}"
  if [[ "$major" -lt 4 ]]; then
    _warn "your active bash is ${BASH_VERSION} (< 4.0)"
    _warn "opensop requires bash 4+.  On macOS, install a newer bash:"
    _warn "  brew install bash"
    _warn "  echo \$(brew --prefix)/bin/bash | sudo tee -a /etc/shells"
    _warn "  chsh -s \$(brew --prefix)/bin/bash"
    _warn ""
    _warn "On Linux this should not happen — if it does, update bash via your"
    _warn "package manager (apt install bash / yum install bash)."
    _warn ""
    _warn "Continuing install; opensop may not run correctly until bash is updated."
  fi
}

_check_bash_version

# jq — required by opensop at runtime (not by the installer itself).
if ! command -v jq >/dev/null 2>&1; then
  _warn "jq was not found on \$PATH"
  _warn "opensop requires jq to run.  Install it before using opensop:"
  _warn "  macOS:   brew install jq"
  _warn "  Debian:  sudo apt install jq"
  _warn "  Fedora:  sudo dnf install jq"
  _warn ""
  _warn "Continuing install; opensop will tell you when jq is missing."
fi

# --------------------------------------------------------------------------- #
# Determine fetch URL
# --------------------------------------------------------------------------- #

if [[ -n "$PIN_VERSION" ]]; then
  # Normalise: "0.8.1" → "v0.8.1"
  TAG="v${PIN_VERSION#v}"
  FETCH_REF="$TAG"
else
  FETCH_REF="main"
fi

FETCH_URL="${RAW_BASE}/${FETCH_REF}/cli/bin/${BINARY_NAME}"

# --------------------------------------------------------------------------- #
# Show plan
# --------------------------------------------------------------------------- #

printf '\n'
printf '  %s\n' "$(_bold "OpenSOP CLI installer")"
printf '\n'
printf '  source  : %s\n' "$FETCH_URL"
printf '  target  : %s\n' "$INSTALL_PATH"
[[ -n "$PIN_VERSION" ]] && printf '  version : %s\n' "$TAG"
$DRY_RUN       && printf '  mode    : DRY RUN (no changes will be made)\n'
printf '\n'

if $DRY_RUN; then
  _info "(dry run — exiting without making changes)"
  exit 0
fi

# --------------------------------------------------------------------------- #
# Download
# --------------------------------------------------------------------------- #

TMP_BIN="$(mktemp)"
# shellcheck disable=SC2064
trap "rm -f '$TMP_BIN'" EXIT

_info "downloading ${FETCH_URL} …"
curl_exit=0
curl -fsSL "$FETCH_URL" -o "$TMP_BIN" 2>/dev/null || curl_exit=$?
if [[ $curl_exit -ne 0 ]]; then
  _die "download failed (curl exit ${curl_exit}).  Check your network${PIN_VERSION:+" and that tag ${TAG} exists in ${REPO_OWNER}/${REPO_NAME}"}."
fi

# Sanity-check the download: must contain the version constant.
if ! grep -q "OPENSOP_CLI_VERSION" "$TMP_BIN" 2>/dev/null; then
  _die "downloaded file does not look like an opensop binary (OPENSOP_CLI_VERSION missing).  Aborting."
fi

# Extract the version from the downloaded binary for the confirmation message.
NEW_VERSION="$(grep -m1 'OPENSOP_CLI_VERSION=' "$TMP_BIN" | sed 's/.*OPENSOP_CLI_VERSION="\{0,1\}\([^"]*\)"\{0,1\}.*/\1/')"

# --------------------------------------------------------------------------- #
# Install
# --------------------------------------------------------------------------- #

# Create the install directory if it doesn't exist.
if [[ ! -d "$INSTALL_DIR" ]]; then
  _info "creating ${INSTALL_DIR} …"
  mkdir -p "$INSTALL_DIR" || _die "could not create ${INSTALL_DIR} — try --prefix with a writable path, or run with sudo"
fi

if [[ ! -w "$INSTALL_DIR" ]]; then
  _die "${INSTALL_DIR} is not writable.  Try:\n  sudo bash -s -- --prefix /usr/local < install.sh\nor use a writable prefix:\n  bash install.sh --prefix \$HOME/.local"
fi

chmod +x "$TMP_BIN"
# mv for an atomic replace on the same filesystem; fall back to cp.
if ! mv "$TMP_BIN" "$INSTALL_PATH" 2>/dev/null; then
  cp "$TMP_BIN" "$INSTALL_PATH"
  chmod +x "$INSTALL_PATH"
  rm -f "$TMP_BIN"
fi

_ok "installed opensop ${NEW_VERSION} → ${INSTALL_PATH}"

# --------------------------------------------------------------------------- #
# PATH check and post-install hint
# --------------------------------------------------------------------------- #

_on_path=false
if command -v opensop >/dev/null 2>&1; then
  _on_path=true
fi

printf '\n'
if $_on_path; then
  _ok "opensop is on your \$PATH — verify with: opensop --version"
else
  printf '  \033[33m!\033[0m  %s is not on your \$PATH.\n' "$INSTALL_DIR"
  printf '     Add it by appending this line to your shell profile\n'
  printf '     (~/.bashrc, ~/.zshrc, or ~/.profile):\n'
  printf '\n'
  printf '       export PATH="%s:$PATH"\n' "$INSTALL_DIR"
  printf '\n'
  printf '     Then reload your shell:\n'
  printf '       source ~/.bashrc   # or: exec bash\n'
fi

printf '\n'
printf '  %s\n' "Quick start:"
printf '    opensop --version\n'
printf '    opensop help\n'
printf '    opensop run ./your-process.sop.json\n'
printf '\n'
printf '  To upgrade later:\n'
printf '    opensop upgrade\n'
printf '    opensop upgrade --pin 0.9.0\n'
printf '\n'
