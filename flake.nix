{
  description = "Reusable NixOS / home-manager building blocks and bootstrap";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
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
