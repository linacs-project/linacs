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
  "Register HOOK-FN at hook point POINT. Duplicate registrations of the
same function object are ignored (EQ identity), so re-running discovery
or calling MAIN more than once in a long-lived Lisp image cannot
accumulate duplicate hooks. Returns HOOK-FN."
  (let ((hooks (gethash point *pipeline-hooks*)))
    (unless (member hook-fn hooks :test #'eq)
      (setf (gethash point *pipeline-hooks*) (append hooks (list hook-fn))))
    hook-fn))

(defun run-hooks (point &rest args)
  (dolist (hook (gethash point *pipeline-hooks*))
    (apply hook args)))

(defvar *project-root* "."
  "The project root, bound to the -C/--root value during resolution (step
2 of the Execution Model) and execution. Providers and pipeline hooks
read it to locate the project's assets -- e.g. deciding whether
<name>/ exists for stow mode -- instead of (truename \".\"), which
is wrong whenever linacs is invoked with -C from a different cwd.
Provider actions are also tagged with an equivalent :project-root plist
entry so the file-related executors (:copy-file, :stow, ...) resolve
their :from/:target sources under it at execution time.")

(defvar *asset-root* #P"./"
  "The asset root: where :from sources and stow packages resolve, relative
to the project root. Defaults to the project root itself (the convention
is plain repo-root packages -- there is no files/ directory). A home may
override it via DEFINE-HOME's :asset-root option -- e.g. :asset-root \"..\"
when the linacs machinery lives in a linacs/ subfolder of a dotfiles repo
whose packages sit at the repo root. RESOLVE-PLAN binds it to the
absolute, canonicalized path for the whole resolution + execution scope
and stamps it onto every action as :asset-root so executors resolve under
it at execution time.")

(defun resolve-asset-root (project-root home)
  "The absolute, canonicalized asset root for PROJECT-ROOT and HOME's
:asset-root setting (a path relative to the project root; default \".\" --
the project root itself). Canonicalized via TRUENAME when the directory
exists, so a \"..\" asset root yields a clean path suitable for symlink
creation."
  (let* ((config (uiop:ensure-directory-pathname (or project-root ".")))
         (rel (uiop:ensure-directory-pathname (or (getf home :asset-root) ".")))
         (merged (merge-pathnames rel config)))
    (if (probe-file merged)
        (namestring (truename merged))
        (namestring (uiop:ensure-directory-pathname merged)))))

(defun action-asset-root (action)
  "The absolute asset root for ACTION: its stamped :asset-root if present
(installed by RESOLVE-PLAN), else *ASSET-ROOT* merged against the action's
:project-root (or *PROJECT-ROOT*). This makes direct executor calls -- e.g.
unit tests that build an action by hand -- resolve under the project root
by default."
  (or (getf action :asset-root)
      (namestring (uiop:ensure-directory-pathname
                   (merge-pathnames (uiop:ensure-directory-pathname *asset-root*)
                                    (uiop:ensure-directory-pathname
                                     (or (getf action :project-root) *project-root*)))))))

(defun collect-actions-from-features (use-feature-requests &key provider-overrides project-root)
  "Step 2 (feature half): walk the feature graph starting from each
use-feature request, resolving :requires, and call each selected provider.
Returns a flat list of provider-tagged action plists.
PROVIDER-OVERRIDES is an alist of (feature . provider) from the CLI's
--provider T=P flag; when present for a feature, it takes precedence over
the use-feature request's own :via. PROVIDER-ROOT (defaults to
*PROJECT-ROOT*) is stamped onto every provider action so file-related
executors resolve their sources under the project root even when linacs is
invoked with -C from a different cwd. The absolute *ASSET-ROOT* is stamped
alongside it."
  (let* ((root-names (mapcar (lambda (r) (getf r :feature)) use-feature-requests))
         (ordered-features (resolve-feature-graph root-names))
         (via-table (make-hash-table :test 'eq)))
    (dolist (r use-feature-requests) (setf (gethash (getf r :feature) via-table) (getf r :via)))
    (loop for fname in ordered-features
          append (let* ((via (or (cdr (assoc fname provider-overrides))
                                 (gethash fname via-table)))
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
                                                               provider-name fname)
                                               :project-root (or project-root *project-root*)
                                               :asset-root *asset-root*))))
                             raw-actions)))))))

