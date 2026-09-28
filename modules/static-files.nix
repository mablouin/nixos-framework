# Places static files as real copies instead of home.file's symlinks into the
# store, for readers that don't follow those. For instance, AI coding agents
# treat a symlink leading outside the working directory as an external file.
# Copies are replaced on every activation; one that was edited since the last
# activation is backed up first. A file dropped from Nix is removed, unless it
# was edited since.
{ config, lib, pkgs, ... }:

let
  cfg = config.framework.staticFiles;

  stateDir = "${config.xdg.stateHome}/framework/static-files";

  sync = pkgs.writeShellApplication {
    name = "sync-static-files";
    text = ''
      # Arguments: pairs of <path from home> <source>. The state dir keeps
      # the last copy of each file, to tell edits apart and find dropped ones.
      state=${lib.escapeShellArg stateDir}
      declare -A declared=()

      edited() { [[ -e $1 ]] && ! cmp -s "$1" "$2"; }

      while (( $# )); do
        path=$1 source=$2
        shift 2
        declared[$path]=1
        target=$HOME/$path saved=$state/''${path//\//%}

        if edited "$target" "$source" && { [[ ! -e $saved ]] || edited "$target" "$saved"; }; then
          echo "warning: $target was changed outside of Nix, moving it to $target.backup" >&2
          mv "$target" "$target.backup"
        fi
        mkdir -p "$(dirname "$target")" "$state"
        # install, not cp, so the copies don't keep the store's read-only mode.
        install -m 644 "$source" "$target"
        install -m 644 "$source" "$saved"
      done

      shopt -s nullglob
      for saved in "$state"/*; do
        name=''${saved##*/} path=''${name//%//}
        [[ -v declared[$path] ]] && continue
        target=$HOME/$path
        if edited "$target" "$saved"; then
          echo "warning: $target is no longer declared but was changed outside of Nix, keeping it" >&2
        else
          rm -f "$target"
        fi
        rm "$saved"
      done
    '';
  };
in {
  options.framework.staticFiles = lib.mkOption {
    type = lib.types.attrsOf lib.types.path;
    default = { };
    example = lib.literalExpression ''{ "AGENTS.md" = ./agents-home.md; }'';
    description = ''
      Files to place as copies (paths relative to the home directory) and
      their sources. The copies are writable, but Nix wins: edits are moved
      to `<file>.backup` on the next activation.
    '';
  };

  # Runs even when nothing is declared, to remove files dropped from Nix.
  config.home.activation.syncStaticFiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${sync}/bin/sync-static-files ${lib.escapeShellArgs
      (lib.concatLists (lib.mapAttrsToList (path: source: [ path "${source}" ]) cfg))}
  '';
}
