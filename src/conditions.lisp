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
;;;;   docs/how-to-debug.md.

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
  "Wrap BODY with standard RETRY/SKIP/ABORT restarts."
  `(restart-case (progn ,@body)
     (retry () :report "Try again" ,@(when on-retry `((funcall ,on-retry))))
     (skip () :report "Skip this action and continue" ,@(when on-skip `((funcall ,on-skip))))
     (abort-processing () :report "Stop processing" ,@(when on-abort `((funcall ,on-abort))))))
