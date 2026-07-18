;;;; src/pipeline.lisp
;;;;
;;;; The five-step Execution Model (facts+profile, resolve, dedup, order,
;;;; execute -- step 0, Discovery, runs separately and earlier; see
;;;; discovery.lisp and cli.lisp), plus pipeline-hook registration for
;;;; the :after-resolve and :before-execute extension points.
;;;;
;;;; Usage:
;;;;   Driven by every CLI command via src/cli.lisp; to call it directly (e.g.
;;;;   from a REPL, after DISCOVER-PROJECT has already loaded a project):
;;;;
;;;;     (run-pipeline :profile :work-laptop :project-root "." :execute-mode :plan-only)

(in-package :linacs.core)

(defvar *pipeline-hooks* (make-hash-table :test 'eq)
  "Maps hook point (:after-resolve or :before-execute) -> list of hook
functions, run in registration order.")

(defun register-pipeline-hook (point hook-fn)
  (setf (gethash point *pipeline-hooks*)
        (append (gethash point *pipeline-hooks*) (list hook-fn))))

(defun run-hooks (point &rest args)
  (dolist (hook (gethash point *pipeline-hooks*))
    (apply hook args)))

(defun collect-actions-from-features (use-feature-requests)
  "Step 2 (feature half): walk the feature graph starting from each
use-feature request, resolving :requires, and call each selected provider.
Returns a flat list of provider-tagged action plists."
  (let* ((root-names (mapcar (lambda (r) (getf r :feature)) use-feature-requests))
         (ordered-features (resolve-feature-graph root-names))
         (via-table (make-hash-table :test 'eq)))
    (dolist (r use-feature-requests) (setf (gethash (getf r :feature) via-table) (getf r :via)))
    (loop for fname in ordered-features
          append (let* ((via (gethash fname via-table))
                        (provider-fn (select-provider fname via))
                        (raw-actions (funcall provider-fn *facts*)))
                   (mapcar (lambda (a)
                             (append (copy-list a)
                                     (list :priority :provider
                                           :source (format nil "provider for feature ~a" fname))))
                           raw-actions)))))

(defun run-pipeline (&key profile project-root (execute-mode :apply))
  "Run Execution Model steps 1-5 against the already-discovered home
definition (i.e. discovery, step 0, must already have run via
DISCOVER-PLUGINS / DISCOVER-PROJECT). EXECUTE-MODE is :apply, :check, or
:plan-only (resolve/order but do not call EXECUTE-ACTION at all)."
  ;; Step 1: probe facts, then merge selected profile.
  (probe-all-facts)
  (apply-profile profile)

  ;; Step 2: walk the feature graph + collect user-level forms.
  (let* ((home (run-current-home-thunk))
         ;; Populate *feature-customs* so providers can read it
         (ignored (register-feature-customs (getf home :use-features)))
         (provider-actions (collect-actions-from-features (getf home :use-features)))
         (user-actions (mapcar (lambda (a) (append (copy-list a) (list :project-root project-root)))
                               (getf home :actions)))
         (all-actions (append user-actions provider-actions)))

    ;; Silence the compiler
    (declare (ignore ignored))

    (run-hooks :after-resolve *facts* all-actions)

    ;; Step 3: deduplicate.
    (let ((deduped (dedup-actions all-actions)))

      ;; Step 4: order topologically.
      (let ((ordered (order-actions deduped)))

        (run-hooks :before-execute *facts* ordered)

        (unless (eq execute-mode :plan-only)
          ;; Informational only, before a real :apply -- never blocks.
          (when (eq execute-mode :apply)
            (preflight-notice ordered))

          ;; Step 5: execute (or check) each action's built-in executor, in order,
          ;; honoring :disabled + the :prune-explicitly-disabled trait.
          (let ((prune (member :prune-explicitly-disabled (getf home :traits))))
            (dolist (action ordered)
              (if (and (getf action :disabled) prune)
                  ;; Pruning disabled actions: respect execute-mode
                  (if (eq execute-mode :apply)
                      (execute-action action :mode :remove)
                      (execute-action action :mode :check))
                  (unless (getf action :disabled)
                    (execute-action action :mode execute-mode))))))

        (values ordered home)))))
