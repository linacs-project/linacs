# LINACS — Your Linux, the way you want it.
## Declared in Lisp. Applied everywhere.

> *"If only there were a Linux like Emacs. Configured in Lisp."*
> Now there is.

---

## What LINACS is for you

I am for the person who has three machines — a ThinkPad running Fedora, a tower on Arch, a Hetzner VPS on Debian — and is tired of keeping their dotfiles, packages, and services in sync across all three. You've tried shell scripts (they rot), Ansible (too heavy for one user), Nix (too much buy-in for a single-person setup), chezmoi (great for dotfiles, but doesn't install packages or enable services).

I am for the person who wants one file — one source of truth — that says: my editor is Emacs, my shell is Fish, my firewall is home-zone with SSH and mDNS, my GPG config is hardened, my Wayland variables are set, my SSH keys are provisioned, and I want to run me across every machine I own.

Not a flake. Not a derivation. Not a module. Just Lisp.

---

## How you use me

You write **what**. I know **how**.

```lisp
(define-home my-machine
  (use-feature :editor :via :emacs)
  (use-feature :security)
  (file "~/.gitconfig" :from "gitconfig.tmpl" :template t))
```

Package names, config paths, init systems, distro quirks — encoded in catalogs and providers, not in your home definition. You stay distro-agnostic without writing a single `if` for package managers.

```bash
linacs plan         # What will I do?
linacs diff         # What would change?
linacs apply        # Make it so
```

---

## A comparison, so you know where I fit

### Nix / Guix

Nix and Guix are **operating-system-scale** tools. They replace your package manager, your init system, your filesystem layout. The power is immense — purely functional, reproducible, rollbackable. The cost is also immense: a new language, their package set, often adopting the whole OS or nothing.

**I am not Nix.** I do not replace your package manager — I call it. I do not lock your filesystem into immutability — I converge toward a target state, idempotently. I do not require you to rebuild the world when you want to add a package.

**Where Nix and I agree:** declarative intent. You say *what*, not *how*.

**Where I differ:** I sit on top of your existing distribution. You keep `dnf`, `apt`, `pacman`. You keep `systemd`. You keep your distro's defaults. For immutable distros like Fedora Silverblue, I layer packages into a toolbox container instead of the host — I don't pretend your OS is something it's not.

**Where Nix wins:** hermetic reproducibility. My action executors are idempotent, but I don't have a purely functional store. If you need bit-for-bit identical environments and don't want the host OS to matter, Nix is the answer.

**Where I win:** incremental adoption. You don't adopt me overnight. Start with two features — `:editor`, `:git` — keep your shell scripts for the rest. Move more into your home definition over time. Point me at your existing dotfiles directory; I stow them as-is.

### chezmoi

