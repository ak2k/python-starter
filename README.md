# python-starter

A starter template for new Python projects, optimized for agentic
development *and* modern Python best practices.

Philosophy: collapse the option space at the project level so an AI coding
agent (or any contributor) writes the same shape of code every time — the
TypeScript-strict experience for Python.

## Quick start

```bash
gh repo create my-project --template ak2k/python-starter --public --clone
cd my-project

# Rename the package (no cookiecutter ceremony — just sed)
rg -l myproject | xargs sed -i '' 's/myproject/your_pkg_name/g'  # macOS
# rg -l myproject | xargs sed -i 's/myproject/your_pkg_name/g'   # Linux
mv src/myproject src/your_pkg_name

# Install + verify
uv sync
make check
```

### Nix users

The repo ships a minimal `flake.nix` providing Python 3.13 + uv via `nix develop`.
Use it instead of system Python/uv if you want reproducibility:

```bash
nix develop           # Python + uv + make on PATH
make check            # identical to non-Nix path
```

direnv auto-activation: edit `.envrc` to uncomment `use flake`, then `direnv allow`.

uv remains the source of truth — `pyproject.toml` + `uv.lock` drive everything.
The flake just wraps the dev environment. To go further and *build the project
as a Nix derivation*, uncomment the `packages` block in `flake.nix` and follow
the [uv2nix docs](https://pyproject-nix.github.io/uv2nix/). Most projects don't
need this.

## What's in here

| File | Purpose |
|---|---|
| `pyproject.toml` | uv deps + ruff strict + basedpyright strict + pytest config — single source of truth |
| `AGENTS.md` | Contract for AI agents. Stack banlist + inner loop + divergence guide. |
| `CLAUDE.md` | Symlink → `AGENTS.md` (compat shim for tools that read CLAUDE.md only) |
| `Makefile` | `make check` = full inner loop. CI runs the same command. |
| `src/myproject/example_service.py` | Canonical service shape — copy for new services |
| `tests/test_example_service.py` | Canonical test shape — copy for new tests |
| `src/myproject/errors.py` | Domain error hierarchy |
| `.github/workflows/ci.yml` | CI runs `make check` |
| `flake.nix` + `.envrc` | Optional Nix dev shell (Python + uv); commented uv2nix block for project-as-derivation |

## Philosophy

One tool per concern, banned substitutes, strict types at the boundary,
canonical examples to pattern-match against. The contract lives in
[AGENTS.md](AGENTS.md) — including the "Appropriate divergence" section for
libraries / CLIs / scrapers / one-off scripts.

## Related work

- [Ranteck/PyStrict](https://github.com/Ranteck/PyStrict-strict-python) —
  strict-mode template that inspired the type-checker config here.
- [osprey-oss/cookiecutter-uv](https://github.com/osprey-oss/cookiecutter-uv) —
  heavier mainstream alternative (cookiecutter + extensive Jinja templating).
- [astral-sh/uv](https://github.com/astral-sh/uv),
  [astral-sh/ruff](https://github.com/astral-sh/ruff),
  [DetachHead/basedpyright](https://github.com/DetachHead/basedpyright) —
  upstream tools.

## License

MIT.
