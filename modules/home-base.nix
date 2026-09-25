# Base for every home-manager config.
{ host, ... }:

{
  home.username = host.user;
  home.homeDirectory = "/home/${host.user}";

  programs.home-manager.enable = true;

  # zsh is the login shell (see nixos-base.nix); letting home-manager manage
  # its dotfiles makes zsh load home.sessionVariables.
  programs.zsh.enable = true;
}
