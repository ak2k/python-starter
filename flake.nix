{
  description = "A new Python project (uv-managed; Nix dev shell + uv2nix build).";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs = {
        pyproject-nix.follows = "pyproject-nix";
        nixpkgs.follows = "nixpkgs";
      };
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs = {
        pyproject-nix.follows = "pyproject-nix";
        uv2nix.follows = "uv2nix";
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      pyproject-nix,
      uv2nix,
      pyproject-build-systems,
    }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};

      # Python interpreter follows pyproject.toml's `requires-python`: the
      # first PEP 440 spec is taken as the floor (handles `>=X.Y` and
      # `>=X.Y,<Z.W` shapes). Bump pyproject.toml — flake follows.
      project = pyproject-nix.lib.project.loadPyproject { projectRoot = ./.; };
      lowerBound = lib.head project.requires-python;
      pyAttr =
        "python"
        + toString (builtins.elemAt lowerBound.version.release 0)
        + toString (builtins.elemAt lowerBound.version.release 1);

      # uv.lock → Nix. Wheels preferred (faster, matches what `uv sync` resolves).
      # Switch to "sdist" if a dep ships a broken wheel and needs local build.
      workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
      overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };

      # Editable variant: project source resolved from $REPO_ROOT at shell
      # entry, not baked into the store. Source edits show up immediately;
      # uv.lock changes still require re-entering the shell.
      editableOverlay = workspace.mkEditablePyprojectOverlay { root = "$REPO_ROOT"; };

      pythonSets = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          python = pkgs.${pyAttr};
        in
        (pkgs.callPackage pyproject-nix.build.packages { inherit python; }).overrideScope (
          lib.composeManyExtensions [
            pyproject-build-systems.overlays.wheel
            overlay
          ]
        )
      );
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          python = pkgs.${pyAttr};

          # Editable pythonSet — only used by `.#pure`. Hatchling's
          # `build_editable` hook imports the `editables` package; inject it
          # as a build input here (not in the base set — production builds
          # don't need it).
          editablePythonSet = pythonSets.${system}.overrideScope (
            lib.composeManyExtensions [
              editableOverlay
              (final: prev: {
                myproject = prev.myproject.overrideAttrs (old: {
                  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ final.resolveBuildSystem { editables = [ ]; };
                });
              })
            ]
          );
          editableVenv = editablePythonSet.mkVirtualEnv "myproject-dev-env" workspace.deps.all;

          # Arm the tracked pre-push gate (.githooks/pre-push) on shell entry —
          # only when provably safe. core.hooksPath REPLACES .git/hooks wholesale
          # (it would silently disable git-lfs / pre-commit / husky hooks), so:
          # arm only inside a repo whose TRACKED tree carries our marker, with no
          # hooksPath convention at ANY scope and no existing hooks to disable;
          # otherwise print why plus the manual command. Style is load-bearing:
          # this runs in the USER'S shell (direnv sources it into zsh), where
          # `pipefail` turns a SIGPIPE'd `cmd | grep -q` probe into a guard
          # bypass and zsh does not word-split unquoted command variables — so
          # no short-circuiting pipelines, no `$cmd` indirection, and a probe
          # failure refuses rather than arms. Subshell keeps variables out of
          # the interactive shell. Bypass details in .githooks/pre-push.
          installHooks = ''
            (
              top=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
              # marker must be TRACKED and executable — a foreign repo that
              # happens to contain its own .githooks/pre-push is not ours
              git ls-files --error-unmatch -- .githooks/pre-push >/dev/null 2>&1 || exit 0
              [ -x "$top/.githooks/pre-push" ] || exit 0
              manual="git config --local core.hooksPath .githooks"
              armed=""
              current=$(git config --get core.hooksPath 2>/dev/null || true)  # any scope
              hooks_dir=$(git rev-parse --git-path hooks)
              if [ "$current" = ".githooks" ]; then
                armed=1
              elif [ -n "$current" ]; then
                origin=$(git config --show-origin --get core.hooksPath 2>/dev/null | cut -f1)
                echo "🪝 pre-push gate NOT armed: core.hooksPath is already '$current' ($origin) — to arm locally: $manual"
              elif ! existing=$(find "$hooks_dir" -maxdepth 1 \( -type f -o -type l \) ! -name '*.sample' -print -quit 2>/dev/null); then
                echo "🪝 pre-push gate NOT armed: could not inspect $hooks_dir — arm manually if appropriate: $manual"
              elif [ -n "$existing" ]; then
                echo "🪝 pre-push gate NOT armed: existing hook $existing would be disabled — to arm: $manual"
              elif git config --local core.hooksPath .githooks 2>/dev/null; then
                armed=1
              else
                echo "🪝 pre-push gate NOT armed: 'git config' write failed (read-only or locked .git/config?) — arm manually: $manual" >&2
              fi
              if [ -n "$armed" ]; then
                echo "🪝 pre-push gate: armed (bypass: git push --no-verify or MYPROJECT_SKIP_PREPUSH=1 git push)"
                # the --local write lives in the SHARED repo config: warn when
                # sibling worktrees would resolve hooks to a missing .githooks
                wt_count=$(git worktree list --porcelain 2>/dev/null | grep -c '^worktree ' || true)
                if [ "$wt_count" -gt 1 ]; then
                  echo "🪝 note: $wt_count worktrees share this hook config — a worktree whose branch lacks .githooks/pre-push has NO pre-push hook" >&2
                fi
              fi
            )
          '';
        in
        {
          # Default shell: uv-managed. Matches the inner loop (`make fix`/`check`)
          # without rebuilding the Nix venv on every dep tweak. `uv add` / `uv lock`
          # work natively; `uv sync` populates `.venv` on first entry.
          default = pkgs.mkShell {
            packages = [
              python
              pkgs.uv
              pkgs.gnumake
            ];

            # uv's bundled python-build-standalone won't link on NixOS;
            # force the Nix-managed interpreter. No-op on Darwin.
            shellHook = ''
              export UV_PYTHON=${python}/bin/python3
              export UV_PYTHON_PREFERENCE=only-system
              ${installHooks}
              echo "🐍 python: $(python3 --version)"
              echo "📦 uv:     $(uv --version)"
            '';
          };

          # Pure shell: uv2nix-built venv with the project installed editable.
          # No `.venv` needed. Source edits to src/myproject/ are live. Bumping
          # uv.lock requires exiting and re-entering so Nix re-resolves.
          # `uv lock --upgrade` works inside. Dep changes (`uv sync`, `uv add`,
          # `make install`) do NOT — the env is a read-only nix closure, so they
          # fail with a store-path permission error; use the default shell.
          pure = pkgs.mkShell {
            packages = [
              editableVenv
              pkgs.uv
              pkgs.gnumake
            ];
            env = {
              UV_NO_SYNC = "1";
              UV_PYTHON = "${editableVenv}/bin/python";
              UV_PYTHON_DOWNLOADS = "never";
              # `uv run` (incl. via make) uses the nix-built closure as the
              # project venv — never a stale `.venv` or an inherited
              # relocation path from the user's shell.
              UV_PROJECT_ENVIRONMENT = "${editableVenv}";
            };
            shellHook = ''
              unset PYTHONPATH
              export REPO_ROOT=$(git rev-parse --show-toplevel)
              ${installHooks}
              echo "🐍 python: $(python --version) (nix-built, editable)"
              echo "📦 uv:     $(uv --version)"
            '';
          };
        }
      );

      # `nix build .#default` produces a runtime venv (project + deps in
      # `[project.dependencies]`). `.#dev` adds `[dependency-groups].dev`
      # (basedpyright, ruff, pytest, ...). Both are Nix-built — no uv at
      # build time — suitable for nixpkgs PRs / NixOS modules / consumers.
      packages = forAllSystems (system: {
        default = pythonSets.${system}.mkVirtualEnv "myproject-env" workspace.deps.default;
        dev = pythonSets.${system}.mkVirtualEnv "myproject-dev-env" workspace.deps.all;
      });

      # `nix fmt` autoformats flake.nix to RFC-166 style.
      # Paired with checks.${system}.nixfmt below, which verifies it stayed formatted.
      formatter = forAllSystems (system: (pkgsFor system).nixfmt);

      # `nix flake check` runs these. `runCommand … touch $out` is the
      # idiomatic pass/fail pattern: tool exits non-zero → derivation fails.
      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          # Non-editable venv with ALL deps to run the suite inside the uv2nix
          # closure — what makes `nix flake check` a faithful gate: it catches
          # native-linking failures the wheels-based raw-uv path hides. NB this
          # does NOT typecheck; only `make check` runs basedpyright (the
          # pre-push hook runs both).
          testVenv = pythonSets.${system}.mkVirtualEnv "myproject-test-env" workspace.deps.all;
        in
        {
          statix = pkgs.runCommand "check-statix" { nativeBuildInputs = [ pkgs.statix ]; } ''
            statix check ${./flake.nix}
            touch $out
          '';
          nixfmt = pkgs.runCommand "check-nixfmt" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
            nixfmt --check ${./flake.nix}
            touch $out
          '';
          # The test suite run against `src/` inside the closure. `PYTHONPATH=src`
          # shadows the installed copy so coverage/fixtures resolve to the tree.
          # `${./.}` is the flake source — git-TRACKED files only; a new test
          # must be `git add`ed before this check can see it (matching CI).
          # NB darwin nix defaults to `sandbox = false`, so this check is
          # stricter on Linux CI than locally — a test that touches the network
          # or reads /etc can pass here and fail there.
          pytest = pkgs.runCommand "check-pytest" { nativeBuildInputs = [ testVenv ]; } ''
            cp -r ${./.} work && chmod -R +w work && cd work
            export HOME="$TMPDIR"
            export PYTHONPATH="$PWD/src"
            # The Linux sandbox has no system CA bundle; tests that construct an
            # httpx client (SSL context init, no network) need a cert file.
            export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            # --no-cov: `make check` owns the coverage gate; this check is
            # scoped to what only it can catch (native linking, lockfile drift).
            pytest --no-cov -p no:cacheprovider
            touch $out
          '';
        }
      );
    };
}
