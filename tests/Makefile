# Makefile for LINACS Test Suite

.PHONY: help test clean setup-lisp install-deps

# Target directories
TEST_DIR := /tmp/linacs-test-env
SBCL_USER_INIT := $(TEST_DIR)/sbcl-init.lisp

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
	@echo "(ql:quickload :fiveam)" > $(SBCL_USER_INIT)
	@echo "(uiop:quit)" >> $(SBCL_USER_INIT)
	@sbcl --eval "$(cat $(SBCL_USER_INIT))" --load $(SBCL_USER_INIT) 2>/dev/null || \
	(echo "FiveAM not installed. Please run: (ql:quickload :fiveam) in SBCL" && false)

test: setup-lisp install-deps
	@echo "Running LINACS test suite..."
	@cd $(TEST_DIR)
	@echo "(asdf:load-system :linacs-tests)" > run-tests.lisp
	@echo "(flet ((run () (fiveam:run-all-tests :linacs-tests) (uiop:quit))) (run))" >> run-tests.lisp
	@sbcl --eval "$(cat $(SBCL_USER_INIT))" --load run-tests.lisp
	@rm -f $(SBCL_USER_INIT)

clean:
	@echo "Cleaning test environment..."
	@rm -rf $(TEST_DIR)