# Opt-in profile for NixOS-WSL hosts. Needs a `nixos-wsl` flake input.
{ inputs, host, ... }:

{
  imports = [ inputs.nixos-wsl.nixosModules.wsl ];

  wsl.enable = true;
  wsl.defaultUser = host.user;
}
