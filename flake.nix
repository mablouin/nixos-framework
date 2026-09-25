{
  description = "Reusable NixOS / home-manager building blocks and bootstrap";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    nixos-wsl = {
      url = "github:nix-community/nixos-wsl/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, nixos-wsl, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      lib.mkHosts = import ./lib/mk-hosts.nix { framework = self; inherit inputs; };

      nixosModules.wsl = {
        imports = [ nixos-wsl.nixosModules.wsl ./profiles/wsl.nix ];
      };

      packages.${system} = {
        bootstrap = pkgs.writeShellApplication {
          name = "bootstrap";
          runtimeInputs = with pkgs; [ git gh ];
          runtimeEnv.FRAMEWORK_REPO = "mablouin/nixos-framework";
          text = builtins.readFile ./scripts/bootstrap.sh;
        };
        default = self.packages.${system}.bootstrap;
      };

      apps.${system}.default = {
        type = "app";
        program = "${self.packages.${system}.bootstrap}/bin/bootstrap";
      };
    };
}