(defun resolve-plan (&key profile project-root provider-overrides platform)
  "Run Execution Model steps 1-4: probe facts, merge profile, run home
thunk, resolve features, collect actions, deduplicate, and order.
Returns (values ordered-actions home-plist).
Discoverably named so callers that only need resolution (plan, check,
diff, explain) can skip the execution step entirely.
PROVIDER-OVERRIDES is a (feature . provider) alist from --provider T=P;
PLATFORM overrides the :os fact. Both are applied after the profile merge,
so the command line wins over the home definition. PROJECT-ROOT is bound
to *PROJECT-ROOT* during resolution and stamped onto provider actions as
:project-root; the home's :asset-root (default the project root itself) is
resolved to an absolute path and bound to *ASSET-ROOT* and stamped onto
every action as :asset-root, so providers and file-related executors
locate their sources under it regardless of the invocation cwd."
  (probe-all-facts)
  (apply-profile profile)
  (apply-platform-override platform)
  (clrhash *action-results*)

  (let* ((home (run-current-home-thunk))
         (*package-preference-chain* (or (getf home :package-preference) '(:system)))
         (*project-root* (or project-root "."))
         (*asset-root* (resolve-asset-root *project-root* home))
         (ignored (register-feature-customs (getf home :use-features)))
         (provider-actions (collect-actions-from-features (getf home :use-features)
                                                          :provider-overrides provider-overrides
                                                          :project-root *project-root*))
         (user-actions (mapcar (lambda (a)
                                  (let* ((id (action-identity a))
                                         (loc (getf a :location))
                                         (prov (list :source (or (getf a :source) "user")
                                                     :location loc)))
                                    (register-provenance id prov)
                                    (append (copy-list a)
                                            (list :project-root *project-root*
                                                  :asset-root *asset-root*))))
                                (getf home :actions)))
         (all-actions (append user-actions provider-actions)))
    (declare (ignore ignored))
    (resolve-package-vias all-actions)
    (run-hooks :after-resolve *facts* all-actions)
    (let* ((deduped (dedup-actions all-actions))
           (ordered (order-actions deduped)))
      (run-hooks :before-execute *facts* ordered)
      (values ordered home))))

(defun execute-plan (ordered home &key (mode :apply) continue-on-error)
  "Execute an already-resolved action plan (Execution Model step 5).
MODE is :apply or :check. CONTINUE-ON-ERROR skips failed actions and
their dependents rather than aborting the entire run.
Returns ORDERED so callers can inspect *ACTION-RESULTS* afterward."
  (preflight-notice ordered)
  (preflight-sudo-prompt ordered)

  (let* ((prune (member :prune-explicitly-disabled (getf home :traits)))
         (failed-ids (make-hash-table :test 'equal)))
    (catch 'linacs-abort
      (dolist (action ordered)
        (let ((id (action-identity action)))
          (cond
            ((and (getf action :disabled) prune)
             (execute-action action :mode (if (eq mode :apply) :remove :check)))
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
                 ;; The interactive handler runs at signal time, while the
                 ;; action's RETRY/SKIP/ABORT-PROCESSING restarts are still
                 ;; live -- see HANDLE-LINACS-ERROR-INTERACTIVELY.
                 (handler-bind ((linacs-error #'handle-linacs-error-interactively))
                   (execute-action action :mode mode))
               (linacs-error (e)
                 (setf (gethash id *action-results*) (list :status :failed :error e))
                 (setf (gethash id failed-ids) t)
                 (if continue-on-error
                     (linacs.log:warn* "~a failed; continuing" id)
                     (error e))))))))))
  ordered)

(defun run-pipeline (&key profile project-root (execute-mode :plan-only) continue-on-error
                           provider-overrides platform)
  "Run Execution Model steps 1-5 against the already-discovered home
definition (i.e. discovery, step 0, must already have run via
DISCOVER-PLUGINS / DISCOVER-PROJECT). Composes RESOLVE-PLAN and
EXECUTE-PLAN. EXECUTE-MODE is :apply, :check, or :plan-only
(resolve/order but do not call EXECUTE-ACTION at all).
CONTINUE-ON-ERROR means skip failed actions and their dependents rather
than aborting the entire run.
PROVIDER-OVERRIDES and PLATFORM are forwarded to RESOLVE-PLAN (see there)."
  (multiple-value-bind (ordered home)
      (resolve-plan :profile profile :project-root project-root
                    :provider-overrides provider-overrides :platform platform)
    (unless (eq execute-mode :plan-only)
      (execute-plan ordered home :mode execute-mode :continue-on-error continue-on-error))
    (values ordered home)))
