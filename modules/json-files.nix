# Declares keys in JSON files that apps also write to (e.g. Claude Code's
# settings), which rules out home.file's read-only symlinks. On activation the
# declared keys are deep-merged into the live file; everything else in it is
# kept. Keys declared by the previous activation but not anymore are removed.
{ config, lib, pkgs, ... }:

let
  cfg = config.framework.jsonFiles;

  stateDir = "${config.xdg.stateHome}/framework/json-files";

  merge = pkgs.writeShellApplication {
    name = "merge-json";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      target=$1 declared=$2 state=$3

      current='{}'
      if [[ -e $target ]]; then
        if ! jq -e 'type == "object"' "$target" >/dev/null 2>&1; then
          echo "warning: $target is not a JSON object, leaving it alone" >&2
          exit 0
        fi
        current=$(<"$target")
      fi
      previous='{}'
      [[ -e $state ]] && previous=$(<"$state")

      mkdir -p "$(dirname "$target")" "$(dirname "$state")"
      tmp=$(mktemp "$target.XXXXXX")
      # Objects merge recursively; any other value (arrays included) replaces.
      jq -n --argjson current "$current" --argjson previous "$previous" \
        --slurpfile declared "$declared" '
          reduce ($previous | paths(type != "object")) as $path ($current;
            . as $acc | try delpaths([$path]) catch $acc)
          * $declared[0]
        ' >"$tmp"
      if [[ -e $target ]]; then
        chmod --reference="$target" "$tmp"
      else
        chmod 600 "$tmp"
      fi
      mv "$tmp" "$target"
      cp "$declared" "$state"
    '';
  };

  stateFile = path: "${stateDir}/${lib.replaceStrings [ "/" ] [ "%" ] path}";
in {
  options.framework.jsonFiles = lib.mkOption {
    type = lib.types.attrsOf (pkgs.formats.json { }).type;
    default = { };
    example = { ".claude/settings.json".model = "opus"; };
    description = ''
      JSON files (paths relative to the home directory) and the keys to set in
      them. Objects are merged recursively; any other value, arrays included,
      replaces what's in the file. Keys set outside of Nix are kept, and a
      file that isn't a JSON object is left alone with a warning.
    '';
  };

  config.home.activation.mergeJsonFiles = lib.mkIf (cfg != { })
    (lib.hm.dag.entryAfter [ "writeBoundary" ] (lib.concatStrings (lib.mapAttrsToList (path: value:
      let declared = pkgs.writeText "declared.json" (builtins.toJSON value);
      in ''
        run ${merge}/bin/merge-json "$HOME"/${lib.escapeShellArg path} ${declared} \
          ${lib.escapeShellArg (stateFile path)}
      '') cfg)));
}
