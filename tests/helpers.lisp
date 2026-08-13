(in-package #:linacs-tests)

;; Test helper functions

(defun reset-project-registries ()
  "Reset all LINACS registries to initial state.
Mirrors cli.lisp's RESET-PROJECT-REGISTRIES but operates via symbol
lookup to avoid cross-package dependency at compile time."
  (let ((core (find-package :linacs.core)))
    (when core
      (dolist (sym-name '("*FACT-PROBERS*" "*FACT-METADATA*"
                          "*FEATURE-REGISTRY*"
                          "*PROVIDERS*" "*CATALOGS*" "*PROFILES*"
                          "*PIPELINE-HOOKS*" "*DSL-FORMS*"
                          "*REPOSITORY-METHODS*"))
        (let ((sym (find-symbol sym-name core)))
          (when (and sym (symbol-value sym))
            (clrhash (symbol-value sym)))))
      ;; Plist / list / simple-value vars get reset to nil
      (dolist (sym-name '("*FACTS*" "*CURRENT-HOME-THUNK*"
                          "*CURRENT-HOME-ACTIONS*" "*CURRENT-HOME-USE-FEATURES*"))
        (let ((sym (find-symbol sym-name core)))
          (when sym (setf (symbol-value sym) nil))))
      ;; Clear diagnostics tracking state
      (dolist (sym-name '("*FACTS-READ*" "*PROVENANCE*" "*ACTION-RESULTS*"))
        (let ((sym (find-symbol sym-name core)))
          (when sym
            (if (hash-table-p (symbol-value sym))
                (clrhash (symbol-value sym))
                (setf (symbol-value sym) nil))))))))

;; Master suite that collects all test suites as children
(def-suite linacs-tests
  :description "LINACS master test suite")
