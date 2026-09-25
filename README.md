# nixos-framework

Reusable NixOS / home-manager building blocks, meant to be vendored into a
personal config repo as a `git subtree` under `framework/`.

## Bootstrap

On a fresh NixOS (WSL) install:

```sh
nix --extra-experimental-features 'nix-command flakes' \
  run github:mablouin/nixos-framework -- <owner/config-repo> <host>
```

This will:

1. Clone the config repo into `~/.nixos-config` (use `--dir` to change it)
2. Add a `framework` git remote for the subtree workflow
3. Apply `nixosConfigurations.<host>` with `nixos-rebuild switch`
4. Activate `homeConfigurations.<host>` (conflicting files get a `.backup`
   suffix)

`<owner/config-repo>` can also be a full git URL or a local path. Run with
`--help` for all options.

## Building hosts

`lib/mk-hosts.nix` turns a directory of host files into the
`nixosConfigurations` / `homeConfigurations` the bootstrap expects:

```nix
outputs = inputs: import ./framework/lib/mk-hosts.nix {
  inherit inputs;
  hostsDir = ./hosts;
  homeModulesDir = ./home; # optional, auto-imported for every host
  # nixosModulesDir = ./nixos; # optional, same for NixOS hosts
};
```

`inputs` must provide `nixpkgs`, `nixpkgs-unstable` and `home-manager`, plus
`nixos-wsl` for hosts using the WSL profile.

Each `hosts/<name>.nix` describes one machine; the hostname is the file name:

```nix
{
  system = "x86_64-linux";
  user = "nixos";

  nixos = {
    imports = [ ../framework/profiles/wsl.nix ];
    system.stateVersion = "26.05";
  };

  home = {
    home.stateVersion = "26.05";
  };
}
```

`system`, `user` and `name` are available to every module as `host`. A host
without `nixos` only gets a home-manager config.

## Layout

```text
.
├── flake.nix              # Bootstrap app (nix run)
├── scripts/bootstrap.sh
├── lib/mk-hosts.nix       # Host files → flake outputs
├── modules/
│   ├── nixos-base.nix     # Always applied: host, user, nix, git, zsh
│   └── home-base.nix      # Always applied: home-manager basics, zsh
└── profiles/
    └── wsl.nix            # Opt-in: NixOS-WSL
```

## Subtree workflow

From the config repo:

```sh
git subtree pull --prefix framework framework main --squash
git subtree push --prefix framework framework <branch>
```
