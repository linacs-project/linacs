# Getting Started with LINACS

**Lisp Declarative Linux — Configuration Made Simple**

*Complete guide to installing, understanding, and using LINACS*

---

## Table of Contents

1. [Installing LINACS](#1-installing-linacs)
2. [Building Your First Home Project](#2-building-your-first-home-project)
3. [How LINACS Works - The Pipeline](#3-how-linacs-works---the-pipeline)
4. [How LINACS Is Built - Architecture](#4-how-linacs-is-built---architecture)
5. [Complete Reference](#5-complete-reference)

---

## 1. Installing LINACS

*Part of the Getting Started guide — from the original manual*

Hello. I'm LINACS — Lisp Declarative Linux — and this is the manual I wish
someone had handed you on day one. I'm going to talk to you directly
through this whole manual: when I say "I", I mean the tool you're about
to install; when I say "you", I mean the person about to describe their
Linux home directory to me for the first time.

This part gets you from nothing installed to a real `linacs apply` doing
something on your machine. The other parts are the mental model,
the internals, and the exhaustive reference — you won't need any of them
to finish this one.

### 1.1 Installing me

You need [SBCL](http://www.sbcl.org/) on your `PATH` — nothing else. I
depend only on `asdf` and `uiop`, both bundled with SBCL, so there's no
Quicklisp step and nothing else to pull down.

From the project root, run `build.sh`:

```sh
./build.sh
```

which does exactly this:

```sh
# Most clean installations or new users do have a local bin.
mkdir -p ~/.local/bin/

# Build linacs and store it there.
sbcl \
  --non-interactive \
  --eval '(require :asdf)' \
  --eval '(push #P"./" asdf:*central-registry*)' \
  --eval '(asdf:load-system :linacs :force t)' \
  --eval '(sb-ext:save-lisp-and-die
             "linacs"
             :executable t
             :toplevel
             (lambda ()
               (linacs.core:main (rest sb-ext:*posix-argv*))))' \
&& ln -sf "$PWD/linacs" ~/.local/bin/linacs

# Show linacs's own help, to confirm it worked.
clear
linacs
```

A minute later you have a real, standalone `linacs` executable — no Lisp
image to keep around, no `asdf:load-system` step at runtime — symlinked
into `~/.local/bin`. If nothing prints when you just type `linacs` in a new
shell, make sure `~/.local/bin` is actually on your `PATH` (most distros
add it by default for a login shell; if yours doesn't, add
`export PATH="$HOME/.local/bin:$PATH"` to your shell's rc file).

Confirm it:

```sh
linacs version
linacs --help
```

---

## 2. Building Your First Home Project

Let's actually do this.

### 2.1 Step 1 — scaffold

```sh
linacs init -C ~/my-home
```

I'll create:

```
~/my-home/
├── home.lisp
├── profiles/
├── features/
├── providers/
├── catalogs/
├── templates/
├── hooks/
└── files/
```

`home.lisp` starts out about as small as it can be:

```lisp
(define-home my-home
  :traits (:prune-explicitly-disabled))
```

Everything else is empty. That's fine — an empty home is a valid home,
it just doesn't do anything yet.

### 2.2 Step 2 — decide what "shell" means to you

Say you want me to manage your shell. First, tell me it's a *capability*
that exists, in `features/shell.lisp`:

```lisp
(in-package :linacs.core)

(define-feature :shell
  :description "Login shell and dotfiles"
  :requires nil)
```

Then tell me *how* to provide it, in `providers/shell.lisp` (or in the
same file — I don't care which of the six directories a registration form
lives in, as long as it's one of them):

```lisp
(in-package :linacs.core)

(define-provider :bash :for :shell
  (lambda (facts)
    (declare (ignore facts))
    (list
      '(:action :package :target :bash :via :system)
      '(:action :copy-file :to "~/.bashrc" :from "bashrc"))))
```

Drop your actual `.bashrc` content at `files/bashrc` — this is where
every `:from "..."` path in a convenience form resolves, always relative
to `files/` under your project root, never the project root itself.

### 2.3 Step 3 — teach me your distro's package names

`:target :bash` above is a canonical name, not necessarily a real package
name. Some distros call it something else. Tell me the mapping in
`catalogs/packages.lisp`:

```lisp
(in-package :linacs.core)

(define-catalog :packages
  (:bash (:fedora . "bash") (:ubuntu . "bash") (:arch . "bash")))
```

If I ever hit a canonical name that isn't in the catalog, I don't fail —
I just fall back to using the keyword's name as-is (`:bash` → `"bash"`),
so starting without a catalog entry for every single package is fine.

### 2.4 Step 4 — wire it into your home

```lisp
;; home.lisp
(define-home my-home
  :traits (:prune-explicitly-disabled)
  (use-feature :shell))
```

Since there's only one provider registered for `:shell` (`:bash`), I'll
use it automatically. Try it:

```sh
linacs plan -C ~/my-home
```

You should see something like:

```
Resolved plan for MY-HOME:
  PACKAGE bash
  COPY-FILE ~/.bashrc
2 action(s).
```

Nothing has touched your filesystem yet — `plan` always runs in check
mode. When you're happy:

```sh
linacs apply -C ~/my-home
```

Don't put `sudo` in front of that. Every action that genuinely needs
root (installing that `bash` package, for instance) escalates on its own
for just that one step and may prompt you for your password right then —
running the whole thing under `sudo` instead would reset `~` to root's
home directory and isn't needed for anything linacs does.

### 2.5 Step 5 — add a second machine

Say you also want zsh at work. Add a second provider:

```lisp
;; providers/shell.lisp, appended
(define-provider :zsh :for :shell
  (lambda (facts)
    (declare (ignore facts))
    (list
      '(:action :package :target :zsh :via :system)
      '(:action :copy-file :to "~/.zshrc" :from "zshrc"))))
```

Now there are two providers for `:shell`, so I need you to pick one. Do it
with a Fact instead of hard-coding it:

```lisp
;; profiles/machines.lisp
(define-profile :work    '((:work-p . t)))
(define-profile :personal '((:work-p . nil)))
```

```lisp
;; home.lisp
(use-feature :shell :via (if (fact :work-p) :zsh :bash))
```

```sh
linacs plan -C ~/my-home --profile work      # -> zsh
linacs plan -C ~/my-home --profile personal  # -> bash
```

Same `home.lisp`, different outcome, purely from the Fact.

### 2.6 Step 6 — check before you trust

Two commands exist specifically so you never have to find out about a
mistake via `apply`:

```sh
linacs validate -C ~/my-home   # are the s-expressions even well-formed?
linacs check    -C ~/my-home --profile work   # does everything actually resolve?
```

`validate` catches unbalanced parens before anything else runs, even if a
plugin fails to load. `check` runs the whole resolution pipeline (steps
0–4) and stops before step 5, so you find out about a missing provider, a
conflicting action, or a dependency cycle without any risk to your system.

That's the whole loop. Everything past this point in the manual is
reference material for when you want to do something more specific:
secrets, templates, removal, cross-action dependencies, pipeline hooks,
and so on.

---

## 3. How LINACS Works - The Pipeline

This is the mental model: Facts, Profiles, Features, Providers, Catalogs,
Actions, and the five-step pipeline that ties them together. If you read
nothing else in this manual, read this part — everything else is detail
on top of what's here.

### 3.1 The pipeline, in order

Every time you run me — `linacs plan`, `linacs apply`, `linacs check`, whatever —
I do the same five things, in the same order, preceded by a discovery pass:

```
0. Discover   -- find and load your project's .lisp files, and any
                  third-party linacs-* plugins
1. Probe      -- figure out facts about this machine, then apply your
                  chosen --profile on top
2. Resolve    -- walk your use-feature calls, find the right provider
                  for each, run each provider, collect every action
                  (yours and the providers')
3. Deduplicate -- if two actions want to touch the same thing, decide
                  which one wins (or complain, if I can't tell)
4. Order      -- sort the surviving actions so dependencies run first
5. Execute    -- run each action's executor, in order
```

I want to walk through each of these once, slowly, because understanding
this order will save you a lot of head-scratching later.

### 3.2 Step 0: Discovery

Before I know anything about your machine, I go looking for code. I look
for two kinds:

- **Your project's own files.** I have six subdirectories I always check:
  `profiles/`, `features/`, `providers/`, `catalogs/`, `templates/`,
  `hooks/`. Any `.lisp` file in any of them, at any depth, gets loaded —
  alphabetically, so you can control ordering within a directory just by
  naming files `00-first.lisp`, `01-second.lisp` if you ever need to. Then,
  last of all, I load `home.lisp` from your project root.
- **Third-party plugins.** Any ASDF system whose name starts with `linacs-`
  gets loaded too, before your own files, so your project can build on top
  of whatever a plugin registers.

Nobody writes a manifest file listing what to load. You just drop a
`.lisp` file in the right directory and I'll find it next time you run me.

One thing that trips people up: **`home.lisp` is loaded, but not run,**
during discovery. Your `define-home` body only actually executes later, in
step 2, once I know real facts about the machine. I'll explain why in a
moment — it's the reason `(when (fact :laptop-p) ...)` works at all.

### 3.3 Step 1: Facts and Profiles

A **Fact** is something true about the machine you're running on:
`:os`, `:hostname`, `:laptop-p`, `:display-server`, a couple of dozen
more built-in ones covering things like GPU vendor, wifi/bluetooth
presence, RAM, and CPU architecture (see §5.14 for the full list and
exactly how each is probed), plus anything else a provider author decides
to add (a custom `:codename` fact, say). I
gather these automatically, once, at the start of every run. You read
them with `(fact :key)`.

A **Profile** is a named override list you select with `--profile`. It
doesn't replace fact-probing — it runs *after* it, and just overwrites
whichever keys it mentions. This is how one `home.lisp` describes your
laptop, your desktop, and your server: the facts differ, the file doesn't.

```lisp
(define-profile :laptop
  '((:hostname . "thinkpad") (:gpu . :nvidia) (:laptop-p . t)))
```

Once probing + profile merging is done, I hand you a flat plist of facts.
`(fact :key)` is the only way you ever read one. There's no way to tell,
from inside your `home.lisp`, whether a value came from a prober or a
profile — and that's deliberate. It keeps the language simple: you never
have to reason about layers, only about the final value.

### 3.4 Step 2: Resolving the feature graph

This is where your `home.lisp` body actually runs. I already have facts;
now I execute your `define-home` form top to bottom, exactly like ordinary
Common Lisp code — because that's exactly what it is. `when`, `unless`,
`if`, `cond`, `and`, `or` — I don't reinvent any of these. If you can write
it as a standard Lisp conditional over `(fact ...)`, it works.

Every `(use-feature :something ...)` you write gets queued up. Once your
whole body has run, I:

1. Take every feature name you asked for, and recursively pull in whatever
   they `:requires`, building a dependency-ordered list.
2. For each feature, pick the right **Provider**. If you said
   `:via :emacs`, I use the provider registered under that name. If you
   didn't say `:via` and there's exactly one provider registered for that
   feature, I use it automatically. If there's more than one and you
   didn't disambiguate, I stop and tell you.
3. Call each selected provider with the current facts. A provider is just
   a function from facts to a list of actions — nothing more. It can
   return a fixed list, or compute one; I don't care which.
4. Collect everything: the actions your providers returned, plus every
   `file`, `package`, `secret`, ... form you wrote directly in
   `define-home`.

### 3.5 Step 3: Deduplication

Now I might have two actions that both want to manage
`~/.gitconfig` — say, a provider ships a default one, and you also wrote
`(file "~/.gitconfig" :from "gitconfig")` yourself because you wanted
something different. I resolve this by **identity** and **priority**:

- Every action has an identity — usually just its type plus its target,
  like `(:copy-file . "~/.gitconfig")`.
- Things you wrote directly in `define-home` outrank things a provider
  returned.
- If two actions of the *same* priority claim the same identity with
  *different* content, I stop and ask you to sort it out — I never
  silently merge or guess.
- You can force a specific action to win outright with `:force t`,
  regardless of priority.

### 3.6 Step 4: Ordering

I sort what's left into an execution order. Mostly that's just the order
things appeared, but if you wrote `:depends-on` on an action, I make sure
its dependency runs first. I do one topological pass over the whole set —
if you've built a cycle, I'll tell you exactly which actions are involved.

### 3.7 Step 5: Execution

Finally, I run each action's executor, one at a time, in that order.
Every executor understands three modes:

- **`:apply`** — actually change the system.
- **`:check`** — tell me what *would* change, and touch nothing. This is
  what powers `linacs plan`, `linacs check`, `linacs diff`, and `--dry-run`.
- **`:remove`** — undo the action. This only ever runs when you've marked
  an action `:disabled t` *and* your home has the
  `:prune-explicitly-disabled` trait — deletion is always something you
  opt into, never a side effect.

Every built-in executor is written to be **idempotent**: running it twice
produces the same result as running it once. I don't keep a separate
"what did I do last time" state file to diff against — each executor
simply checks the real system and only acts if something's actually wrong.
That also means there's no rollback. If something fails partway through, I
stop, tell you exactly what broke, and you fix it and run me again. I
converge you toward the goal; I don't try to undo history.

### 3.8 Why the ordering (0→1→2) actually matters

Here's the thing that confuses almost everyone once: `home.lisp` gets
*loaded* in step 0, before facts exist, but its body only *runs* in step 2,
after facts exist. That's because `define-home` doesn't evaluate its body
immediately — it wraps it up and hands it to me to run later. So this is
completely safe, even though it looks like it shouldn't be:

```lisp
;; home.lisp -- loaded in step 0, when no facts exist yet
(define-home my-home
  (when (fact :laptop-p)          ; not evaluated until step 2
    (use-feature :power-management)))
```

By the time that `when` actually runs, I've already probed facts and
merged your profile. You never have to think about this consciously —
just know that if you see `home.lisp` being *loaded* early in verbose
output, that's normal, and it's not a bug.

### 3.9 What I will never ask you to do

- **No variables.** You never bind or `setf` anything in the DSL. State
  comes from Facts (and Profiles), full stop.
- **No custom control flow.** `when`/`unless`/`if`/`cond` and friends are
  the entire vocabulary. I don't add a `linacs-if` or a `linacs-loop`.
- **No silent deletion.** I only ever remove something you explicitly
  marked `:disabled t`, and only if your home opted into
  `:prune-explicitly-disabled`.
- **No rollback.** I converge forward. Re-running me is always safe and
  is always the answer when something goes wrong mid-run.

---

## 4. How LINACS Is Built - Architecture

The first parts of this manual are about *using* me to describe a
Linux home environment. This part is different: it's for you if you want
to understand my own source, extend me with a new action type, or just
know why a file lives where it lives before you go digging through it.
If you only ever plan to write `home.lisp` files, you can skip this part
entirely and come back if curiosity strikes.

### 4.1 Source layout

```
linacs/
├── linacs.asd                 # Explicit ASDF :components list
├── src/
│   ├── package.lisp         # The three packages: :linacs.core, :linacs.log, :linacs-templates
│   ├── conditions.lisp      # Every condition class + restart vocabulary
│   ├── log.lisp             # Leveled logging
│   ├── discovery.lisp       # Step 0: directory + ASDF-plugin discovery
│   ├── facts.lisp           # Fact prober registration/probing
│   ├── profiles.lisp        # Named fact-override sets
│   ├── catalogs.lisp        # Canonical name -> distro-string tables
│   ├── features.lisp        # Feature DAG + resolution
│   ├── providers.lisp       # Provider registration/selection
│   ├── actions.lisp         # Identity, dedup, ordering, dispatch
│   ├── secrets.lisp         # :pass/:vault/:file/:prompt resolution
│   ├── templates.lisp       # RENDER-* discovery
│   ├── action-types/        # One file per built-in executor
│   ├── pipeline.lisp        # The five-step Execution Model + hooks
│   ├── privilege.lisp       # Privilege preflight for apply
│   ├── dsl.lisp             # define-home + convenience macros
│   └── cli.lisp             # Argument parsing + dispatch
└── docs/                    # This manual, the spec, and guides
```

Every file starts with a header describing exactly what it does and how
to use it — that header is the fastest way to orient yourself in any
single file, faster than reading this section again.

### 4.2 The package split

Three packages, one job each:

- **`:linacs.core`** — everything: the DSL, the pipeline, every built-in
  action executor, the CLI. This is where you'll spend nearly all your
  time if you're extending me.
- **`:linacs.log`** — a small leveled-logging facility (`info`, `debug*`,
  `warn*`, `error*`), kept separate so providers and executors can log
  without depending on the rest of the core.
- **`:linacs-templates`** — deliberately empty by default. A home project's
  own `templates/*.lisp` files add `RENDER-*` functions here; I never
  define anything in it myself.

Two symbols are worth knowing about early: `:linacs.core` shadows
`cl:package` and `cl:directory`, because the home-definition DSL wants
`package` and `directory` as macro names. If you're working inside
`:linacs.core` and reach for the standard Lisp functions of those names,
you'll get my macros instead — use `cl:directory`/`cl:package` explicitly
if you ever need the originals.

### 4.3 The registries

I don't keep a database. Every piece of registered knowledge — every
feature, provider, catalog, fact prober, pipeline hook, and action type —
lives in a plain hash table, held in a special variable:

| Variable | Populated by | Cleared on every `bootstrap`? |
|---|---|---|
| `*feature-registry*` | `define-feature` | Yes |
| `*providers*` | `define-provider` | Yes |
| `*catalogs*` | `define-catalog` / `register-catalog` | Yes |
| `*fact-probers*` | `register-fact-prober` | Yes |
| `*pipeline-hooks*` | `register-pipeline-hook` | Yes |
| `*profiles*` | `define-profile` | Yes |
| `*action-types*` | `register-action-type` | **No** |
| `*action-type-descriptions*` | `register-action-type :description` | **No** |

The first six are populated by **Discovery** (a home project's own
`.lisp` files, loaded fresh on every single command) and are cleared at
the start of every `bootstrap` call specifically so that running more
than one command in a long-lived Lisp image — a REPL, a saved image used
interactively — never silently accumulates stale or duplicate
registrations. A fresh per-invocation process never would have noticed
the difference; a persistent one does, and did, until this was fixed.

The last two are populated once, when the `:linacs` system itself loads
(each `action-types/*.lisp` file registers its own type at the top
level), and never touched by Discovery — they're part of *me*, not part
of any project, so clearing them on every command would just break
every action type after the first call.

### 4.4 The condition system

Every error path uses a real CLOS condition class from `conditions.lisp`,
not a bare `(error "some string")`. Two conditions go further than that
and carry genuine, named, invokable restarts:

- `action-conflict` offers `USE-FIRST`/`USE-SECOND`.
- `missing-provider` (the ambiguous-multiple-providers case) offers
  `SPECIFY-PROVIDER` (with an `:interactive` clause, so a live debugger
  prompts you for a name) and `SKIP-FEATURE`.

Everything an action executor itself raises is wrapped, at the point of
execution, in `RETRY`/`SKIP`/`ABORT-PROCESSING`. The compiled CLI catches
all of this in one place (`src/cli.lisp`'s `WITH-CLI-ERROR-REPORT`) and
turns it into a one-line message; a live REPL sees the real condition and
its real restarts instead. See §5.14 for exactly how to
get the latter.

### 4.5 Why the core isn't auto-discovered

A home project's `features/`, `providers/`, `catalogs/`, and so on are
loaded automatically — that's the entire point of Discovery. My own
`src/` is not: `linacs.asd` lists every file explicitly, in dependency
order, with `:serial t`. This isn't an oversight; Discovery is
*implemented* in `src/discovery.lisp`, and a system can't bootstrap
itself via a mechanism it hasn't loaded yet. So my own layout is ordinary
ASDF, and a home project's layout is the directory convention Discovery
provides — two different things, on purpose.

### 4.6 Extension points, summarized

If you're writing a feature for a project (not modifying me), you almost
certainly want `docs/how-to-feature.md` instead of this section — it's a
complete, example-driven guide. This is just the map of what's
extensible and where it's registered:

| To add | Call | Where it typically lives |
|---|---|---|
| A capability | `define-feature` | a project's `features/*.lisp` |
| An implementation of a capability | `define-provider` | a project's `providers/*.lisp` |
| A distro package-name mapping | `register-catalog` | a project's `catalogs/*.lisp` |
| A new probed fact | `register-fact-prober` | a project's `providers/*.lisp` |
| Cross-cutting behavior (audit logging, a confirmation prompt) | `register-pipeline-hook` | a project's `hooks/*.lisp` |
| A new `:via` handler for the `:package` action type | `register-package-via-handler` | a plugin, or a project's `providers/*.lisp` |
| A template renderer | a `RENDER-*` function | a project's `templates/*.lisp` |
| **A genuinely new action type** (rare — `:command` covers most cases) | `register-action-type` | a plugin, or a change to `src/action-types/` if it belongs in the core |

The last two are the extension points that touch me rather than a project.
A new action type is a function of `(action &key mode)` handling
`:apply`/`:check`/`:remove`, plus one `register-action-type` call with a
`:description`. A new `:via` handler for `:package` is a function of
`(action name &key mode)` where `name` is already resolved to a string,
plus one `register-package-via-handler` call — for example, the
`linacs-fedora` plugin registers `:toolbox` and `:rpm-ostree` handlers so
`(package :ripgrep :via :toolbox)` works transparently. Look at any file
in `src/action-types/` as a template for a full action type;
`command.lisp` is the simplest complete example.

---

## 5. Complete Reference

Every keyword, every option, every variation, each with a runnable
snippet. This is the part you'll come back to.

### 5.1 `define-home`

The root of your project. Exactly one per project.

```lisp
(define-home my-home
  :traits (:prune-explicitly-disabled)
  ...)
```

- `:traits` is optional. Right now I ship exactly one trait,
  `:prune-explicitly-disabled` — without it, `:disabled t` actions are
  simply never run at all (not applied, not removed); with it, they're run
  in `:remove` mode.
- Without `:traits` at all:

  ```lisp
  (define-home my-home
    (use-feature :editor :via :emacs))
  ```

- `(package-preference :toolbox :flatpak :system)` sets the global
  auto-selection chain for packages that don't specify `:via` explicitly.
  See §5.7 for details.

Everything else inside the body is one of the forms below, or a standard
Lisp conditional wrapping them.

### 5.2 `use-feature`

Pulls a Feature into your home and (optionally) picks a Provider for it.

**Plain — let me auto-select the provider** (only works if exactly one is
registered):

```lisp
(use-feature :version-control)
```

**Explicit provider:**

```lisp
(use-feature :editor :via :emacs)
```

**Computed provider — any Lisp conditional over facts:**

```lisp
(use-feature :editor :via (if (fact :work-p) :emacs :vim))

(use-feature :editor
  :via (cond
         ((and (fact :work-p) (fact :laptop-p)) :emacs)
         ((fact :work-p) :vscode)
         (t :vim)))
```

**With an explicit ordering dependency** (rare — most ordering is handled
by feature `:requires`, not this):

```lisp
(use-feature :editor :via :emacs :depends-on ((:package :system . "emacs")))
```

**Wrapped in a conditional** (this is just ordinary Lisp — `use-feature`
doesn't have its own conditional form):

```lisp
(when (fact :laptop-p)
  (use-feature :power-management))

(unless (fact :work-p)
  (use-feature :gaming)
  (use-feature :media))
```

### 5.3 `file`

Copies (or renders) a file to a target path. Expands to a `:copy-file`
action.

**Plain:**

```lisp
(file "~/.gitconfig" :from "gitconfig"))
```

**With mode / owner / group:**

```lisp
(file "~/.ssh/config" :from "ssh/config" :mode #o600)

(file "/etc/X11/xorg.conf.d/10-nvidia.conf"
      :from "nvidia/10-nvidia.conf"
      :mode #o644 :owner "root" :group "root")
```

If you omit `:owner`/`:group`, I default them to *you* — the user who
invoked `linacs`, even under `sudo`, never `root`. For anything under a
system path that genuinely needs `root:root`, set it explicitly, as above.

**With an explicit dependency:**

```lisp
(file "~/.config/starship.toml"
      :from "starship.toml"
      :depends-on ((:package :system . "starship")))
```

**Forcing a conflict win:**

```lisp
(file "~/.gitconfig" :from "gitconfig" :force t))
```

**Templated** (see §5.22 for the renderer side):

```lisp
(file "~/.gitconfig" :from "gitconfig.tmpl" :template t)

;; or with an explicit renderer function instead of by-convention lookup
(file "~/.gitconfig" :from "gitconfig.tmpl" :renderer #'render-gitconfig)
```

**Templated with secrets threaded in as keyword arguments:**

```lisp
(file "~/.config/gh/hosts.yml"
      :from "gh-hosts.tmpl" :template t
      :secrets ((:token :from :pass :path "github/token")))
```

### 5.4 `directory`

Ensures a directory exists with the right mode. Expands to `:ensure-dir`.

```lisp
(directory "~/.ssh" :mode #o700)

(directory "~/.config/emacs" :mode #o755)

;; system path needing non-default ownership
(directory "/etc/X11/xorg.conf.d" :mode #o755 :owner "root" :group "root")
```

### 5.5 `symlink`

Applies `ln -sf` semantics. Expands to `:symlink`.

```lisp
(symlink "~/.emacs.d" :to "~/.config/emacs"))
```

### 5.6 `stow`

`(stow "fish")` mirrors `files/fish/**` onto a target root (default `~`),
GNU-Stow style — no dependency on the `stow` binary itself. It folds a
whole directory into a single symlink when nothing exists at the target
yet, and falls back to merging file-by-file when the target already
exists for real, recursing as deep as it needs to:

```lisp
;; files/fish/.config/fish/config.fish -> ~/.config/fish/config.fish
;; (folds the highest untaken directory -- if ~/.config doesn't exist
;; either, ~/.config itself becomes the symlink, not just ~/.config/fish)
(stow "fish")
```

**A different target root than `~`:**

```lisp
(stow "skel-fish" :to "/etc/skel"))
```

**Source directory name different from the package's identity** (rarely
needed — mostly for when two profiles want different variants of the
same logical package):

```lisp
(stow "fish-work" :from "fish"))
```

If two `stow` calls' packages both reach into the same subdirectory —
say, `fish` and `starship` both touch `~/.config` — the first one to run
folds `~/.config` into a single symlink; the second one *unfolds* it back
into a real directory containing both packages' files individually,
exactly like real GNU Stow does when two packages' trees overlap. You
never have to think about ordering these by hand.

**Marked for removal** (only acted on with `:prune-explicitly-disabled`):
removes exactly the symlinks this package created, then prunes any
directory left empty by that removal — but never anything that still
has unrelated content in it, and never the target root itself:

```lisp
(stow "fish" :disabled t))
```

An existing *real* file or an unrelated symlink blocking a path this
package needs is a conflict, reported clearly rather than silently
overwritten — same as real stow's own safety behavior.

### 5.7 `package`

Declares a package should be installed (or, with `:disabled t`,
uninstalled once pruned). Expands to `:package`, defaulting `:via` to
`:system`.

**Plain (goes through your catalog + system package manager):**

```lisp
(package "vim"))
```

**Via a language-specific manager instead of the system one:**

```lisp
(package "black" :via :pip)
(package "typescript" :via :npm)
```

**Via Flatpak.** Flatpak app IDs are already the same across every
distro, so unlike `:via :system`, this never consults your catalog — the
string you give is used exactly as written. Give it as a **string, not a
keyword** — app IDs are case-sensitive (`"org.videolan.VLC"` really does
have a capital `VLC`), and a bare keyword would get uppercased by the
Lisp reader and silently stop matching:

```lisp
(package "org.videolan.VLC" :via :flatpak))
```

By default this installs system-wide (`:scope :system`, needs root, like
any other `:via :system` package) from the `flathub` remote, adding that
remote automatically if it isn't configured yet. Both are overridable:

```lisp
;; install into your own home directory instead -- never needs root,
;; and I never run this one under sudo even if you invoked linacs that way
(package "com.spotify.Client" :via :flatpak :scope :user)

;; a non-default remote needs its URL, since I can't guess a third-party
;; remote's location the way I can flathub's
(package "com.example.App" :via :flatpak :remote "my-remote" :remote-url "https://example.com/repo")
```

A plan containing only `:scope :user` Flatpak installs never triggers the
"needs root" preflight check that a `:system`-scope package would — I
only ask for privileges I actually intend to use.

**Plugin-provided `:via` options.** Plugins can register new `:via`
handlers for the `:package` action using `register-package-via-handler`.
For example, the `linacs-fedora` plugin adds `:via :toolbox` and
`:via :rpm-ostree`:

```lisp
(package :ripgrep :via :toolbox)
(package :docker :via :rpm-ostree)
```

These work exactly like the built-in `:via` options — the same
idempotency, the same `:disabled t` removal semantics, the same
dependencies. No core changes needed; just load the plugin and use the
keyword.

**Auto-selection with `package-preference`.** When you omit `:via`
from a `(package ...)` form, I pick the best method automatically
based on a global chain you declare once in `define-home`:

```lisp
(define-home my-home
  (package-preference :toolbox :flatpak :system)
  (package :ripgrep)                ;; picks :toolbox if available
  (package :emacs)                  ;; then :flatpak
  (package "org.videolan.VLC")      ;; then :system
  ...)
```

I walk the chain in order and use the first method whose
corresponding fact is true (`:toolbox` → `(fact :toolbox-p)`).
`:system` is always available. If nothing in the chain is
available, I warn and fall back to `:system`.

You can still write an explicit `:via` to bypass auto-selection
for a single package:

```lisp
(package :emacs :via :flatpak)         ;; always flatpak, no matter the chain
```

Provider-authors can attach a `:via-preference` key to individual
actions to override the global chain for that specific package,
while still allowing the executor to auto-select among the listed
methods:

```lisp
(:action :package :target :firewalld
         :via-preference (:toolbox :system))
```

**Marked for removal:**

```lisp
(package "vim-tiny" :disabled t)
(package "nano" :disabled t))
```

Remember: removal only actually *happens* if your home has the
`:prune-explicitly-disabled` trait. Without it, this line is inert —
useful if you want to document intent before you're ready to act on it.

### 5.8 `secret`

Writes a secret value to a target file. Expands to `:secret`. The value
is fetched fresh, immediately before the file is written, and never
persisted anywhere in plaintext along the way.

**From the `pass` password manager:**

```lisp
(secret "~/.ssh/id_ed25519" :from :pass :path "ssh/id_ed25519"))
```

**From HashiCorp Vault:**

```lisp
(secret "~/.config/app/db-password" :from :vault :path "secret/data/db#password"))
```

**From another file on disk:**

```lisp
(secret "~/.config/app/license" :from :file :path "/mnt/private/license.txt"))
```

**Interactively prompted:**

```lisp
(secret "~/.config/app/api-key"
        :from :prompt
        :message "Enter API key for app: "))
```

If I'm running somewhere with no attached terminal (CI, a script, a cron
job) and I hit a `:prompt` secret, I won't hang waiting for input — I'll
stop and tell you there's no interactive terminal available, with the
option to supply the value programmatically, skip, or abort.

**With explicit mode:**

```lisp
(secret "~/.ssh/id_ed25519" :from :pass :path "ssh/id_ed25519" :mode #o600))
```

### 5.9 `env-var`

Ensures a single `export KEY="value"` line exists in a target file.
Expands to `:env-var`.

```lisp
(env-var "EDITOR" :value "emacs" :file "~/.profile"))
```

### 5.10 `config-lines`

Ensures specific lines are present, and specific lines are absent, in a
target file — leaving everything else in that file untouched. Expands to
`:config-lines`. Note: identity for this action type includes the actual
content, so multiple `config-lines` calls against the *same file* never
conflict with each other — they're additive.

```lisp
(config-lines "~/.config/i3/config"
  :ensure ("bindsym $mod+Return exec emacs")
  :remove ("bindsym $mod+Return exec i3-sensible-terminal"))
```

**Ensure-only:**

```lisp
(config-lines "~/.config/emacs/init.el"
  :ensure ("(setq initial-buffer-choice t)"))
```

**Remove-only:**

```lisp
(config-lines "~/.bashrc" :remove ("alias rm='rm -i'")))
```

### 5.11 `config-ini`

Sets/unsets keys within a named `[section]` of an INI-style file. Expands
to `:config-ini`.

```lisp
(config-ini "~/.config/fontconfig/fonts.conf"
  :section "antialias"
  :set (("enable" . "true"))
  :unset ("rgba"))
```

**Set-only:**

```lisp
(config-ini "~/.gtkrc-2.0" :section "Settings" :set (("gtk-theme-name" . "Adwaita-dark")))
```

### 5.12 `config-env`

Sets `KEY=value` pairs in a systemd `environment.d`-style file (no section
headers). Expands to `:config-env`.

```lisp
(config-env "~/.config/environment.d/wayland.conf"
  :set (("MOZ_ENABLE_WAYLAND" . "1")
        ("QT_QPA_PLATFORM" . "wayland")
        ("XDG_CURRENT_DESKTOP" . "sway")))
```

### 5.13 `direct-action`

The escape hatch. For anything a feature or convenience form doesn't
cover. You always need to say why.

```lisp
(direct-action
  :reason "No provider exists for :proprietary-tool and I need it tomorrow"
  (:action :package :target "proprietary-tool" :version "1.2.3"))
```

You can pass more than one action plist in one `direct-action`:

```lisp
(direct-action
  :reason "Custom cleanup not covered by convenience forms"
  (:action :copy-file
           :from "custom/cleanup.sh"
           :to "~/.local/bin/cleanup.sh"
           :mode #o755)
  (:action :ensure-dir :target "~/.local/bin" :mode #o755))
```

`direct-action` entries always win identity conflicts outright — reaching
for the escape hatch is a deliberate act on your part, so I trust it.

### 5.14 Facts

**Reading one:**

```lisp
(fact :laptop-p)
(fact :os))
```

**Combining facts with ordinary predicates** (this is the whole
vocabulary — no custom conditional macros exist):

```lisp
(and (fact :work-p) (fact :laptop-p))
(member :nvidia (fact :gpu-vendor))
(eq (fact :display-server) :wayland)
(not (fact :laptop-p)))
```

**Every built-in fact**, all probed from `/proc`/`/sys` (or a read-only
command like `uname`) — no sudo, no distro-specific tooling required:

| Fact | Values | How it's probed |
|---|---|---|
| `:os` | e.g. `:fedora`, `:arch`, `:debian`, `:ubuntu` | distro-specific release files first, `/etc/os-release`'s `ID=` as a generic fallback |
| `:hostname` | a string | `uiop:hostname` |
| `:laptop-p` | `t`/`nil` | any `BAT*` under `/sys/class/power_supply/` |
| `:display-server` | `:wayland`, `:x11`, `nil` | `$WAYLAND_DISPLAY`/`$DISPLAY` |
| `:gpu-vendor` | a **list** of `:nvidia`/`:amd`/`:intel` (e.g. `(:intel :nvidia)` on hybrid graphics) | PCI vendor ID under every `/sys/class/drm/card*/device/vendor` |
| `:vm-p` | `t`/`nil` | DMI `sys_vendor`/`product_name` against known hypervisor strings, falling back to `/proc/cpuinfo`'s `hypervisor` flag on x86 |
| `:cpu-arch` | e.g. `:x86-64`, `:aarch64`, `:armv7l` | `uname -m` |
| `:package-manager` | `:pacman`, `:dnf`, `:yum`, `:apt`, `:zypper`, `:apk`, `:xbps`, `:portage`, `:unknown` | which of those binaries is actually on `PATH`, checked in that order — not a mapping from `:os`, so a distro `:os` doesn't recognize by name still resolves correctly |
| `:wifi-p` | `t`/`nil` | any `/sys/class/net/*/wireless/` |
| `:bluetooth-p` | `t`/`nil` | any adapter under `/sys/class/bluetooth/` |
| `:touchpad-p` | `t`/`nil` | a `Touchpad`-named entry in `/proc/bus/input/devices` |
| `:ram-gb` | an integer | `MemTotal` in `/proc/meminfo`, rounded |
| `:cpu-cores` | an integer | `processor` line count in `/proc/cpuinfo` (logical CPUs, same as `nproc`) |
| `:uefi-p` | `t`/`nil` | `/sys/firmware/efi/` exists |
| `:init-system` | `:systemd`, `:openrc`, `:runit`, `:sysvinit`, `:unknown` | `/run/systemd/system/` unambiguously; a couple of marker paths for the rest (best-effort) |
| `:root-disk-type` | `:nvme`, `:ssd`, `:hdd`, `:unknown` | resolves `/`'s device from `/proc/mounts` through any LVM/LUKS/mdraid stacking, then `/sys/block/*/queue/rotational` |
| `:fingerprint-p` | `t`/`nil` | `"fingerprint"` in any `/sys/bus/usb/devices/*/product` (heuristic — won't catch a non-USB reader) |
| `:container-p` | `t`/`nil` | `/.dockerenv`, `/run/.containerenv`, `$container`, or `docker`/`lxc`/`kubepods` in `/proc/1/cgroup` |
| `:sys-vendor` | a string, or `:unknown` | `/sys/class/dmi/id/sys_vendor` |
| `:product-name` | a string, or `:unknown` | `/sys/class/dmi/id/product_name` |

Two facts that look like they belong on this list are deliberately
**not** built in: `:secure-boot-p` and `:product-uuid`. Both would need
to read a `/sys` attribute (the EFI `SecureBoot` efivar; DMI's
`product_uuid`) that's root-only by default on every mainstream distro —
the kernel restricts exactly those two DMI/efivar attributes on purpose,
since they're closer to a hardware serial number than a descriptive
string. I never ask for sudo just to read a fact, so these aren't
probed. If you genuinely need one, you can still register it yourself
with `:sudo`-appropriate handling in your own action, the same way any
custom fact or action works — LINACS just won't do it silently as a
built-in.

**Registering a new fact prober** (typically in `providers/*.lisp`):

```lisp
(register-fact-prober :codename
  (lambda ()
    (cond
      ((probe-file "/etc/fedora-release") :fedora-codename-here)
      (t :unknown))))
```

If two different files register a prober for the *same* key, I won't
guess which one to trust — I'll stop at startup and tell you both
registrants, so you can remove one or make one depend on and defer to the
other.

### 5.15 Profiles

**Defining one:**

```lisp
(define-profile :laptop
  '((:hostname . "thinkpad") (:gpu . :nvidia) (:laptop-p . t)))
```

**Defining several, side by side** (profiles never extend each other —
each one is a complete, independent override set):

```lisp
(define-profile :work-laptop
  '((:hostname . "work-thinkpad") (:gpu . :intel) (:laptop-p . t) (:work-p . t)))

(define-profile :personal-desktop
  '((:hostname . "home-tower") (:gpu . :nvidia) (:laptop-p . nil) (:work-p . nil)))
```

**Selecting one:**

```sh
linacs plan -C ~/my-home --profile work-laptop)
```

**Running with no profile at all** is completely valid — you just get
whatever the fact probers found, with no overrides:

```sh
linacs plan -C ~/my-home))
```

### 5.16 Catalogs

**Defining one:**

```lisp
(define-catalog :packages
  (:emacs (:fedora . "emacs") (:ubuntu . "emacs-nox") (:arch . "emacs")))
```

**A catalog entry with fewer distros than you support** — this is fine,
distros that aren't listed just fall back to the keyword's own name:

```lisp
(define-catalog :packages
  (:htop (:fedora . "htop")))   ; on :arch, resolves to "htop" anyway
```

**Extending an existing catalog from a plugin, without redefining the
whole thing:**

```lisp
(register-catalog :packages :emacs '((:void . "emacs-nox")))
```

**Per-via catalog entries.** By default, catalog entries are resolved
for `:via :system` (the distro key). You can add entries for other
method types too — useful when a canonical keyword needs a different
name for Flatpak, pip, or a containerized install:

```lisp
(define-catalog :packages
  (:emacs (:fedora . "emacs-pgtk") (:ubuntu . "emacs-nox")
          (:flatpak . "org.gnu.emacs"))
  (:firefox (:flatpak . "org.mozilla.firefox")
            (:fedora . "firefox") (:ubuntu . "firefox")))
```

When I resolve a package action with `:via :flatpak`, I look for a
`(:flatpak . "name")` entry first, falling back to the keyword's own
name if none is found. Old `(:distro . "name")` entries continue to
work unchanged and are treated as `:system`-via entries.

### 5.17 Features

```lisp
(define-feature :development
  :description "Core development tools: compilers, debuggers, version control"
  :tags (:dev :core)
  :provides (:compilers :version-control)
  :requires (:editor))
```

- `:description` and `:tags` are documentation only — I don't act on them,
  but `linacs list`/`linacs doctor` can surface them.
- `:requires` is the real mechanism: when you `use-feature :development`,
  I make sure `:editor` is resolved first.

**A feature with no dependencies at all:**

```lisp
(define-feature :shell :requires nil))
```

### 5.18 Providers

```lisp
(define-provider :emacs :for :editor
  (lambda (facts)
    (list
      '(:action :package :target :emacs :via :system)
      '(:action :ensure-dir :target "~/.config/emacs/" :mode #o755)
      '(:action :copy-file :from "emacs/init.el" :to "~/.config/emacs/init.el"))))
```

**A provider that computes its actions from facts, instead of returning a
fixed list:**

```lisp
(define-provider :lsp-auto-install :for :language-support
  (lambda (facts)
    (mapcar (lambda (lang)
              (list :action :package
                    :target (format nil "~a-lsp" lang) :via :system))
            (getf facts :languages))))
```

**Giving a provider a description**, so `linacs list` and `linacs explain` show
something more useful than just its name:

```lisp
(define-provider :emacs :for :editor :description "GNU Emacs with a minimal, fast-starting config"
  (lambda (facts) ...))
```

**A provider that conditionally returns nothing** (useful when the
provider itself should only apply under certain facts, independent of
whether the feature was requested):

```lisp
(define-provider :nvidia-proprietary :for :nvidia-drivers
  (lambda (facts)
    (when (eq (getf facts :gpu) :nvidia)
      (list '(:action :package :target :nvidia-driver :via :system)))))
```

**Marking a provider as the default**, so `(use-feature :shell)` doesn't
force you to specify `:via` when several providers exist for a feature —
I'll only auto-select the sole provider when there's exactly one *or*
exactly one is marked `:default t`:

```lisp
(define-provider :bash :for :shell :default t
  (lambda (facts) (declare (ignore facts))
    (list '(:action :package :target :bash :via :system)
          '(:action :copy-file :to "~/.bashrc" :from "bashrc")))

(define-provider :zsh :for :shell
  (lambda (facts) (declare (ignore facts))
    (list '(:action :package :target :zsh :via :system)
          '(:action :copy-file :to "~/.zshrc" :from "zshrc"))))
```

With that in place, both of these work:

```lisp
(use-feature :shell)              ; -> bash, since it's the default
(use-feature :shell :via :zsh)    ; -> zsh, explicit override still wins
```

If nobody registers a default and more than one provider exists, I still
stop and ask you to disambiguate — same as always, just with a message
that now lists every candidate by name so you can see exactly what you're
choosing between. If more than one provider claims `:default t` for the
same feature, that's also an error — a default has to be unambiguous too.

Because a provider is just a function, you (or a provider author writing
tests) can call it directly with a fixture fact plist and assert on the
list it returns — no special test mode needed for providers, unlike
executors.

**Passing configuration** to use-feature provider creates re-useable
features that can easily be copied by others, and customised without
needing to update the provider.

```lisp
(use-feature :editor
  :via :emacs
  :config (:url "https://github.com/someone/doom-emacs.git"
           :target "~/.config/emacs")))
```

The variables are accesible withing the provider as follows:

```lisp
(define-provider :emacs
  :for :editor
  :description "GNU Emacs"
  (lambda (facts)
    (declare (ignore facts))
    (let* (;; ── Configuration source (from :config or sensible defaults) ──
           (config-url       (or (feature-config :editor :url)
                                 "https://github.com/doom/doom-emacs.git"))
           (config-target    (or (feature-config :editor :target)
                                 "~/.emacs.d")))
      (append
       (list
        (list :action :package :target package-key :via :system)
        '(:action :package :target :git :via :system)
        (list :action :clone :target config-target :url config-url))

       (editor-environment-actions editor-cmd visual-cmd pager-cmd sudo-editor-cmd)))))
```

### 5.19 The built-in Action types, directly

You'll mostly reach these through the convenience forms above, but every
one of them is a plain plist you can also write yourself (inside a
provider, or via `direct-action`):

```lisp
(:action :package     :target :emacs :via :system)
(:action :ensure-dir   :target "~/.config/emacs/" :mode #o755 :owner "user" :group "user")
(:action :copy-file    :from "emacs/init.el" :to "~/.config/emacs/init.el" :mode #o644)
(:action :symlink      :target "~/.emacs.d" :to "~/.config/emacs")
(:action :service      :target :ssh-daemon :enabled t :running t)
(:action :timer        :target "backup-daily" :on-calendar "daily")
(:action :env-var      :target "EDITOR" :value "emacs" :file "~/.profile")
(:action :config-lines :target "~/.config/i3/config"
                         :ensure ("bindsym $mod+Return exec emacs")
                         :remove ("bindsym $mod+Return exec i3-sensible-terminal"))
(:action :config-ini   :target "~/.config/fontconfig/fonts.conf"
                         :section "antialias" :set (("enable" . "true")) :unset ("rgba"))
(:action :config-env   :target "~/.config/environment.d/wayland.conf"
                         :set (("MOZ_ENABLE_WAYLAND" . "1")))
(:action :secret       :target "~/.ssh/id_ed25519" :from :pass :path "ssh/id_ed25519" :mode #o600)
(:action :stow         :target "fish" :to "~"))
```

Thirteen more built-in types — `:user`, `:group`, `:authorized-key`,
`:permissions`, `:mount`, `:sysctl`, `:kernel-module`, `:hostname`,
`:locale`, `:firewall`, `:cron`, `:command`, `:clone` — cover system
administration and other tasks beyond a single home directory. They have
their own convenience forms too (`user`, `group`, `authorized-key`, ...);
see §5.21 for every one of them with example variations.

**`:service`, specifically** — enables/starts a systemd unit only if it
isn't already in the desired state:

```lisp
(:action :service :target :tlp :enabled t :running t))
```

**`:timer`, specifically** — creates and enables a systemd timer unit:

```lisp
(:action :timer :target "backup-daily" :on-calendar "daily"))
```

**Registering a brand-new action type** (for when even `direct-action`
plus the built-ins don't cover what you need — an author-level
extension):

```lisp
(register-action-type :my-custom-action
  (lambda (action &key mode)
    (case mode
      (:check (list :status :would-change :target (getf action :target)))
      (:apply (list :status :changed :target (getf action :target)))
      (:remove (list :status :removed :target (getf action :target))))))
```

### 5.20 Generic action properties

These work on *any* action, whether written via a convenience form or
directly:

```lisp
;; Run only after another action, by identity
(file "starship.toml" :from "starship.toml"
      :depends-on ((:package :system . "starship")))

;; Win any identity conflict outright
(file "~/.gitconfig" :from "gitconfig" :force t)

;; Mark for removal (only acted on with :prune-explicitly-disabled)
(package "nano" :disabled t)

;; Explicit ownership for a system path
(file "/etc/foo.conf" :from "foo.conf" :owner "root" :group "root"))
```

### 5.21 System administration actions

The built-in types in §5.19 cover dotfiles, packages, and services. A
separate class of task shows up once you're managing more than your own
home directory — system users, mounts, kernel parameters, the firewall —
and deserves its own dedicated, idempotent executors rather than being
bent out of shape from `:config-lines` or a raw shell command. Here they
are, one by one.

**`user`** — creates or modifies a system user; only touches what's
actually different (an existing user with matching attributes is left
alone):

```lisp
(user "deploy" :shell "/bin/bash" :create-home t)

(user "postgres" :system t :create-home nil :shell "/usr/sbin/nologin")

;; lock or unlock the account
(user "deploy" :locked t)

;; remove it (only acted on with :prune-explicitly-disabled)
(user "old-service-account" :disabled t :remove-home t))
```

**`group`** — creates or modifies a system group:

```lisp
(group "docker")
(group "docker" :gid 999)
(group "sudo" :disabled t))
```

**`authorized-key`** — manages one entry in a user's
`~/.ssh/authorized_keys`, without touching any other key already there.
Re-declaring the same key with a different comment updates it in place
rather than creating a duplicate line, and I enforce the strict `700`/
`600` permissions SSH requires on the directory and file:

```lisp
(authorized-key "deploy" :key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...")

(authorized-key "deploy"
  :key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..."
  :comment "ci-bot@github-actions")

;; remove just this one key, leaving every other key in the file alone
(authorized-key "deploy" :key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..." :disabled t))
```

**`permissions`** — fixes owner/group/mode on a path that already exists,
without creating it and without touching its content. This is the tool
for paths a *package* created (`/var/lib/mysql`, `/var/www`), which
`file`/`directory` only ever set ownership on at creation time:

```lisp
(permissions "/var/lib/mysql" :owner "mysql" :group "mysql" :mode #o750)

(permissions "/var/www" :owner "www-data" :group "www-data" :recursive t))
```

**`mount`** — ensures a persistent `/etc/fstab` entry exists *and* the
filesystem is actually mounted right now, not just on next boot:

```lisp
(mount "/mnt/data" :device "/dev/sdb1" :fstype "ext4")

(mount "/mnt/data" :device "/dev/sdb1" :fstype "ext4" :options "defaults,noatime")

;; a bind mount
(mount "/srv/containers/app/data" :device "/mnt/data/app" :fstype "none" :options "bind")

;; unmount and drop the fstab entry
(mount "/mnt/data" :device "/dev/sdb1" :disabled t))
```

**`sysctl`** — sets a kernel parameter, persists it under
`/etc/sysctl.d/`, and applies it to the *running* kernel immediately, so
you don't need a reboot to see the effect:

```lisp
(sysctl "net.ipv4.ip_forward" :value 1)

(sysctl "vm.swappiness" :value 10 :file "/etc/sysctl.d/60-swap.conf"))
```

**`kernel-module`** — loads a module now and persists that decision via
`/etc/modules-load.d/`, or blacklists one via `/etc/modprobe.d/`:

```lisp
(kernel-module "nfs" :state :loaded)
(kernel-module "usb-storage" :state :blacklisted))
```

**`hostname`** — sets the hostname at runtime *and* writes `/etc/hostname`
so it survives a reboot; setting only one or the other is a common
half-fix this avoids:

```lisp
(hostname "app-server-01"))
```

**`locale`** — generates a locale if it isn't already, sets it as the
system default, and optionally sets the timezone (which involves
re-pointing the `/etc/localtime` symlink, not just editing a config file):

```lisp
(locale "en_US.UTF-8")
(locale "en_US.UTF-8" :timezone "America/New_York"))
```

**`firewall`** — opens or closes a port through whichever of
`firewalld`/`ufw` is actually installed, so your home config doesn't have
to hard-code one:

```lisp
(firewall 80 :protocol "tcp" :allow t)
(firewall 22 :protocol "tcp" :allow t)

;; close a port
(firewall 8080 :protocol "tcp" :allow nil))
```

**`cron`** — manages one entry under `/etc/cron.d/`, for the minimal
installs (Alpine, Debian-minimal, older RHEL) that still lean on cron
instead of systemd timers:

```lisp
(cron "nightly-backup" :schedule "0 2 * * *" :command "/usr/local/bin/backup.sh")

(cron "cleanup-tmp"
  :schedule "*/15 * * * *"
  :command "/usr/bin/find /tmp -mtime +1 -delete"
  :user "root"))
```

**`command`** — the escape hatch beneath the escape hatch: a raw shell
command, but with an idempotency check so it doesn't just re-run blindly
every time. Give me exactly one of `:creates`, `:unless`, or `:only-if`:

```lisp
;; run only if this path doesn't exist yet
(command "install oh-my-zsh" :run "sh install-oh-my-zsh.sh --unattended"
         :creates "~/.oh-my-zsh")

;; run only if this shell command currently fails (exits non-zero)
(command "install rustup" :run "curl https://sh.rustup.rs -sSf | sh -s -- -y"
         :unless "command -v rustup")

;; run only if this shell command currently succeeds
(command "restart flaky service" :run "systemctl restart flaky.service"
         :only-if "systemctl is-failed --quiet flaky.service"))
```

If you give me none of the three, I can't reason about whether the
command is needed — I'll say so honestly (`:would-change` under `plan`,
and I'll run it on every `apply`) rather than pretend I checked something
I didn't. That's a signal to add a check, not a bug to work around.

(Cloning a git repo specifically has its own dedicated type, `:clone`,
just below — prefer it over `command` + `git clone` when that's all you
need, since it actually checks the repo's real state on a repeat run
instead of just a marker file's presence.)

Give `:sudo t` when `:run` (and `:remove-run`, if present) itself needs
root:

```lisp
(command "set timezone" :run "timedatectl set-timezone America/New_York"
         :unless "timedatectl show --property=Timezone | grep -q America/New_York"))

(command "write sysctl override" :run "echo 1 > /proc/sys/net/ipv4/ip_forward"
         :only-if "test $(cat /proc/sys/net/ipv4/ip_forward) != 1"
         :sudo t))
```

Every other built-in action type escalates on its own, per-command, only
if a plain attempt actually fails — `:command` is the one exception,
because I can't safely guess whether an arbitrary shell string needs
root, and re-running it after a failed plain attempt could leave things
half-done. So for `:command` specifically, `:sudo t` is how you tell me
up front; I still skip `sudo` itself if the whole process already happens
to be running as root (see §5.21's general escalation note and
§4.4).

**`clone`** — ensures a git repository is checked out at `:target`,
requires the `git` binary. Unlike `command` + a `:creates` marker, a
repeat run actually looks at the repo's real state: it checks the
checked-out repo's `origin` remote against the declared `:url`, not just
whether the directory happens to exist:

```lisp
(clone "~/.dotfiles" :url "https://example.com/dotfiles.git")

(clone "~/.cache/linacs/krohnkite" :url "https://github.com/esjeon/krohnkite.git"
       :branch "main" :depth 1))
```

- Target missing → clones it.
- Target exists, `origin` matches `:url` → `:unchanged` — I never re-clone
  or re-fetch on every run.
- Target exists but isn't a git repository at all → a clear
  `execution-failure`, refusing to clone over whatever's actually there,
  the same conflict-detection philosophy as `:stow`.
- Target exists, is a git repo, but `origin` doesn't match the declared
  `:url` → also a clear `execution-failure` — a real contradiction on
  disk, not something I'll silently re-point.
- `:branch` given, but a *different* branch is currently checked out → I
  only warn about it; I never auto-switch branches, since that could
  discard a dirty working tree.
- `:depth` only affects the initial clone — I don't re-verify it
  afterward (git doesn't cheaply expose "was this a shallow clone of
  depth N" for me to check against).

I never escalate for `:clone` itself (you're cloning into your own
directories); `:remove` deletes the whole checked-out tree, falling back
to a privileged `rm -rf` only if the plain delete fails, same as every
other filesystem-removing built-in.

### 5.22 Templates

A template renderer is a plain Common Lisp function returning a string,
living in `templates/*.lisp`, in the `:linacs-templates` package.

**By-convention discovery** — `gitconfig.tmpl` looks for
`RENDER-GITCONFIG`:

```lisp
;; templates/renderers.lisp
(in-package :linacs-templates)

(defun render-gitconfig (facts &key signing-key work-email)
  (format nil "[user]
    name = ~a
    email = ~a
    signingkey = ~a"
          (getf facts :user-name)
          (if (getf facts :work-p) work-email "personal@example.com")
          (or signing-key "")))
```

Used from `home.lisp` as:

```lisp
(file "~/.gitconfig" :from "gitconfig.tmpl" :template t
      :secrets ((:signing-key :from :pass :path "git/signing-key")
                (:work-email :from :pass :path "git/work-email")))
```

If I can't find a matching `RENDER-*` function, I'll stop and tell you the
exact symbol name I looked for, with the option to supply a renderer,
treat the file as static instead, skip, or abort.

**Explicit renderer, skipping by-convention lookup entirely:**

```lisp
(file "~/.gitconfig" :from "gitconfig.tmpl" :renderer #'render-gitconfig))
```

### 5.23 Pipeline hooks

Two extension points, for cross-cutting behavior that doesn't belong in
any single provider:

**`:after-resolve`** — runs right after step 2, before deduplication, with
every collected action:

```lisp
(register-pipeline-hook :after-resolve
  (lambda (facts actions)
    (declare (ignore facts))
    (dolist (action actions)
      (when (eq (getf action :action) :secret)
        (linacs.log:info "Secret action targets ~a" (getf action :target))))))
```

**`:before-execute`** — runs right after step 4, with the final ordered
list, before anything is actually executed:

```lisp
(register-pipeline-hook :before-execute
  (lambda (facts ordered-actions)
    (declare (ignore facts))
    (let ((removals (remove-if-not (lambda (a) (getf a :disabled)) ordered-actions)))
      (when removals
        (linacs.log:warn "This run will remove ~d resource(s)." (length removals))))))
```

Multiple hooks at the same point run in the order you registered them. A
hook can signal a condition to halt the run, but it can't rewrite the
action list or reorder execution — it observes and may object, nothing
more.

### 5.24 The CLI, command by command

```
linacs plan       -C DIR [--profile NAME]
linacs apply      -C DIR [--profile NAME] [-n] [--continue]
linacs diff       -C DIR [--profile NAME]
linacs validate   -C DIR
linacs check      -C DIR [--profile NAME]
linacs explain    -C DIR [--profile NAME]
linacs graph      -C DIR [--profile NAME]
linacs export     -C DIR [--profile NAME] [-o FILE]
linacs list       -C DIR
linacs facts      -C DIR [--profile NAME]
linacs doctor     -C DIR [--profile NAME]
linacs init       -C DIR
linacs version
```

**`plan`** — resolve everything, print the ordered action list, touch
nothing:

```sh
linacs plan -C ~/my-home --profile work-laptop))
```

**`apply`** — actually execute. Never run this one under `sudo` yourself:
whichever individual actions in the plan genuinely need root (a package
install, a root-owned system file) escalate on their own, one command at
a time, and may prompt you for your `sudo` password right at that step:

```sh
linacs apply -C ~/my-home --profile work-laptop)

# dry-run: see exactly what apply would have done, touches nothing
linacs apply -C ~/my-home --profile work-laptop -n))
```

**`diff`** — check mode, but focused on reporting only what would
actually change:

```sh
linacs diff -C ~/my-home --profile work-laptop))
```

**`validate`** — syntax only, doesn't touch facts/features/providers at
all, runs even if a plugin is broken:

```sh
linacs validate -C ~/my-home))
```

**`check`** — full resolution (steps 0–4), no execution — catches missing
providers, action conflicts, dependency cycles, fact-prober conflicts:

```sh
linacs check -C ~/my-home --profile work-laptop))
```

**`explain`** — prints which provider was actually chosen for each
feature you used (not just the feature name), each with its description,
plus the final numbered action order, for when `plan`'s output isn't
detailed enough:

```sh
linacs explain -C ~/my-home --profile work-laptop))
```

**`graph`** — prints the abstract feature dependency graph (not the
action list), with each feature's description alongside it:

```sh
linacs graph -C ~/my-home --profile work-laptop))
```

**`export`** — writes the resolved action list out as a Lisp
s-expression, to a file if you want one:

```sh
linacs export -C ~/my-home --profile work-laptop -o /tmp/plan.sexp))
```

**`list`** — every registered feature, provider, catalog, and action
type, as aligned tables, each with whatever description you gave it (in
`:description` on `define-feature`, `define-provider`, or a built-in
action type's own documentation). Features get a combined view showing
every provider registered for them in one row:

```sh
linacs list -C ~/my-home)
# Features:
#   FEATURE   DESCRIPTION              PROVIDERS
#   --------  -----------------------  --------------------
#   editor    Text editor capability   emacs (default), vim
#   shell     Login shell and dotfiles bash, zsh
#
# Providers:
#   PROVIDER  FOR FEATURE  DEFAULT  DESCRIPTION
#   --------  -----------  -------  ----------------------------------------
#   emacs     editor       yes      GNU Emacs with a minimal, fast-starting config
#   vim       editor                Vim with sane defaults, no plugin manager
#
# Action types:
#   TYPE       DESCRIPTION
#   ---------  --------------------------------------
#   copy-file  Copy or render a file to a target path
#   ...
```

**`facts`** — print every resolved fact, after probing and merging your
selected `--profile`, one per line, aligned. This is the fastest way to
answer "why did I pick that provider on this machine" without re-deriving
it from probes yourself:

```sh
linacs facts -C ~/my-home --profile work-laptop)
#   DISPLAY-SERVER  :WAYLAND
#   GPU             :INTEL
#   HOSTNAME        "work-thinkpad"
#   LAPTOP-P        T
#   OS              :DEBIAN
#   WORK-P          T
```

**`doctor`** — sanity-checks your environment against your home: OS,
hostname, privileges, a table of exactly how each `use-feature` resolves
(the chosen provider, or a clear diagnosis — no provider registered,
ambiguous with no default, a `:via` that doesn't exist), and a count of
how many package installs in the plan will actually need root:

```sh
linacs doctor -C ~/my-home --profile work-laptop))
```

**`init`** — scaffold a brand-new project (see §2.1):

```sh
linacs init -C ~/my-home))
```

**Global options, usable on (almost) any command:**

```
-C, --root DIR        Project root (default .)
-p, --platform NAME    Target platform (default: auto-detect)
    --profile NAME     Select a defined profile
    --provider T=P     Prefer provider P for feature T
-n, --dry-run          Show changes without executing them (apply)
    --continue         Keep going after a failed action
-o, --output FILE      Write output to FILE (export)
-v, --verbose          Increase verbosity (repeat for more: -v, -vv)
    --quiet            Only show errors
-h, --help             Show help and exit
```

### 5.25 Getting help

I try never to leave you guessing about what a command accepts.

**Running me with no arguments, or `linacs --help`,** prints every command
with a one-line description, aligned into a column, followed by every
global option:

```sh
linacs --help)
# Usage: linacs <command> [options]
#
# Commands:
#   plan      Show the resolved, ordered action list
#   apply     Execute the ordered action list
#   ...
```

**Adding `--help` after any specific command** shows that command's own
usage line, description, exactly the options *it* accepts (not every
option I support globally — `init` doesn't take `--profile`, for
instance, and I won't pretend it does), and a couple of runnable
examples:

```sh
linacs apply --help)
# Usage: linacs apply [options]
#
# Execute the ordered action list
#
# Options:
#   -C, --root DIR  Project root (default ".")
#   --profile NAME  Select a defined profile (fact overrides)
#   -n, --dry-run   Show changes without executing them
#   --continue      Keep going after a failed action
#   -v, --verbose   Increase verbosity (repeatable: -v, -vv)
#   --quiet         Only show errors
#   -h, --help      Show this command's help and exit
#
# Examples:
#   linacs apply -C ~/my-home --profile work-laptop   # sudo (if needed) is per-action
#   linacs apply -C ~/my-home --profile work-laptop -n   # dry run
```

**If you pass a flag I don't recognize, or leave a flag missing its
required value,** I won't silently ignore it or crash with a raw stack
trace — I print that command's help (so you can see immediately what it
does accept) and exit non-zero:

```sh
linacs apply --bogus-flag)
# [error] Unknown or malformed option(s) for 'apply': --bogus-flag
#
# Usage: linacs apply [options]
# ...
```

### 5.26 When I stop and ask you something

I use the Common Lisp Condition System for every error, not exceptions in
the exception-handling sense. That means every failure comes with
concrete restarts, not just a stack trace. Every command — not just
`apply` — catches these cleanly and prints a one-line error instead of an
SBCL backtrace. Here's the full list of conditions I can signal, and what
your options are at each one:

| Condition | When it happens | Your restarts |
|---|---|---|
| `missing-provider` | You `use-feature`d something with no matching (or ambiguous) provider | specify a provider / skip the feature / abort |
| `action-conflict` | Two same-priority actions claim the same identity with different content | keep definition A / keep definition B / abort |
| `non-interactive-prompt` | A `:prompt` secret was hit with no attached terminal | supply the value / skip / abort |
| `fact-prober-conflict` | Two different registrations claim the same fact key | abort (fix one of the registrations) |
| `missing-template-renderer` | `:template t` but no matching `RENDER-*` function exists | specify a renderer / treat as static / skip / abort |
| `file-discovery-load-error` | One of your project's `.lisp` files failed to load | skip that file / abort |
| `dependency-cycle` | Your `:depends-on` edges form a loop | abort (fix the cycle) |
| `execution-failure` | An executor's underlying operation failed (disk full, network down, a privileged command's sudo prompt failed or was declined, ...) | retry / skip / abort |

I never require you to run me as root. Every action that genuinely needs
privilege escalates on its own, per action, via `sudo` — a package
install, a write to a root-owned system file, creating a system user.
Everything else never touches `sudo` at all. If a privileged step
genuinely fails (wrong password, no TTY, cancelled), that's a real
`execution-failure`, not something silently treated as "nothing needed to
change."

I never retry automatically, and I never roll back. Re-running me after
you've fixed the underlying problem is always the right move — every
built-in executor is idempotent, so re-running is cheap and safe.

### 5.27 A note on stale builds

If you build me as a standalone executable with `save-lisp-and-die` and
you ever update your `linacs` checkout in place (pull a fix, re-extract a
new copy over an old directory, etc.), make sure ASDF actually recompiles
from the new sources before you re-save the image. If you reuse an old
project directory, or your fasl cache still has compiled output from a
previous build, ASDF can decide nothing's changed based on file
timestamps and silently reuse stale compiled code — you'll see behavior
from a version you thought you'd already fixed. The reliable fix is to
force a full rebuild:

```lisp
(asdf:load-system :linacs :force t))
```

I'd rather you hit this note once here than debug it from a cryptic error
a second time.

---

That's everything. If you made it this far: go build something. Start
small — one feature, one provider, one file — and grow it. That's how I'm
meant to be used.
