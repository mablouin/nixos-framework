# Bootstraps a machine from a config repo built on top of nixos-framework:
# clones the config, then applies its NixOS and home-manager configurations.

usage() {
  cat <<USAGE
Usage: nix run github:${FRAMEWORK_REPO} -- [options] <config-repo> <host>

Clones <config-repo> into the config directory, then applies the
nixosConfigurations.<host> and homeConfigurations.<host> outputs of its flake.

Arguments:
  <config-repo>  GitHub "owner/repo", or any git URL / local path
  <host>         Name of the host outputs to apply

Options:
  -b, --branch <name>  Branch to clone (default: the repo's default branch)
  -d, --dir <path>     Clone destination (default: ~/.nixos-config)
  -f, --framework <flake-ref>
                       Use this framework instead of the config's locked one,
                       e.g. path:/home/me/git/nixos-framework or
                       github:${FRAMEWORK_REPO}/<branch> (lock file untouched)
  -h, --help           Show this help
USAGE
}

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

branch=""
dir="$HOME/.nixos-config"
framework=""
positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--branch) branch="${2:?--branch requires a value}"; shift 2 ;;
    -d|--dir) dir="${2:?--dir requires a value}"; shift 2 ;;
    -f|--framework) framework="${2:?--framework requires a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; die "unknown option: $1" ;;
    *) positional+=("$1"); shift ;;
  esac
done
[[ ${#positional[@]} -eq 2 ]] || { usage >&2; exit 1; }
repo="${positional[0]}"
host="${positional[1]}"

[[ $EUID -ne 0 ]] || die "run as your regular user, not root (sudo is used where needed)"

# Resolve the clone URL. Only GitHub "owner/repo" slugs get the auth fallback.
github_slug=""
case "$repo" in
  *://*|git@*|/*|./*|../*|~*) url="$repo" ;;
  */*) github_slug="$repo"; url="https://github.com/$repo.git" ;;
  *) die "config repo must be \"owner/repo\", a git URL or a path: $repo" ;;
esac

can_read() { GIT_TERMINAL_PROMPT=0 git ls-remote "$1" HEAD >/dev/null 2>&1; }

# Prints a GitHub token, logging in with the device flow if needed. Honors
# GH_TOKEN. The login is saved to ~/.config/gh so gh stays authenticated
# after the bootstrap.
github_token() {
  if ! gh auth status --hostname github.com >/dev/null 2>&1; then
    log "Log in to GitHub to access $github_slug" >&2
    # On WSL, open the device page in the Windows browser while gh prints the code.
    if [[ -n ${WSL_DISTRO_NAME:-} ]] && command -v explorer.exe >/dev/null; then
      explorer.exe "https://github.com/login/device" >/dev/null 2>&1 || true
    fi
    # Prompts disabled: gh would otherwise offer to install itself as git's
    # credential helper, pointing at this ephemeral store path.
    GH_PROMPT_DISABLED=1 gh auth login --hostname github.com --git-protocol https \
      --web --insecure-storage </dev/null >&2 || die "GitHub login failed"
  fi
  gh auth token --hostname github.com
}

# --- Clone -------------------------------------------------------------------

token=""
if [[ -d $dir/.git ]]; then
  log "$dir already exists, skipping clone"
elif [[ -e $dir && -n $(ls -A "$dir") ]]; then
  die "$dir exists and is not an empty directory"
else
  clone_url="$url"
  if ! can_read "$url"; then
    [[ -n $github_slug ]] || die "cannot read $url"
    token=$(github_token)
    clone_url="https://oauth2:${token}@github.com/${github_slug}.git"
    can_read "$clone_url" || die "authenticated, but still cannot read $github_slug"
  fi

  clone_args=()
  [[ -z $branch ]] || clone_args+=(--branch "$branch")
  log "Cloning $repo into $dir"
  git clone "${clone_args[@]}" "$clone_url" "$dir"
  # Never persist the token in .git/config.
  git -C "$dir" remote set-url origin "$url"
fi

# --- Apply -------------------------------------------------------------------

# Child nix invocations don't inherit the caller's --extra-experimental-features.
NIX_CONFIG="${NIX_CONFIG:+$NIX_CONFIG$'\n'}extra-experimental-features = nix-command flakes"
[[ -z $token ]] || NIX_CONFIG+=$'\n'"access-tokens = github.com=$token"
export NIX_CONFIG

# Flags added to every flake evaluation. --override-input implies
# --no-write-lock-file, so testing another framework never touches flake.lock.
flake_args=()
[[ -z $framework ]] || flake_args+=(--override-input framework "$framework")

# True if the flake has <output>.<host>. A flake without <output> at all is
# fine; any other evaluation error is fatal.
eval_err=$(mktemp)
trap 'rm -f "$eval_err"' EXIT
has_output() {
  local result
  if ! result=$(nix eval "${flake_args[@]}" --raw "$dir#$1" \
      --apply "c: if builtins.hasAttr \"$host\" c then \"yes\" else \"no\"" 2>"$eval_err"); then
    grep -q "does not provide attribute" "$eval_err" && return 1
    cat "$eval_err" >&2
    die "failed to evaluate the flake in $dir"
  fi
  [[ $result == yes ]]
}

applied=0

if [[ -e /etc/NIXOS ]] && has_output nixosConfigurations; then
  log "Applying NixOS configuration '$host'"
  # Exit code 4 means the new generation is active but some units (or the
  # user's systemd manager, often not running yet on a fresh WSL boot) failed
  # to reload; a restart fixes it, so keep going.
  status=0
  nixos-rebuild switch --sudo --flake "$dir#$host" "${flake_args[@]}" || status=$?
  case $status in
    0) ;;
    4) printf '\033[1;33mwarning:\033[0m %s\n' \
        "NixOS configuration activated, but some units failed to reload (restart to fix)" >&2 ;;
    *) exit "$status" ;;
  esac
  applied=1
fi

if has_output homeConfigurations; then
  log "Applying home-manager configuration '$host'"
  activation=$(nix build "${flake_args[@]}" --no-link --print-out-paths \
    "$dir#homeConfigurations.\"$host\".activationPackage")
  HOME_MANAGER_BACKUP_EXT=backup "$activation/activate"
  applied=1
fi

[[ $applied -eq 1 ]] || die "no nixosConfigurations.$host or homeConfigurations.$host in $dir"

log "Bootstrap complete"
if [[ -n ${WSL_DISTRO_NAME:-} ]]; then
  echo "Restart the distro to pick up all changes: wsl.exe --terminate $WSL_DISTRO_NAME"
fi
