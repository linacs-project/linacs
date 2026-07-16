# LINACS Test Suite

This directory contains the comprehensive test suite for the LINACS core implementation.

## Structure

```
tests/
├── linacs-tests.asd          # ASDF system definition for tests
├── package.lisp              # Test package definition
├── helpers.lisp              # Test utilities and fixtures
├── run.lisp                  # Test runner
└── modules/
    ├── actions/              # Action identity, deduplication, ordering tests
    ├── dsl/                  # DSL macro tests and validation
    ├── features/             # Feature graph resolution tests
    ├── pipeline/             # Pipeline execution tests
    └── executors/            # Action executor tests
        ├── copy-file.lisp
        ├── ensure-dir.lisp
        ├── symlink.lisp
        ├── service.lisp
        ├── config-lines.lisp
        └── package-action.lisp
```

## Running Tests

### Using ASDF

From a Lisp REPL:

```lisp
;; Add the tests directory to the ASDF registry
(push #P"/path/to/linacs-project/linacs/tests/" asdf:*central-registry*)

;; Load the test system
(asdf:load-system :linacs-tests)

;; Run all tests
(fiveam:run-all-tests :linacs-tests)

;; Or run from the test directory
(fiveam:run-all-tests :linacs-tests)
```

### Using sbcl

```bash
# Build the test system
cd /path/to/linacs-project
sbcl --eval "(asdf:load-system :linacs-tests)" \
     --eval "(flet ((run () (fiveam:run-all-tests :linacs-tests))) (run) (exit))" \
     --quit
```

### Using Roswell

```bash
ros run -s linacs-tests
```

## Test Organization

### Actions Tests

- **identity.lisp**: Tests action identity computation for all action types
- **dedup.lisp**: Tests action deduplication and conflict resolution
- **ordering.lisp**: Tests topological sorting of actions

### DSL Tests

- **macros.lisp**: Tests DSL macro expansion (define-home, use-feature, file, etc.)
- **validation.lisp**: Tests DSL argument validation

### Features Tests

- **graph.lisp**: Tests feature dependency graph resolution and cycle detection

### Pipeline Tests

- **execution.lisp**: Tests pipeline execution flow

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
;; Run a specific suite
(fiveam:run-suite :action-identity)

;; Run tests matching a pattern
(fiveam:run-tests "action-identity")

;; Run a specific test
(fiveam:run-test 'action-identity-test-simple-identity)
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
    sbcl --eval "(asdf:load-system :linacs-tests)" \
         --eval "(progn (fiveam:run-all-tests :linacs-tests) (uiop:quit))"
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