[chezmoi](https://chezmoi.io) is the best dotfile manager in class. It handles one thing well: managing `~/.config`, `~/.bashrc`, `~/.gitconfig` across machines with templates and secrets.

**What I share with chezmoi:** you version-control your config, secrets come from external sources, files are applied to your home directory.

**Where chezmoi wins:** maturity, community, documentation. Its `diff`/`apply` workflow is battle-tested.

**Where I differ:** chezmoi stops at your home directory. I also install packages, enable services, configure firewalld zones, manage groups, set kernel parameters, write cron jobs — the things that live outside `~` but are still part of your machine's setup. When your editor feature needs to install `emacs` and enable `emacs.service`, I handle it in the same declaration.

**Where we overlap:** both apply dotfiles. If chezmoi works for you and you don't need the rest, use it. It's excellent at what it does.

### Shell scripts / Ansible / ...

Shell scripts work until they don't. Each new machine means another `if` branch. Ansible is for fleets of servers, not one user's workstation. Puppet, Salt — they assume an organization.

I am for one user with a handful of machines. You run me from your laptop, and I configure your laptop. No control plane. No agent. No YAML.

---

## How I work

I am a pipeline. Five steps, no magic:

```
┌─ Discovery ────  Auto-load plugins, your files, your home.lisp
├─ Facts ────────  Probe OS, GPU, display, laptop, YubiKey, ...
├─ Resolution ───  Walk feature graph, call providers, collect actions
├─ Dedup+Order ──  Resolve conflicts, topological sort
└─ Execution ────  Apply or check, one action at a time, idempotently
```

Every action is idempotent by construction. The package executor checks before it installs. The config-lines executor diffs before it writes. The service executor queries `systemctl is-active` before it starts. I don't need a state file — the system *is* the state.

---

## Stow is my backbone

You will add new applications to your home faster than I can ship providers for them. That is fine. I am built for this.

Drop any directory under `files/` in your home project, and I stow it onto your home directory with symlinks:

```
my-home/
├── home.lisp
└── files/
    ├── .config/          # Stows to ~/.config/
    │   ├── fish/
    │   └── sway/
    ├── .gitconfig.tmpl   # Stows to ~/.gitconfig
    └── scripts/           # Stows to ~/scripts/
        └── my-thing.sh
```

`files/` mirrors your home directory. Every file or directory in `files/` is symlinked into place by me. You version-control the whole thing. You edit in place — it's already symlinked back to your repo.

This is not an afterthought. Stow is a first-class action type (`:stow`) with its own executor — it handles folding, unfolding, and conflict resolution the same way GNU Stow does, natively in Lisp, no external binary required. Plugins use it too: the security plugin stows `files/gpg/` onto `~/.gnupg/` and `files/firewalld/` onto `/etc/firewalld/`.

**Most of your dotfile management will be stow.** Features and providers are for the things that need logic (package installation, service enablement, config generation). Everything else is a file in `files/`.

---

## A real example

Here is what a complete home definition looks like — not a toy, but something you'd actually write:

```lisp
(define-home jans-machine
  :traits (:prune-explicitly-disabled)

  ;; ─── Core ──────────────────────────────────────────────
  (use-feature :editor
    :via (if (fact :laptop-p) :emacs :vim))
  (use-feature :terminal
    :via (if (eq (fact :display-server) :wayland) :alacritty :rxvt))
  (use-feature :browser :via :firefox)
  (use-feature :security)           ;; umbrella: GPG + firewall

  ;; ─── Conditional on facts ─────────────────────────────
  (when (fact :laptop-p)
    (use-feature :power-management))

  (when (eq (fact :display-server) :wayland)
    (env-var "MOZ_ENABLE_WAYLAND" :value "1" :file "~/.profile")
    (env-var "QT_QPA_PLATFORM" :value "wayland" :file "~/.profile"))

  ;; ─── Dotfiles (stow-managed) ─────────────────────────
  (file "~/.gitconfig" :from "gitconfig.tmpl" :template t
    :secrets ((:signing-key :from :pass :path "git/signing-key")))
  (file "~/.config/starship.toml" :from "starship.toml")

  ;; ─── Secrets ─────────────────────────────────────────
  (directory "~/.ssh" :mode #o700)
  (secret "~/.ssh/id_ed25519" :from :pass :path "ssh/id_ed25519" :mode #o600)
  (file "~/.ssh/config" :from "ssh/config" :mode #o600)

  ;; ─── Removal ─────────────────────────────────────────
  (package "vim-tiny" :disabled t)
  (package "nano" :disabled t))
```

You check this into Git. Clone it on your new machine. Run `linacs apply`. Done.

---

## The stack

```
You                    ─  Home definition (Lisp DSL)
│
Features + Providers   ─  Community knowledge, your overrides
│
LINACS core            ─  Fact probing, resolution, ordering, execution
│
Action executors       ─  package, stow, copy-file, service, firewall-zone, ...
│
Your system            ─  Fedora, Arch, Debian, Ubuntu, Silverblue, ...
```

---

## Plugin ecosystem

I ship with a growing set of plugins, each in its own ASDF system, auto-discovered by name:

| Plugin | What it manages |
|--------|----------------|
| [linacs-fedora](../linacs-plugins/distributions/linacs-fedora/README.md) | Fact: rpm-ostree (Fedora Atomic); :toolbox, :flatpak facts moved to core |
| [linacs-kde-plasma](../linacs-plugins/desktops/linacs-kde-plasma/README.md) | KDE Plasma configuration via `kwriteconfig5` |
| [linacs-security](../linacs-plugins/tools/linacs-security/README.md) | GPG (default/hardened/YubiKey), firewalld (home/public/server) |

You write your own the same way. Drop a `linacs-*` ASDF system in your Quicklisp local-projects, or put a `.lisp` file in your home project's `providers/` directory. I discover it on next run.

---

## Philosophy, in a few lines

- **You declare intent; I encode knowledge.** You say `(use-feature :editor)`. I know that means a package, maybe a config directory, an environment variable.
- **Extend without forking.** New features, providers, catalogs, action types — all registered at load time. The core is deliberately small.
- **No DSL variables.** Facts replace them. Profiles override facts per machine. You never bind a variable in your home definition.
- **Mutable by default, immutable when needed.** `:via :toolbox` handles rpm-ostree via a toolbox/podman container, `:via :flatpak` handles Flatpak user-or-system scope, `:via :appimage` handles standalone executables. More backends can be added.
- **Idempotency lives in the executor, not in a lockfile.** Run me twice, get the same result. No diff against yesterday's snapshot.
- **No rollback.** Run me again. I converge. If an action fails, I tell you — I don't revert the ones that succeeded.

---

## Project layout

```
├── linacs/                     I am here — the core engine
│   ├── src/                    Resolution, execution, CLI
│   │   ├── action-types/       22 built-in executors
│   │   ├── pipeline.lisp       5-step pipeline
│   │   ├── cli.lisp            12 CLI commands
│   │   └── ...
│   └── docs/
│       ├── user-manual.md      Full user manual (I/you voice)
│       └── diagnostics-design.md
│
├── linacs-home/                Your home definition
│   ├── home.lisp               Your declaration
│   ├── files/                  Stow-managed dotfiles
│   ├── features/               Your feature overrides
│   ├── providers/              Your provider overrides
│   ├── catalogs/               Your package translations
│   └── plugins/                Symlinks to plugins
│
├── linacs-plugins/             Community plugins
│   ├── tools/linacs-security/  GPG + firewall
│   ├── distributions/          Fedora, Arch detection
│   └── desktops/               KDE Plasma, Sway, ...
│
└── AGENTS.md                   Complete specification (v1.0)
```

---

## CLI reference

```text
linacs <command> [options]
```

| Command | What it does |
|---------|-------------|
| `plan` | Show the resolved, ordered action list — what will happen |
| `apply` | Execute the ordered action list — make it so |
| `diff` | Show which actions would change something |
| `validate` | Check syntax only (balanced parens, valid forms) |
| `check` | Fully resolve configuration without executing anything |
| `explain` | Print the resolved feature graph and action order |
| `graph` | Print the abstract feature dependency DAG |
| `export` | Write the action list as a data s-expression |
| `list` | List registered features, providers, catalogs, action types |
| `facts` | Print resolved facts, after probing and profile merge |
| `doctor` | Diagnose the environment and provider coverage |
| `init` | Scaffold a new home project |
| `version` | Print the LINACS version |

| Option | Effect |
|--------|--------|
| `-C, --root DIR` | Project root (default `.`) |
| `-p, --platform NAME` | Target platform (default: auto-detect) |
| `--profile NAME` | Select a defined profile for fact overrides |
| `--provider T=P` | Prefer provider P for feature T |
| `-n, --dry-run` | Show changes without executing them |
| `--continue` | Keep going after a failed action |
| `-o, --output FILE` | Write output to FILE (for `export`) |
| `-v, --verbose` | Increase verbosity (repeat for debug) |
| `--quiet` | Only show errors |

## What you see when you run me

I tell you what I *will* do before I do it. Every action gets a status glyph so you know, at a glance, what's about to happen:

```
$ linacs plan
Resolved plan for JANS-MACHINE (traits: (PRUNE-EXPLICITLY-DISABLED)):
  STATUS  TYPE           TARGET
  ------  -------------  -----------------------
  [+]     package        GNUPG
  [!]     ensure-dir     ~/.gnupg/
  [!]     config-lines   ~/.gnupg/gpg.conf
  [!]     package        FIREWALLD
  [!]     service        firewalld
  [x]     package        vim-tiny
  [-]     package        nano

7 action(s): 1 to apply, 5 already present, 1 to remove, 1 disabled
[+] apply  [!] already present  [x] remove  [-] disabled
```

| Glyph | Meaning |
|-------|---------|
| `[+]` | Will be installed / created / started |
| `[!]` | Already in the desired state — skipped |
| `[x]` | Will be removed (explicitly disabled + prune trait) |
| `[-]` | Disabled but preserved (no prune trait — just skipped) |

When you want to understand *why* each action exists, add `-v`:

```
$ linacs explain -v
  #  STATUS  TYPE           TARGET                   PROVENANCE
  -  ------  -------------  -----------------------  ---------------------------------
  1  [+]     package        GNUPG                    SECURITY-GPG / GPG-HARDENED
  2  [!]     ensure-dir     ~/.gnupg/                SECURITY-GPG / GPG-HARDENED
  ...
```

Every action is tagged with its **feature** and **provider** — no mystery about where a package requirement came from. You see the full dependency chain from your home definition all the way down to what's about to change on disk.

---

## Where to go next

| What | Where |
|------|-------|
| **User manual** | [docs/user-manual.md](docs/user-manual.md) — getting started, mental model, references (1900+ words, I/you voice) |
| **Plugins overview** | [linacs-plugins/README.md](../linacs-plugins/README.md) |
| **Security plugin (GPG + firewall)** | [linacs-security/README.md](../linacs-plugins/tools/linacs-security/README.md) |

---

## Quick start

```bash
# Build me once
cd linacs
./build.sh

# Scaffold your home
mkdir my-home && cd my-home
linacs init

# Edit home.lisp, then:
linacs plan         # What will I do?
linacs diff         # What would change?
linacs apply        # Make it so

# On your next machine:
git clone git@github.com:you/my-home.git
linacs apply         # Same home, new machine
```

---

## For contributors

I am an open specification with an open implementation. The fastest way to extend me is to write a provider:

```bash
touch my-home/providers/my-cool-thing.lisp
```

```lisp
(in-package :linacs.core)
(define-provider :my-cool-thing :for :editor
  (lambda (facts)
    (list (list :action :package :target :my-cool-thing :via :system))))
```

I discover it automatically on next run. No Makefile edit. No registration step.

---

## License

MIT — LINACS Project
