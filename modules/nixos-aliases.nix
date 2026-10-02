# nixos-switch / home-switch shell functions, so changes can be applied and
# tested before committing. Two sets:
#
# - nixos-switch / home-switch: the local config checkout (path:, includes
#   uncommitted and untracked files) with the local framework checkout
#   overriding the `framework` input, so both repos are switched as they are
#   on disk and the lock is ignored. NIXOS_FRAMEWORK_LOCKED=1 keeps the
#   locked framework instead, to check what the lock alone produces.
# - nixos-switch-main / home-switch-main: the repo's main branch (github:)
#   with its locked framework, i.e. what's actually pushed.
{ config, lib, host, ... }:

let
  cfg = config.framework.nixosAliases;
  checkouts = config.framework.checkouts;

  # Same convention as framework.checkouts: the folder is the URL's last
  # segment, without ".git".
  nameOf = url: lib.removeSuffix ".git" (baseNameOf (lib.removeSuffix "/" url));

  ownerRepoOf = url:
    let
      stripped = lib.removeSuffix ".git" url;
      m = builtins.match ".*github\\.com[:/]([^/]+/[^/]+)" stripped;
    in
    if m == null then null else builtins.head m;

  configUrl = lib.findFirst (url: nameOf url == cfg.configDir) null checkouts.repos;
  ownerRepo = if configUrl == null then null else ownerRepoOf configUrl;

  localConfig = "$HOME/${checkouts.dir}/${cfg.configDir}";
  localFramework = "$HOME/${checkouts.dir}/${cfg.frameworkDir}";
in
{
  options.framework.nixosAliases = {
    configDir = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "nixos-config";
      description = ''
        Name of the config repo checkout (one of `framework.checkouts.repos`,
        cloned under `framework.checkouts.dir`) that `nixos-switch` /
        `home-switch` switch from. Empty disables these functions.
      '';
    };
    frameworkDir = lib.mkOption {
      type = lib.types.str;
      default = "nixos-framework";
      description = ''
        Name of the framework checkout. `nixos-switch` and `home-switch`
        override the `framework` flake input with it, unless
        `NIXOS_FRAMEWORK_LOCKED=1` is set.
      '';
    };
    host = lib.mkOption {
      type = lib.types.str;
      default = host.name;
      description = "Flake output name to switch, i.e. `<flake-ref>#<host>`.";
    };
  };

  config = {
    assertions = [{
      assertion = cfg.configDir == "" || ownerRepo != null;
      message = ''
        framework.nixosAliases.configDir "${cfg.configDir}" doesn't match a
        GitHub URL in framework.checkouts.repos.
      '';
    }];

    programs.zsh.initContent = lib.mkIf (cfg.configDir != "") ''
      nixos-switch() {
        local args=(--flake "path:${localConfig}#${cfg.host}")
        [[ -z "$NIXOS_FRAMEWORK_LOCKED" ]] && args+=(--override-input framework "path:${localFramework}")
        sudo nixos-rebuild switch ''${args[@]}
      }

      home-switch() {
        local args=(--flake "path:${localConfig}#${cfg.host}")
        [[ -z "$NIXOS_FRAMEWORK_LOCKED" ]] && args+=(--override-input framework "path:${localFramework}")
        home-manager switch -b backup ''${args[@]}
      }

      nixos-switch-main() {
        local args=(--flake "github:${toString ownerRepo}#${cfg.host}" --refresh)
        NIX_CONFIG="access-tokens = github.com=$(gh auth token)" \
          sudo --preserve-env=NIX_CONFIG nixos-rebuild switch ''${args[@]}
      }

      home-switch-main() {
        local args=(--flake "github:${toString ownerRepo}#${cfg.host}" --refresh)
        NIX_CONFIG="access-tokens = github.com=$(gh auth token)" \
          home-manager switch -b backup ''${args[@]}
      }
    '';
  };
}
