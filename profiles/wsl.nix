# Opt-in profile for NixOS-WSL hosts, exported as `nixosModules.wsl`.
{ host, ... }:

{
  wsl.enable = true;
  wsl.defaultUser = host.user;
}
