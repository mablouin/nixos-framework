# Claude Code settings that stay writable: Claude Code edits its own
# settings.json and ~/.claude.json, so these go through framework.jsonFiles
# instead of home-manager's read-only programs.claude-code.settings (setting
# that is an error). Everything else (enable, package, agents, commands...)
# is home-manager's programs.claude-code.
#
# Provider settings such as Microsoft Foundry's belong in settings.env: they
# apply to Claude Code and the processes it starts, however it's launched
# (e.g. from an IDE), and never reach the shell.
{ config, lib, pkgs, ... }:

let
  cfg = config.framework.claude-code;

  configDir = lib.removePrefix "${config.home.homeDirectory}/" config.programs.claude-code.configDir;
in {
  options.framework.claude-code = {
    settings = lib.mkOption {
      type = (pkgs.formats.json { }).type;
      default = { };
      example = {
        model = "opus";
        env.CLAUDE_CODE_USE_FOUNDRY = "1";
      };
      description = ''
        Keys to set in Claude Code's settings.json (see framework.jsonFiles
        for how they're merged).
      '';
    };
    trustedDirectories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "/home/me" ];
      description = "Directories whose trust dialog is pre-accepted in ~/.claude.json.";
    };
  };

  config = {
    assertions = [
      {
        assertion = config.programs.claude-code.settings == { };
        message = "Use framework.claude-code.settings instead of programs.claude-code.settings, which makes settings.json read-only.";
      }
      {
        # The framework never enables Claude Code by itself.
        assertion = cfg.settings == { } && cfg.trustedDirectories == [ ]
          || config.programs.claude-code.enable;
        message = "framework.claude-code is set but Claude Code isn't enabled; set programs.claude-code.enable = true.";
      }
    ];

    framework.jsonFiles = lib.mkMerge [
      (lib.mkIf (cfg.settings != { }) {
        "${configDir}/settings.json" = cfg.settings;
      })
      (lib.mkIf (cfg.trustedDirectories != [ ]) {
        ".claude.json".projects = lib.genAttrs cfg.trustedDirectories
          (_: { hasTrustDialogAccepted = true; });
      })
    ];
  };
}
