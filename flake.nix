{
  description = "A new Python project (uv-managed; Nix dev shell optional).";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      devShells = forAllSystems (system:
        let pkgs = pkgsFor system; in {
          default = pkgs.mkShell {
            packages = [
              pkgs.python313
              pkgs.uv
              pkgs.gnumake
            ];

            # On Linux (esp. NixOS), uv's default python-build-standalone
            # cpython is dynamically linked and won't run. Force uv to use
            # the Nix-managed interpreter. Harmless on Darwin.
            shellHook = ''
              export UV_PYTHON=${pkgs.python313}/bin/python3
              export UV_PYTHON_PREFERENCE=only-system
              echo "🐍 python: $(python3 --version)"
              echo "📦 uv:     $(uv --version)"
            '';
          };
        });

      # --- Optional: build the project as a Nix package via uv2nix ---
      # Uncomment + add `uv2nix`, `pyproject-nix`, and `pyproject-build-systems`
      # inputs when you need `nix build` / `nix run` to produce a derivation
      # (e.g., for nixpkgs PRs, NixOS modules, home-manager).
      # See: https://pyproject-nix.github.io/uv2nix/
      #
      # packages = forAllSystems (system: { default = ...; });
      # apps = forAllSystems (system: { default = ...; });
    };
}
