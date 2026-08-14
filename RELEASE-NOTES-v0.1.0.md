# v0.1.0 — First release

LINACS — *Declarative Linux home environment management*. Write what you
want your machine to be in Lisp; LINACS knows how to make it so, idempotently.

> *"If only there were a Linux like Emacs. Configured in Lisp."*

## Added

### Core language
- Declarative home DSL: `define-home`, `use-feature`, and the `file`,
  `directory`, `symlink`, `package`, `secret`, `env-var`, `config-lines`,
  `config-ini`, `config-env`, and system-administration convenience forms
- Feature/provider model with a dependency graph, sub-feature composition,
  `:requires`/`:provides`, and strict provider selection (`:via`, `:default`,
  interactive `specify-provider` menu)
- Auto-probed **facts** with metadata, `declare-fact` for profile-only keys,
  and fact-prober conflict detection with no silent "first one wins"
- Action type registration with identity functions, dedup behavior
  (`:conflict`/`:additive`), and topological `:depends-on` ordering
- Idempotent state convergence — every executor probes current state and
  only changes what differs
- Provenance tracking for every action (feature/provider/facts snapshot)
- Pipeline hooks (`:after-resolve`, `:before-execute`) with no core changes

### Package management
- Package action with automatic **`:via` discovery** from a package
  preference chain (`:system`, `:pip`, `:npm`, `:flatpak`, `:toolbox`,
  `:podman`, `:appimage`)
- Registry for `:package :via` providers, plugin-extensible
- Package-manager **repository** support (configure a repo as a package
  prerequisite via catalog specifications)
- Per-action privilege escalation via `sudo` — LINACS itself never runs as
  root, and dotfiles in your own home never touch sudo
- `--platform` and `--provider` per-run overrides

### Extensibility
- Plugins auto-discovered via the ASDF `linacs-*` convention
- Stable `:linacs.api` interface for plugins and home projects
- `define-dsl-form` / `register-dsl-form` for own home-level forms
- Sudo helpers exported for plugin authors

### CLI
- Commands: `plan`, `apply`, `diff`, `validate`, `check`, `explain`,
  `graph`, `export`, `list`, `facts`, `doctor`, `init`, `version`
- Status labels `[v]`/`[x]`/`[~]`/`[!]` with color, action summary,
  spinner for long actions
- Dry-run (`-n`), `--continue`, verbosity levels, `--quiet`
- `init --example` scaffolding for a working `:shell` project

### Tests
- FiveAM test suite covering the pipeline, executors, DSL, features,
  CLI flag parsing, and providers

## Fixed
- Dry-run no longer attempts to delete applications
- `copy-file` handling corrected
- `service` and `config-lines` identity corrections
- `define-provider` silent failure; provider file-resolution consistency
- `apply` summary miscount / "nothing to do"
- Status alignment in `plan`/`explain`; facts alignment
- `config-ini`/catalog merge behavior
- Warning and error cleanup

## Other
- GPL-3.0 license
- User manual, README, and action-types documentation at
  `docs/user-manual.md`
