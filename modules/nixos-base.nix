# Base for every NixOS host: host identity, the user account, Nix settings and
# the essential tools (git, and zsh as the login shell).
{ pkgs, host, ... }:

{
  networking.hostName = host.name;

  nixpkgs.hostPlatform = host.system;
  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  users.users.${host.user} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

  environment.systemPackages = with pkgs; [
    git
    zsh
  ];
}
