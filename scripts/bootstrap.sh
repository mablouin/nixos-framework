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
  -h, --help           Show this help
USAGE
}

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

branch=""
dir="$HOME/.nixos-config"
positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--branch) branch="${2:?--branch requires a value}"; shift 2 ;;
    -d|--dir) dir="${2:?--dir requires a value}"; shift 2 ;;
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
    # TODO: interactive GitHub device-flow login (next milestone step).
    token=$(gh auth token --hostname github.com 2>/dev/null) \
      || die "cannot read $github_slug anonymously; set GH_TOKEN or run 'gh auth login' first"
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

# The framework is vendored as a git subtree; add its remote for subtree pull/push.
if [[ -d $dir/framework ]] && ! git -C "$dir" remote get-url framework >/dev/null 2>&1; then
  git -C "$dir" remote add framework "https://github.com/$FRAMEWORK_REPO.git"
fi

# --- Apply -------------------------------------------------------------------

# Child nix invocations don't inherit the caller's --extra-experimental-features.
NIX_CONFIG="${NIX_CONFIG:+$NIX_CONFIG$'\n'}extra-experimental-features = nix-command flakes"
[[ -z $token ]] || NIX_CONFIG+=$'\n'"access-tokens = github.com=$token"
export NIX_CONFIG

has_output() {
  [[ $(nix eval --raw "$dir#$1" \
    --apply "c: if builtins.hasAttr \"$host\" c then \"yes\" else \"no\"" 2>/dev/null) == yes ]]
}

applied=0

if [[ -e /etc/NIXOS ]] && has_output nixosConfigurations; then
  log "Applying NixOS configuration '$host'"
  # Exit code 4 means the new generation is active but some units (or the
  # user's systemd manager, often not running yet on a fresh WSL boot) failed
  # to reload; a restart fixes it, so keep going.
  status=0
  nixos-rebuild switch --sudo --flake "$dir#$host" || status=$?
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
  activation=$(nix build --no-link --print-out-paths \
    "$dir#homeConfigurations.\"$host\".activationPackage")
  HOME_MANAGER_BACKUP_EXT=backup "$activation/activate"
  applied=1
fi

[[ $applied -eq 1 ]] || die "no nixosConfigurations.$host or homeConfigurations.$host in $dir"

log "Bootstrap complete"
if [[ -n ${WSL_DISTRO_NAME:-} ]]; then
  echo "Restart the distro to pick up all changes: wsl.exe --terminate $WSL_DISTRO_NAME"
fi
