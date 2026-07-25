(in-package #:linacs-tests)

;; Test helper functions

(defun reset-project-registries ()
  "Reset all LINACS registries to initial state.
Mirrors cli.lisp's RESET-PROJECT-REGISTRIES but operates via symbol
lookup to avoid cross-package dependency at compile time."
  (let ((core (find-package :linacs.core)))
    (when core
      (dolist (sym-name '("*FACT-PROBERS*" "*FEATURE-REGISTRY*"
                          "*PROVIDERS*" "*CATALOGS*" "*PROFILES*"
                          "*PIPELINE-HOOKS*"))
        (let ((sym (find-symbol sym-name core)))
          (when (and sym (symbol-value sym))
            (clrhash (symbol-value sym)))))
      ;; Plist / list / simple-value vars get reset to nil
      (dolist (sym-name '("*FACTS*" "*CURRENT-HOME-THUNK*"
                          "*CURRENT-HOME-ACTIONS*" "*CURRENT-HOME-USE-FEATURES*"))
        (let ((sym (find-symbol sym-name core)))
          (when sym (setf (symbol-value sym) nil)))))))
