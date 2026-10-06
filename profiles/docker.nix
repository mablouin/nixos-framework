# Opt-in profile for NixOS hosts that need a local Docker Engine daemon.
#
# Import with `imports = [ framework.nixosModules.docker ];` from a host module.
{ pkgs-unstable, ... }:

{
  virtualisation.docker = {
    enable = true;
    package = pkgs-unstable.docker;
  };
}
