# nixos-framework

Reusable NixOS / home-manager building blocks, consumed by a personal config
repo as a flake input.

## Bootstrap

On a fresh NixOS (WSL) install:

```sh
nix --extra-experimental-features 'nix-command flakes' \
  run github:mablouin/nixos-framework -- <owner/config-repo> <host>
```

This will:

1. Log in to GitHub (device flow) if the config repo is private and `gh` is
   not already authenticated (`GH_TOKEN` is honored)
2. Clone the config repo into `~/.nixos-config` (use `--dir` to change it)
3. Apply `nixosConfigurations.<host>` with `nixos-rebuild switch`
4. Activate `homeConfigurations.<host>` (conflicting files get a `.backup`
   suffix)

`<owner/config-repo>` can also be a full git URL or a local path. Run with
`--help` for all options.

## Using it from a config repo

The framework owns the `nixpkgs`, `nixpkgs-unstable`, `home-manager` and
`nixos-wsl` inputs; the config repo only needs the framework itself:

```nix
{
  inputs.framework.url = "github:mablouin/nixos-framework";

  outputs = inputs@{ framework, ... }: framework.lib.mkHosts {
    inherit inputs;
    hostsDir = ./hosts;
    homeModulesDir = ./home; # optional, auto-imported for every host
    # nixosModulesDir = ./nixos; # optional, same for NixOS hosts
  };
}
```

Each `hosts/<name>.nix` describes one machine; the hostname is the file name:

```nix
{
  system = "x86_64-linux";
  user = "nixos";

  nixos = { framework, ... }: {
    imports = [ framework.nixosModules.wsl ];
    system.stateVersion = "26.05";
  };

  home = {
    home.stateVersion = "26.05";
  };
}
```

Every module receives:

- `host`: `system`, `user` and `name` of the host being built
- `framework`: this flake, for opt-in modules like `framework.nixosModules.wsl`
- `inputs`: the config repo's inputs
- `pkgs-unstable`: nixpkgs-unstable for the host's system

A host without `nixos` only gets a home-manager config.

## Testing framework changes

Point the config at a local checkout or a branch with `--override-input`. It
implies `--no-write-lock-file`, so `flake.nix` and `flake.lock` stay untouched:

```sh
nixos-rebuild switch --sudo --flake ~/.nixos-config#<host> \
  --override-input framework path:$HOME/git/nixos-framework
```

`path:` includes uncommitted and untracked files. Use
`github:mablouin/nixos-framework/<branch>` to test a pushed branch instead.
The bootstrap takes the same thing as `--framework <flake-ref>`.

To test from another WSL distro, share the checkout through `/mnt/wsl`, which
all WSL 2 distros see:

```sh
sudo mkdir -p /mnt/wsl/dev && sudo mount --bind ~/git /mnt/wsl/dev
```

Then use `path:/mnt/wsl/dev/nixos-framework` from the test distro.

## Layout

```text
.
├── flake.nix              # Inputs, lib.mkHosts, nixosModules, bootstrap app
├── scripts/bootstrap.sh
├── lib/mk-hosts.nix       # Host files → flake outputs
├── modules/
│   ├── nixos-base.nix     # Always applied: host, user, nix, git, zsh
│   └── home-base.nix      # Always applied: home-manager basics, zsh
└── profiles/
    └── wsl.nix            # Opt-in as nixosModules.wsl
```
