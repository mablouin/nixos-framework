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
2. Apply `nixosConfigurations.<host>` with `nixos-rebuild switch`
3. Activate `homeConfigurations.<host>` (conflicting files get a `.backup`
   suffix)

Both are built straight from `github:<owner/config-repo>`; nothing is cloned.
To get local checkouts to edit and switch from, list them in
`framework.checkouts` (see below). `<owner/config-repo>` can also be any flake
ref, such as `path:/some/checkout`. Run with `--help` for all options.

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

### Checkouts

`framework.checkouts` clones repos into one directory (relative to home) on
home-manager activation when they're missing. Each clone URL lands in a
folder named after its last segment (without `.git`). Existing folders are
left alone, and a failed clone only warns. Private GitHub repos use `gh`'s
login, which the bootstrap sets up:

```nix
{
  framework.checkouts = {
    dir = "git";
    repos = [
      "https://github.com/me/nixos-config.git"
      "https://github.com/mablouin/nixos-framework.git"
    ];
  };
}
```

## Testing framework changes

Point the config at a local checkout or a branch with `--override-input`. It
implies `--no-write-lock-file`, so `flake.nix` and `flake.lock` stay untouched:

```sh
nixos-rebuild switch --sudo --flake ~/git/nixos-config#<host> \
  --override-input framework path:$HOME/git/nixos-framework
```

`path:` includes uncommitted and untracked files. Use
`github:mablouin/nixos-framework/<branch>` to test a pushed branch instead.
The bootstrap takes the same thing as `--framework <flake-ref>`, and a
`path:` config ref to test an uncommitted config.

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
│   ├── home-base.nix      # Always applied: home-manager basics, zsh
│   └── home-checkouts.nix # framework.checkouts option
└── profiles/
    └── wsl.nix            # Opt-in as nixosModules.wsl
```
