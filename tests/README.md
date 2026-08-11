# LINACS Test Suite

This directory contains the comprehensive test suite for the LINACS core implementation.

## Structure

```
tests/
├── linacs-tests.asd          # ASDF system definition for tests
├── package.lisp              # Test package definition
├── helpers.lisp              # Test utilities and fixtures
├── Makefile                  # Makefile-based runner (see below)
├── setup.sh                  # Sets up a local SBCL/Quicklisp test env
├── actions/                  # Action identity, deduplication, ordering tests
├── api/                      # :linacs.api public-surface tests
├── cli/                      # CLI flag-parsing tests
├── dsl/                      # DSL macro tests and validation
├── executors/                # Action executor tests
├── facts/                    # Fact schema tests
├── features/                 # Feature graph resolution tests
├── pipeline/                 # Pipeline execution tests
├── privilege/                # Sudo/privilege handling tests
└── profiles/                 # Profile metadata tests
```

The canonical entry point is `run-all-tests.lisp` at the linacs project
root, which loads the whole suite and prints a pass/fail summary. The
`linacs-tests.asd` system definition registers every test file, so
`asdf:load-system :linacs-tests` (or `make test`) runs the identical
coverage.

## Running Tests

### Canonical: `run-all-tests.lisp` (from the linacs root)

```bash
cd linacs
sbcl --load run-all-tests.lisp
```

This loads LINACS, every test module, and runs the whole suite, printing a
pass/fail summary. It is the single source of truth for what gets tested.

### Using ASDF

From a Lisp REPL:

```lisp
;; Add both the linacs root and the tests dir to the ASDF registry
;; (linacs-tests.asd lives under tests/ and depends on "linacs")
(push #P"/path/to/linacs-project/linacs/" asdf:*central-registry*)
(push #P"/path/to/linacs-project/linacs/tests/" asdf:*central-registry*)

;; Load the test system
(asdf:load-system :linacs-tests)

;; Run all tests (run-all-tests exercises every registered suite)
(fiveam:run-all-tests)
```

### Using `make test`

From the `linacs/tests` directory, `make test` runs the same suite via
ASDF and exits non-zero if any check fails (usable in CI).

Note: the master suite is the `linacs-tests` symbol in the
`linacs-tests` package. FiveAM's `run!` needs that symbol, not the
`:linacs-tests` keyword — prefer `(fiveam:run-all-tests)` or
`(fiveam:run! (find-symbol "LINACS-TESTS" :linacs-tests))`.

### Using Roswell

```bash
cd linacs
ros run --load run-all-tests.lisp
```

## Test Organization

### Actions Tests

- **identity.lisp**: Tests action identity computation for all action types
- **dedup.lisp**: Tests action deduplication and conflict resolution
- **ordering.lisp**: Tests topological sorting of actions

### DSL Tests

- **macros.lisp**: Tests DSL macro expansion (define-home, use-feature, file, etc.)
- **validation.lisp**: Tests DSL argument validation
- **dsl-form-registration.lisp**: Tests `define-dsl-form` /
  `define-action-macro` / `register-dsl-form` (plugin-added home-level
  forms, reachability from `:linacs.api`, `dsl-form-conflict` on
  duplicates and on shadowing built-ins)

### Features Tests

- **graph.lisp**: Tests feature dependency graph resolution and cycle detection

### Pipeline Tests

- **execution.lisp**: Tests pipeline execution flow
- **disabled-actions.lisp**: Tests how `:disabled t` actions are handled
  under the `:prune-explicitly-disabled` trait
- **hooks.lisp**: Tests `register-pipeline-hook` behavior

### CLI Tests

- **flag-parsing.lisp**: Tests `parse-args` / CLI flag handling

### Facts Tests

- **schema.lisp**: Tests fact probing and type validation

### Privilege Tests

- **basics.lisp**: Tests sudo/privilege detection and escalation logic

### Profiles Tests

- **metadata.lisp**: Tests profile definition, application, and metadata

### API Tests

- **surface.lisp**: Tests the `:linacs.api` public package surface (what
  is exported, and that a `(:use :cl :linacs.api)` consumer sees it)

### Executors Tests

Each executor is tested using `:check` mode to verify idempotency without side effects:

- **copy-file.lisp**: Tests file copying with template rendering
- **ensure-dir.lisp**: Tests directory creation and mode checking
- **symlink.lisp**: Tests symlink creation
- **service.lisp**: Tests systemd service management
- **config-lines.lisp**: Tests line-based file manipulation
- **package-action.lisp**: Tests package installation checks

## Running Specific Test Suites

```lisp
;; Run a specific suite (the suite symbol lives in the linacs-tests package)
(fiveam:run! (find-symbol "ACTION-IDENTITY" :linacs-tests))

;; Run tests matching a pattern
(fiveam:run-tests "action-identity")

;; Run a specific test
(fiveam:run-test (find-symbol "ACTION-IDENTITY-TEST-SIMPLE-IDENTITY" :linacs-tests))
```

## Adding New Tests

1. Create a new file in the appropriate module directory
2. Define a test suite with `def-suite`
3. Define individual tests using `test`
4. Add assertions using `is`, `signals-error`, etc.
5. Ensure all tests use `:check` mode for executors

Example:

```lisp
(in-package #:linacs-tests)

(def-suite my-new-feature :description "Tests for my new feature")
(in-suite my-new-feature)

(test test-something
  (is (equal (foo) "bar"))
  (is (plusp (bar))))
```

## Test Utilities

The test helpers provide useful utilities:

- `reset-registries`: Clears all LINACS registries for clean test state
- `make-fixture-home`: Creates a minimal home definition for testing
- `fixture-facts`: Returns a set of fixture facts for testing

## Running in CI/CD

Example GitHub Actions workflow:

```yaml
- name: Run LINACS Tests
  run: |
    cd linacs
    sbcl --load run-all-tests.lisp
```

## Expected Coverage

The test suite covers:
- ✅ All action executor types (in :check mode)
- ✅ Action identity computation
- ✅ Action deduplication and conflict resolution
- ✅ Action topological ordering
- ✅ DSL macro expansion
- ✅ DSL argument validation
- ✅ Feature graph resolution
- ✅ Pipeline execution flow
- ✅ Idempotency guarantees
- ✅ Error handling (where applicable)

## Future Enhancements

Potential areas for additional test coverage:
- Privilege escalation edge cases
- Template rendering tests
- Catalog lookups
- Fact probing tests
- Provider selection tests
- Interactive secret prompt tests
- Edge cases for all executors