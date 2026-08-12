;;;; src/conditions.lisp
;;;;
;;;; Every condition class LINACS can signal, plus the shared RETRY/SKIP/ABORT
;;;; restart vocabulary. LINACS uses the Common Lisp Condition System for all
;;;; error handling instead of ad hoc exceptions: every signaled condition is
;;;; a real CLOS condition class, and the conditions that make sense to
;;;; resolve interactively (ACTION-CONFLICT, MISSING-PROVIDER) carry real,
;;;; named restarts rather than only ever aborting.
;;;;
;;;; Usage:
;;;;   Conditions are signaled with plain ERROR from wherever they're detected
;;;;   (actions.lisp, providers.lisp, features.lisp, ...), e.g.:
;;;;
;;;;     (error 'missing-provider :feature :editor)
;;;;
;;;;   and caught either by the CLI (src/cli.lisp's WITH-CLI-ERROR-REPORT, which
;;;;   prints a one-line message and exits) or, when driving LINACS from a live
;;;;   REPL, by an interactive debugger showing the real restarts -- see
;;;;   docs/user-manual.md §4.4.

(in-package :linacs.core)

(define-condition linacs-error (error)
  ((message :initarg :message :reader linacs-error-message :initform ""))
  (:report (lambda (c stream) (format stream "~a" (linacs-error-message c))))
  (:documentation "Base condition for all LINACS-signaled errors."))

(define-condition missing-provider (linacs-error)
  ((feature :initarg :feature :reader missing-provider-feature))
  (:report (lambda (c stream)
             (if (and (slot-boundp c 'message) (plusp (length (linacs-error-message c))))
                 (format stream "~a" (linacs-error-message c))
                 (format stream "No provider found for feature ~a."
                         (missing-provider-feature c))))))

(define-condition action-conflict (linacs-error)
  ((identity :initarg :identity :reader action-conflict-identity)
   (def-a :initarg :def-a :reader action-conflict-def-a)
   (def-b :initarg :def-b :reader action-conflict-def-b))
  (:report (lambda (c stream)
             (format stream "Conflicting definitions for ~s~%  Definition A: ~a~%  Definition B: ~a"
                     (action-conflict-identity c)
                     (action-conflict-def-a c)
                     (action-conflict-def-b c)))))

(define-condition dsl-form-conflict (linacs-error)
  ((name :initarg :name :reader dsl-form-conflict-name)
   (existing :initarg :existing :reader dsl-form-conflict-existing :initform nil))
  (:report (lambda (c stream)
             (format stream "A DSL form ~a is already registered~@[ by ~a~] and cannot be redefined.~%~%No plugin or project may silently shadow an existing home-level form."
                     (dsl-form-conflict-name c)
                     (dsl-form-conflict-existing c)))))

(define-condition insufficient-privileges (linacs-error)
  ((count :initarg :count :reader insufficient-privileges-count))
  (:report (lambda (c stream)
             (format stream "This plan requires installing packages, but linacs is not running with~%sufficient privileges to do so.~%~%  Affected actions: ~d :PACKAGE actions"
                     (insufficient-privileges-count c))))
  (:documentation "No longer signaled by the core pipeline as of the
per-action escalation model (see privilege.lisp's PREFLIGHT-NOTICE) --
kept defined in case a project or plugin still wants this shape of
condition for its own use."))

(define-condition permission-denied-mid-run (linacs-error)
  ((target :initarg :target :reader permission-denied-target))
  (:report (lambda (c stream)
             (format stream "Permission denied while executing :PACKAGE ~s.~%  Action required: Install package."
                     (permission-denied-target c))))
  (:documentation "No longer signaled by the core pipeline as of the
per-action escalation model -- a failed privileged command now signals
EXECUTION-FAILURE from RUN-PRIVILEGED instead. Kept defined in case a
project or plugin still wants this shape of condition for its own use."))

(define-condition non-interactive-prompt (linacs-error)
  ((target :initarg :target :reader non-interactive-prompt-target))
  (:report (lambda (c stream)
             (format stream "Cannot prompt for secret ~a -- no interactive terminal available."
                     (non-interactive-prompt-target c)))))

(define-condition fact-prober-conflict (linacs-error)
  ((fact-key :initarg :fact-key :reader fact-prober-conflict-key)
   (registrants :initarg :registrants :reader fact-prober-conflict-registrants))
  (:report (lambda (c stream)
             (format stream "Multiple fact probers registered for ~a.~%  Registered by: ~{~a~^, ~}~%~%LINACS cannot determine which prober's result to trust and will not guess."
                     (fact-prober-conflict-key c)
                     (fact-prober-conflict-registrants c)))))

(define-condition missing-template-renderer (linacs-error)
  ((template :initarg :template :reader missing-template-renderer-template)
   (expected-symbol :initarg :expected-symbol :reader missing-template-renderer-expected))
  (:report (lambda (c stream)
             (format stream "No renderer found for template ~s~%  Expected: ~a in :LINACS-TEMPLATES"
                     (missing-template-renderer-template c)
                     (missing-template-renderer-expected c)))))

(define-condition execution-failure (linacs-error)
  ((action-type :initarg :action-type :reader execution-failure-action-type)
   (target :initarg :target :reader execution-failure-target)
   (underlying :initarg :underlying :reader execution-failure-underlying :initform nil))
  (:report (lambda (c stream)
             (format stream "Failed to execute ~a ~a~%  Error: ~a"
                     (execution-failure-action-type c)
                     (execution-failure-target c)
                     (execution-failure-underlying c)))))

(define-condition file-discovery-load-error (linacs-error)
  ((path :initarg :path :reader file-discovery-load-error-path)
   (underlying :initarg :underlying :reader file-discovery-load-error-underlying :initform nil))
  (:report (lambda (c stream)
             (format stream "Failed to load ~a during project-local file discovery.~%  Error: ~a"
                     (file-discovery-load-error-path c)
                     (file-discovery-load-error-underlying c)))))

(define-condition pipeline-aborted-by-hook (linacs-error)
  ((hook-point :initarg :hook-point :initform nil :reader pipeline-aborted-by-hook-point))
  (:report (lambda (c stream)
             (format stream "Pipeline aborted by hook at ~a." (pipeline-aborted-by-hook-point c)))))

(define-condition dependency-cycle (linacs-error)
  ((cycle :initarg :cycle :reader dependency-cycle-cycle))
  (:report (lambda (c stream)
             (format stream "Dependency cycle detected among actions: ~{~a~^ -> ~}"
                     (dependency-cycle-cycle c)))))

;;; Restarts -- thin macros so callers get a consistent vocabulary of
;;; retry/skip/abort plus condition-specific choices, per the spec's
;;; "Condition System Integration" section.

(defmacro with-linacs-restarts ((&key on-retry on-skip on-abort) &body body)
  "Wrap BODY with standard RETRY/SKIP/ABORT restarts. The keyword callbacks,
when supplied, give each restart a real body: RETRY runs (funcall ON-RETRY),
SKIP runs (funcall ON-SKIP), ABORT-PROCESSING runs (funcall ON-ABORT). The
restart-clause value is the value of the whole form. Callers that pass no
callbacks get inert restarts (they transfer control and continue), which is
fine for an interactive debugger but not for the compiled CLI's restart
menu -- see EXECUTE-ACTION, %LOAD-LISP-FILE, and RESOLVE-SECRET-PROMPT."
  `(restart-case (progn ,@body)
     (retry () :report "Try again" ,@(when on-retry `((funcall ,on-retry))))
     (skip () :report "Skip this action and continue" ,@(when on-skip `((funcall ,on-skip))))
     (abort-processing () :report "Stop processing" ,@(when on-abort `((funcall ,on-abort))))))

;;; --- Interactive restart menu (compiled CLI) --------------------------------
;;;
;;; WITH-CLI-ERROR-REPORT (src/cli.lisp) and EXECUTE-PLAN (src/pipeline.lisp)
;;; bind HANDLE-LINACS-ERROR-INTERACTIVELY around resolution and execution.
;;; It runs at signal time -- before any restart frame is unwound -- so on an
;;; interactive terminal it can present the real restart menu and invoke a
;;; restart (RETRY/SKIP/ABORT for execution, USE-FIRST/USE-SECOND for
;;; conflicts, SPECIFY-PROVIDER/SKIP-FEATURE for providers). On a
;;; non-interactive terminal (CI, piped output) it returns normally and the
;;; enclosing HANDLER-CASE handles the condition exactly as before: print +
;;; exit in the CLI, per-action failure handling in EXECUTE-PLAN.

(defparameter *linacs-restart-descriptions*
  '(    (retry . "Try again")
    (skip . "Skip this action and continue")
    (abort-processing . "Stop processing")
    (force . "Force overwrite the conflicting file/symlink")
    (use-first . "Keep definition A (the existing action)")
    (use-second . "Keep definition B (the new action)")
    (specify-provider . "Manually select a provider")
    (skip-feature . "Continue without this feature"))
  "Human-readable text for each LINACS restart name, mirroring the :report
strings the restarts are declared with. Used by the restart menu, since the
report text of a restart is not portably readable.")

(defun linacs-restart-p (restart)
  "T if RESTART is one LINACS itself establishes, rather than the ambient
SBCL CONTINUE/ABORT/EXIT restarts that are always present in a debugger."
  (assoc (restart-name restart) *linacs-restart-descriptions*))

(defun compute-linacs-restarts ()
  "The LINACS restarts active at the current point, in COMPUTE-RESTARTS order."
  (remove-if-not #'linacs-restart-p (compute-restarts)))

(defun restart-description (restart)
  (or (cdr (assoc (restart-name restart) *linacs-restart-descriptions*))
      (string-downcase (string (restart-name restart)))))

(defvar *restart-menu-p* nil
  "T when the CLI has detected an interactive terminal and wants the restart
menu presented. Bound by WITH-CLI-ERROR-REPORT and EXECUTE-PLAN; tests may
bind it to force or suppress menu presentation regardless of the terminal.")

(defvar *linacs-abort-function*
  (lambda () (uiop:quit 1))
  "Function invoked when the interactive restart menu's ABORT choice is made.
Defaults to quitting; tests and API callers may rebind it to something that
does not terminate the Lisp image.")

(defun present-restart-menu (condition)
  "Print CONDITION and a numbered menu of the active LINACS restarts, read a
choice from *QUERY-IO*, and invoke the chosen restart. A trailing synthetic
[ABORT] entry calls *LINACS-ABORT-FUNCTION*. Loops until a valid choice is
made; never returns normally."
  (loop
    (format t "~&[error] ~a~%" condition)
    (let ((restarts (compute-linacs-restarts)))
      (format t "Restarts:~%")
      (loop for r in restarts for i from 0
            do (format t "  ~d. [~a] ~a~%" i (restart-name r) (restart-description r)))
      (format t "  ~d. [ABORT] Stop processing~%" (length restarts))
      (force-output)
      (let* ((line (read-line *query-io* nil nil))
             (n (and line (ignore-errors (parse-integer (string-trim " " line))))))
        (cond
          ((and n (< n (length restarts)))
           (invoke-restart-interactively (nth n restarts)))
          ((and n (= n (length restarts)))
           (funcall *linacs-abort-function*))
          (t (format t "  Please choose a restart number.~%")))))))

(defun handle-linacs-error-interactively (condition)
  "Interactive handler for LINACS-ERROR. On an interactive terminal with
LINACS restarts actually active, presents the restart menu (never returning
normally). Otherwise returns normally, so the enclosing HANDLER-CASE handles
the condition exactly as it would have before the menu existed."
  (when (and (or *restart-menu-p* (interactive-stream-p *query-io*))
             (compute-linacs-restarts))
    (present-restart-menu condition)))
