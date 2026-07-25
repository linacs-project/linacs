# LINACS - Declarative Linux Home Environment Definition Language

If there only was a Linux like Emacs. Configured in Lisp. Now there is - Linacs.

## Overview

LINACS is a project that allows users to declaratively define their Linux home environment using a Lisp-like syntax. It handles package installation, file configuration, service management, and more through a standardized DSL.

## Key Features

- **Declarative Configuration**: Define your home environment with clear, readable Lisp code
- **Distribution Agnostic**: Works across Fedora, Arch, Debian, Ubuntu, and other mutable distributions
- **Idempotent Actions**: Every action is designed to be idempotent
- **Auto-Discovery**: Automatically discovers features, providers, catalogs, and action types
- **Fact-Based**: Automatically detects your system (OS, GPU, laptop/desktop, etc.)
- **Extensible**: Easy to add new features, providers, action types, and `:via` handlers via plugins

## Quick Start

### Installation

```bash
# Install dependencies
sudo dnf install sbcl asdf-uiop  # Fedora
# or
sudo apt-get install sbcl libffi-dev  # Debian/Ubuntu

# Clone and install
cd /path/to/linacs-project
git clone <repository-url>
cd linacs
./build.sh
```

### Running LINACS

```bash
# Build and install (creates `linacs` executable)
./build.sh

# Create a home definition
echo "(define-home my-home (use-feature :emacs))" > home.lisp

# Apply configuration
./linacs apply --root . -C /path/to/linacs-home
```

## Architecture

### Core Components

- **Features**: Abstract capabilities (e.g., `:development`, `:editor`)
- **Providers**: Concrete implementations mapping features to actions
- **Facts**: System information (OS, GPU, laptop/desktop, etc.)
- **Actions**: Atomic operations (package install, file copy, service enable)
- **Catalogs**: Distribution-specific package names
- **Discovery**: Automatic plugin and file discovery

### Home Definition

```lisp
(define-home my-home
  :traits (:prune-explicitly-disabled)

  ;; Capabilities
  (use-feature :development)
  (use-feature :browser)

  ;; Standard CL conditional over a Fact
  (when (fact :laptop-p)
    (use-feature :battery-management))

  ;; Simple file drops for dotfiles
  (file "~/.gitconfig" :from "gitconfig")

  ;; Secrets
  (secret "~/.ssh/id_ed25519" :from :pass :path "ssh/id_ed25519")

  ;; Explicit removal
  (package "vim" :disabled t))
```

## Testing

LINACS includes a comprehensive test suite using the FiveAM testing framework.

### Running Tests

```bash
cd /path/to/linacs
sbcl --load run-all-tests.lisp
```

### Test Structure

The test suite covers:
- **DSL Tests**: File, directory, symlink, package definitions (6 tests)
- **Feature Tests**: Dependency graph resolution (1 test)
- **Pipeline Tests**: Execution flow (1 test)
- **Executor Tests**: Copy-file, ensure-dir, symlink, service, package-action, config-lines (13 tests)
- **Action Tests**: Identity computation, deduplication, ordering (10 tests)

**Total: 23 tests** - All passing

See [linacs-tests/README.md](../linacs-tests/README.md) for detailed testing documentation.

### Quick Test

```bash
# Run simple test suite
sbcl --load run-simple-tests.lisp
```

### Adding Tests

```lisp
(in-package #:linacs-tests)

(def-suite your-suite
  :description "Suite description here")

(def-test your-test-name ()
  "Test description here"
  (it.bese.fiveam:is (condition-equals expected-value))
  (linacs.core:reset-project-registries))  ; Reset for isolation
```

## CLI Commands

```
linacs <command> [options]

Commands:
  plan        Show the resolved, ordered action list
  apply       Execute the ordered action list
  diff        Show which actions would change something
  validate    Check configuration syntax only
  check       Fully resolve configuration without executing
  explain     Print the resolved feature graph and action order
  graph       Print the abstract feature dependency graph
  export      Write the action list as a data s-expression
  list        List registered features, providers, catalogs, action types
  doctor      Diagnose the environment and provider coverage
  init        Scaffold a new project
  version     Print the LINACS version

Options:
  -C, --root DIR        Project root (default .)
  -p, --platform NAME   Target platform (default: auto-detect)
      --profile NAME    Select a defined profile (fact overrides)
      --provider T=P    Prefer provider P for feature T
  -n, --dry-run         Show changes without executing them
  -v, --verbose         Increase verbosity (can be repeated)
      --quiet           Only show errors
```

## Development

### Project Structure

```
linacs/
├── src/                  # LINACS core implementation
│   ├── package.lisp
│   ├── conditions.lisp
│   ├── log.lisp
│   ├── discovery.lisp
│   ├── facts.lisp
│   ├── profiles.lisp
│   ├── catalogs.lisp
│   ├── features.lisp
│   ├── providers.lisp
│   ├── actions.lisp
│   ├── secrets.lisp
│   ├── templates.lisp
│   ├── action-types/
│   │   ├── package.lisp
│   │   ├── helpers.lisp
│   │   ├── copy-file.lisp
│   │   ├── ensure-dir.lisp
│   │   ├── symlink.lisp
│   │   ├── service.lisp
│   │   ├── timer.lisp
│   │   ├── env-var.lisp
│   │   ├── config-lines.lisp
│   │   ├── config-ini.lisp
│   │   ├── config-env.lisp
│   │   ├── package-action.lisp
│   │   ├── secret.lisp
│   │   ├── user.lisp
│   │   ├── group.lisp
│   │   ├── authorized-key.lisp
│   │   ├── permissions.lisp
│   │   ├── mount.lisp
│   │   ├── sysctl.lisp
│   │   ├── kernel-module.lisp
│   │   ├── hostname.lisp
│   │   ├── locale.lisp
│   │   ├── firewall.lisp
│   │   ├── cron.lisp
│   │   ├── command.lisp
│   │   ├── clone.lisp
│   │   └── stow.lisp
│   ├── pipeline.lisp
│   ├── privilege.lisp
│   ├── dsl.lisp
│   └── cli.lisp
├── tests/               # Test suite
│   ├── package.lisp
│   ├── helpers.lisp
│   ├── dsl/
│   ├── features/
│   ├── pipeline/
│   ├── executors/
│   └── actions/
├── build.sh
├── linacs.asd
└── README.md
```

### Building

```bash
# Build the executable
./build.sh

# Run in development mode
sbcl --eval '(asdf:load-system :linacs)'
```

### Portability

LINACS targets SBCL. The build script (`build.sh`) uses `sb-ext:save-lisp-and-die`
to produce a standalone executable, and the terminal-handling code in
`read-sudo-password` (src/action-types/helpers.lisp) uses `sb-unix` and
`sb-posix` for echo-disabled password prompts. A pure-ANSI fallback exists
and is reached automatically on non-SBCL implementations or when the
sb-posix contrib is not loaded, but full portability to another Common Lisp
implementation (CCL, ABCL, ECL) is not currently a goal of the core project.

### Running Tests

```bash
# Run all tests
sbcl --load run-all-tests.lisp

# Run simple tests
sbcl --load run-simple-tests.lisp

# Run specific test module
sbcl --eval '(load "tests/package.lisp")' \
     --eval '(load "tests/actions/identity.lisp")' \
     --eval '(fiveam:run-all-tests :summary nil)' \
     --eval '(quit)'
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `sbcl --load run-all-tests.lisp`
5. Submit a pull request

## License

MIT License - See LICENSE file for details
