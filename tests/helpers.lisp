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

;; Scratch-directory helpers shared by filesystem fixtures in several suites.
(defun make-scratch-dir (&optional (prefix "linacs-test"))
  "Create and return a fresh scratch directory under the system temp dir."
  (let ((dir (merge-pathnames
              (format nil "~a-~a-~a/"
                      prefix
                      (string-downcase (string (gensym)))
                      (random 1000000))
              (uiop:temporary-directory))))
    (ensure-directories-exist dir)
    dir))

(defmacro with-scratch-dir ((var) &body body)
  "Bind VAR to a fresh scratch directory for the duration of BODY, then
delete it."
  `(let ((,var (make-scratch-dir)))
     (unwind-protect (progn ,@body)
       (uiop:delete-directory-tree ,var :validate t :if-does-not-exist :ignore))))
