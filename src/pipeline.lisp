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
                        (ignored (reset-facts-read)))
                   (declare (ignore ignored))
                   (multiple-value-bind (provider-fn provider-name)
                       (select-provider fname via)
                     (let ((raw-actions (funcall provider-fn *facts*)))
                       (mapcar (lambda (a)
                                 (let* ((id (action-identity a))
                                        (prov (list :feature fname
                                                    :provider provider-name
                                                    :facts-snapshot (snapshot-facts-read))))
                                   (register-provenance id prov)
                                   (append (copy-list a)
                                           (list :priority :provider
                                                 :source (format nil "provider ~a for feature ~a"
                                                                 provider-name fname)))))
                               raw-actions)))))))

(defun run-pipeline (&key profile project-root (execute-mode :plan-only) continue-on-error)
  "Run Execution Model steps 1-5 against the already-discovered home
definition (i.e. discovery, step 0, must already have run via
DISCOVER-PLUGINS / DISCOVER-PROJECT). EXECUTE-MODE is :apply, :check, or
:plan-only (resolve/order but do not call EXECUTE-ACTION at all).
CONTINUE-ON-ERROR means skip failed actions and their dependents rather
than aborting the entire run."

  (probe-all-facts)
  (apply-profile profile)
  (clrhash *action-results*)

  (let* ((home (run-current-home-thunk))
          (*package-preference-chain* (or (getf home :package-preference) '(:system)))
          (ignored (register-feature-customs (getf home :use-features)))
         (provider-actions (collect-actions-from-features (getf home :use-features)))
         (user-actions (mapcar (lambda (a)
                                 (let* ((id (action-identity a))
                                        (loc (getf a :location))
                                        (prov (list :source (or (getf a :source) "user")
                                                    :location loc)))
                                   (register-provenance id prov)
                                   (append (copy-list a) (list :project-root project-root))))
                               (getf home :actions)))
         (all-actions (append user-actions provider-actions)))
    (declare (ignore ignored))
    (run-hooks :after-resolve *facts* all-actions)

    (let ((deduped (dedup-actions all-actions)))
      (let ((ordered (order-actions deduped)))
        (run-hooks :before-execute *facts* ordered)

        (unless (eq execute-mode :plan-only)
          (preflight-notice ordered)

          (let* ((prune (member :prune-explicitly-disabled (getf home :traits)))
                 (failed-ids (make-hash-table :test 'equal)))
            (dolist (action ordered)
              (let ((id (action-identity action)))
                (cond
                  ((and (getf action :disabled) prune)
                   (execute-action action :mode (if (eq execute-mode :apply) :remove :check)))
                  ((getf action :disabled)
                   (when *progress-reporter*
                     (funcall *progress-reporter* action :skipped))
                   nil)
                  ((and continue-on-error
                        (some (lambda (dep) (gethash dep failed-ids))
                              (getf action :depends-on)))
                   (setf (gethash id *action-results*) (list :status :skipped))
                   (when *progress-reporter*
                     (funcall *progress-reporter* action :skipped))
                   (when (>= linacs.log:*verbosity* 2)
                     (linacs.log:info "Skipping ~a -- depends on prior failure" id)))
                  (t
                   (handler-case
                       (execute-action action :mode execute-mode)
                     (linacs-error (e)
                       (setf (gethash id *action-results*) (list :status :failed :error e))
                       (setf (gethash id failed-ids) t)
                       (if continue-on-error
                           (linacs.log:warn* "~a failed; continuing" id)
                           (error e))))))))))
        (values ordered home)))))
