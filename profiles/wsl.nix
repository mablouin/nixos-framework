# Opt-in profile for NixOS-WSL hosts, exported as `nixosModules.wsl`.
#
# nix-ld provides a dynamic loader for generic Linux binaries, such as the
# VS Code server that the WSL extension downloads into `~/.vscode-server`.
# Without it, its `node` fails with NixOS's stub-ld error and VS Code can't
# connect.
{ host, ... }:

{
  wsl.enable = true;
  wsl.defaultUser = host.user;

  programs.nix-ld.enable = true;
}
