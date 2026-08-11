# Makefile for LINACS Test Suite

.PHONY: help test clean setup-lisp install-deps

# Target directories
TEST_DIR := /tmp/linacs-test-env
SBCL_USER_INIT := $(TEST_DIR)/sbcl-init.lisp
SBCL := sbcl

help:
	@echo "LINACS Test Suite Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make setup-lisp  - Set up local Lisp environment with dependencies"
	@echo "  make install-deps - Install test dependencies (FiveAM)"
	@echo "  make test         - Run the test suite"
	@echo "  make clean        - Clean test environment"

setup-lisp:
	@echo "Setting up local Lisp environment..."
	@mkdir -p $(TEST_DIR)
	@echo "(quit)" > $(SBCL_USER_INIT)

install-deps:
	@echo "Installing FiveAM test framework..."
	@$(SBCL) --non-interactive --eval '(require :asdf)' \
	  --eval '(handler-case (ql:quickload :fiveam) (error (c) (format t "FiveAM install failed: ~a~%" c) (uiop:quit 1)))' || \
	(echo "FiveAM not installed. Please run: (ql:quickload :fiveam) in SBCL" && false)

test: setup-lisp install-deps
	@echo "Running LINACS test suite..."
	@$(SBCL) --non-interactive \
	  --eval '(require :asdf)' \
	  --eval '(push #P"$(CURDIR)/../" asdf:*central-registry*)' \
	  --eval '(push #P"$(CURDIR)/" asdf:*central-registry*)' \
	  --eval '(asdf:load-system :linacs-tests)' \
	  --eval '(unless (fiveam:run-all-tests) (uiop:quit 1))'

clean:
	@echo "Cleaning test environment..."
	@rm -rf $(TEST_DIR)
