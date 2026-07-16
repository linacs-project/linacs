(in-package #:linacs-tests)

;; Test helper functions

(defun reset-project-registries ()
  "Reset all LINACS registries to initial state"
  (let ((core (find-package :linacs.core)))
    (when core
      ;; Reset feature registry
      (let* ((feature-registry (find-symbol "*FEATURE-REGISTRY*" core)))
        (if feature-registry
            (setf (symbol-value feature-registry) nil)))
      ;; Reset facts
      (let* ((facts (find-symbol "*FACTS*" core)))
        (if facts
            (setf (symbol-value facts) nil)))
      ;; Reset pipeline hooks
      (let* ((pipeline-hooks (find-symbol "*PIPELINE-HOOKS*" core)))
        (if pipeline-hooks
            (setf (symbol-value pipeline-hooks) nil))))))
