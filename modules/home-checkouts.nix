# Clones git repos on activation when they're missing, e.g. the config repo
# itself so it can be edited and switched from source.
{ config, lib, pkgs, ... }:

let
  cfg = config.framework.checkouts;

  # The folder is the URL's last segment, without ".git".
  nameOf = url: lib.removeSuffix ".git" (baseNameOf (lib.removeSuffix "/" url));

  # gh's credential helper covers private GitHub repos once gh is logged in
  # (the bootstrap does that); public repos clone without it.
  git = lib.escapeShellArgs [
    "${pkgs.git}/bin/git"
    "-c" "credential.helper="
    "-c" "credential.helper=!${pkgs.gh}/bin/gh auth git-credential"
  ];
in {
  options.framework.checkouts = {
    dir = lib.mkOption {
      type = lib.types.str;
      example = "git";
      description = "Directory to clone into, relative to the home directory.";
    };
    repos = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "https://github.com/me/nixos-config.git" ];
      description = ''
        Clone URLs of repos to clone into `dir` if missing. Each one is cloned
        into a folder named after the URL's last segment (without ".git").
        Existing folders are never touched, and a failed clone only warns.
      '';
    };
  };

  config.home.activation.cloneCheckouts = lib.mkIf (cfg.repos != [ ])
    (lib.hm.dag.entryAfter [ "writeBoundary" ] (lib.concatMapStrings (url:
      let dest = ''"$HOME"/${lib.escapeShellArg "${cfg.dir}/${nameOf url}"}'';
      in ''
        if [[ ! -e ${dest} ]]; then
          verboseEcho "Cloning ${url}"
          GIT_TERMINAL_PROMPT=0 run ${git} clone ${lib.escapeShellArg url} ${dest} \
            || warnEcho "could not clone ${url} into ~/${cfg.dir}"
        fi
      '') cfg.repos));
}
