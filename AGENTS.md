# Agent instructions

Read `README.md` first: it covers the bootstrap, the module interface and how
to test changes.

- The framework holds mechanisms only, never personal opinions. Package
  choices, identities and work settings belong in the consuming config repo.
- Never enable an app. Options for an app assert that the app itself is
  enabled (e.g. `programs.claude-code.enable`).
- Document in the module: a header comment (what and why), option
  descriptions and examples. The README doesn't describe modules or the file
  tree; it only holds stable content.
- Files that apps also write go through `framework.jsonFiles`, not
  home-manager's read-only symlinks.
- Keep file basenames unique across the repo.
- Naming follows nixpkgs: option names are camelCase (`framework.jsonFiles`),
  except a name that refers to a package, which keeps the package's attribute
  name (`framework.claude-code`, like `programs.claude-code`). File,
  directory and package names are kebab-case. A module's file is named after
  its option (`jsonFiles` → `json-files.nix`).
- Shell scripts go through `writeShellApplication`, so shellcheck runs at build
  time.
- A flake only sees git-tracked files: stage new files (`git add`, no commit)
  before building, or build through a `path:` ref.
- Test repeated activations, not just the first.
