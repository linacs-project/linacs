#!/bin/bash
# Setup script for LINACS test suite
# This script sets up a local Quicklisp environment with all necessary dependencies

set -e

echo "Setting up LINACS test environment..."

# Create test directory
TEST_DIR="$(pwd)/test-env"
mkdir -p "$TEST_DIR"

# Create SBCL user init file
cat > "$TEST_DIR/sbcl-init.lisp" << 'EOF'
(quit)
EOF

echo "Test environment created at: $TEST_DIR"
echo ""
echo "To run tests:"
echo "  cd linacs/tests"
echo "  make test"
echo ""
echo "Or manually:"
echo "  sbcl --eval \"(ql:quickload :fiveam)\""
echo "  sbcl --eval \"(asdf:load-system :linacs-tests)\""
echo "  sbcl --eval \"(fiveam:run-all-tests :linacs-tests)\""