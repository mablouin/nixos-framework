# Builds nixosConfigurations / homeConfigurations from a directory of host
# files. Each <hostsDir>/<name>.nix returns:
#
#   { system, user, nixos ? <module>, home ? <module> }
#
# `system`, `user` and `name` are passed to every module as `host`, along with
# `framework` (this flake) and `inputs` (the calling flake's inputs). A host
# without `nixos` only gets a home-manager config.
{ framework, inputs }:

{ hostsDir, nixosModulesDir ? null, homeModulesDir ? null, inputs ? { } }:

let
  inherit (framework.inputs) nixpkgs nixpkgs-unstable home-manager;
  inherit (nixpkgs) lib;
  configInputs = inputs;

  nixFilesIn = dir:
    lib.optionals (dir != null)
      (lib.filter (lib.hasSuffix ".nix") (lib.filesystem.listFilesRecursive dir));

  hostDefs = lib.mapAttrs'
    (file: _: lib.nameValuePair (lib.removeSuffix ".nix" file) (import (hostsDir + "/${file}")))
    (lib.filterAttrs (file: _: lib.hasSuffix ".nix" file) (builtins.readDir hostsDir));

  hostsWith = kind: lib.filterAttrs (_: def: def ? ${kind}) hostDefs;

  hostInfo = name: def: removeAttrs def [ "nixos" "home" ] // { inherit name; };

  importPkgs = source: host: import source {
    inherit (host) system;
    config.allowUnfree = true;
  };

  specialArgsFor = host: {
    inherit framework host;
    inputs = configInputs;
    pkgs-unstable = importPkgs nixpkgs-unstable host;
  };
in {
  nixosConfigurations = lib.mapAttrs (name: def: lib.nixosSystem {
    specialArgs = specialArgsFor (hostInfo name def);
    modules = [ ../modules/nixos-base.nix ] ++ nixFilesIn nixosModulesDir ++ [ def.nixos ];
  }) (hostsWith "nixos");

  homeConfigurations = lib.mapAttrs (name: def: home-manager.lib.homeManagerConfiguration {
    pkgs = importPkgs nixpkgs def;
    extraSpecialArgs = specialArgsFor (hostInfo name def);
    modules = [ ../modules/home-base.nix ] ++ nixFilesIn homeModulesDir ++ [ def.home ];
  }) (hostsWith "home");
}
