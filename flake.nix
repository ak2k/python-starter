{
  description = "A new Python project (uv-managed; Nix dev shell optional).";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, pyproject-nix }:
    let
      inherit (nixpkgs) lib;
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};

      # Single source of truth for Python version: pyproject.toml.
      # pyproject-nix parses `requires-python` as a list of PEP 440 specifiers.
      # We treat the first specifier as the lower bound (the conventional
      # `>=X.Y` form) and map it to `pkgs.pythonXX`. Bumping
      # `requires-python = ">=3.14"` automatically swaps `pkgs.python314`
      # into the shell. Multi-constraint forms like `>=3.13,<3.15` work too —
      # the first spec is used as the floor.
      project = pyproject-nix.lib.project.loadPyproject { projectRoot = ./.; };
      lowerBound = lib.head project.requires-python;
      pyAttr =
        "python"
        + toString (builtins.elemAt lowerBound.version.release 0)
        + toString (builtins.elemAt lowerBound.version.release 1);
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          python = pkgs.${pyAttr};
        in
        {
          default = pkgs.mkShell {
            packages = [
              python
              pkgs.uv
              pkgs.gnumake
            ];

            # On Linux (esp. NixOS), uv's default python-build-standalone
            # cpython is dynamically linked and won't run. Force uv to use
            # the Nix-managed interpreter. Harmless on Darwin.
            shellHook = ''
              export UV_PYTHON=${python}/bin/python3
              export UV_PYTHON_PREFERENCE=only-system
              echo "🐍 python: $(python3 --version)"
              echo "📦 uv:     $(uv --version)"
            '';
          };
        });

      # --- Optional: build the project as a Nix package via uv2nix ---
      # Uncomment + add `uv2nix` and `pyproject-build-systems` inputs when you
      # need `nix build` / `nix run` to produce a derivation (e.g., for nixpkgs
      # PRs, NixOS modules, home-manager). When you do, also add a
      # `nix build .#default` step to .github/workflows/ci.yml.
      # See: https://pyproject-nix.github.io/uv2nix/
      #
      # packages = forAllSystems (system: { default = ...; });
      # apps = forAllSystems (system: { default = ...; });
    };
}
