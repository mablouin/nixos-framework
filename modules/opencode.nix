# OpenCode. nixpkgs' own build corrupts the embedded Bun payload's segment
# order, causing a SIGSEGV on every invocation (upstream
# anomalyco/opencode#26846). Fetching the official release tarball unmodified
# (dontFixup, no patchelf) and relying on nix-ld (programs.nix-ld.enable, see
# profiles/wsl.nix) for the interpreter avoids the corruption entirely. Bump
# version + sha256 below to upgrade, or override framework.opencode.package
# entirely.
#
# opencode.json and auth.json go through framework.jsonFiles rather than
# home-manager's read-only file management, since OpenCode's own auth flow
# can write to auth.json (and a plain store symlink would break if OpenCode
# ever writes to opencode.json too).
{ config, lib, pkgs, ... }:

let
  cfg = config.framework.opencode;

  defaultPackage = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "opencode";
    version = "1.18.34";

    src = pkgs.fetchurl {
      url = "https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-linux-x64.tar.gz";
      sha256 = "16ky3nkw3vs11flwcbdnf0wdlyzfh80d55cmv4nisv928yb4f8hg";
    };

    sourceRoot = ".";
    dontFixup = true;

    installPhase = ''
      install -Dm755 opencode $out/bin/opencode
    '';
  };
in {
  options.framework.opencode = {
    enable = lib.mkEnableOption "OpenCode";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      description = ''
        The opencode package to install. Defaults to the official release
        tarball (see the module header for why nixpkgs' build isn't used).
      '';
    };

    configDir = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${lib.removePrefix "${config.home.homeDirectory}/" config.xdg.configHome}/opencode";
      description = "Path, relative to the home directory, of opencode's config directory.";
    };

    settings = lib.mkOption {
      type = (pkgs.formats.json { }).type;
      default = { };
      example = {
        model = "foundry-openai/gpt-6-luna";
        small_model = "foundry-openai/gpt-6-luna";
        provider = { };
        mcp = { };
      };
      description = ''
        Keys to set in opencode's opencode.json (see framework.jsonFiles for
        how they're merged).
      '';
    };

    auth = lib.mkOption {
      type = (pkgs.formats.json { }).type;
      default = { };
      example = {
        foundry-openai = { type = "api"; key = "azure-ad-via-plugin"; };
      };
      description = ''
        Keys to set in opencode's auth.json (see framework.jsonFiles for how
        they're merged).
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.settings == { } && cfg.auth == { } || cfg.enable;
        message = "framework.opencode is set but disabled; set framework.opencode.enable = true.";
      }
    ];

    home.packages = lib.mkIf cfg.enable [ cfg.package ];

    framework.jsonFiles = lib.mkMerge [
      (lib.mkIf (cfg.settings != { }) { "${cfg.configDir}/opencode.json" = cfg.settings; })
      (lib.mkIf (cfg.auth != { }) {
        "${lib.removePrefix "${config.home.homeDirectory}/" config.xdg.dataHome}/opencode/auth.json" = cfg.auth;
      })
    ];
  };
}
