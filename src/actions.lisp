;;;; src/actions.lisp
;;;;
;;;; Action identity, deduplication, topological ordering, and dispatch. An
;;;; action is a plist (:action <type> :target <t> ...opts); every type has
;;;; exactly one built-in executor (see action-types/) responsible for
;;;; probing and correcting real system state in a single idempotent step --
;;;; there's no separate "current state" model kept anywhere to diff against.
;;;;
;;;; Usage:
;;;;   Executing one action directly (mainly useful for debugging or testing an
;;;;   executor in isolation -- see tests/ and docs/user-manual.md §4.4):
;;;;
;;;;     (execute-action '(:action :copy-file :target "/tmp/x" :from "x") :mode :check)

(in-package :linacs.core)

(deftype action-plist ()
  "A valid action plist has at minimum an :ACTION keyword and a :TARGET."
  '(and list (satisfies action-plist-p)))

(defun action-plist-p (plist)
  (and (consp plist)
       (getf plist :action)
       (getf plist :target)))

(defvar *action-types* (make-hash-table :test 'eq)
  "Maps action type keyword -> executor function of (action &key mode).")

(defvar *package-preference-chain* '(:system)
  "Ordered list of :via methods to try when a :package action has no :via.
Set during RUN-PIPELINE from the home's (package-preference ...) declaration.")

(defvar *action-type-descriptions* (make-hash-table :test 'eq)
  "Maps action type keyword -> a one-line human-readable description, for
`linacs list` and similar reporting. Purely documentation; never consulted
by resolution or execution.")

(defvar *action-identity-functions* (make-hash-table :test 'eq)
  "Maps action type keyword -> function of (action) returning identity.
If no function is registered for a type, the default (cons type target) is used.
Plugin authors register custom identity functions for new action types.")

(defvar *action-type-dedup-behavior* (make-hash-table :test 'eq)
  "Maps action type keyword -> dedup behavior, :conflict (default) or :additive.
:additive types (e.g. :config-lines) keep both same-identity actions at the
same priority, warning instead of signaling ACTION-CONFLICT. Plugin authors
declare the behavior for new action types via the :dedup-behavior keyword on
REGISTER-ACTION-TYPE.")

(defvar *provenance* (make-hash-table :test 'equal)
  "Maps action identity -> provenance plist (:feature :provider :facts-snapshot
or :source :location for user-level actions). Populated during pipeline step 2
and never consulted in normal operation -- zero overhead during execution.")

(defvar *action-results* (make-hash-table :test 'equal)
  "Maps action identity -> result plist (:status :applied :already-met :failed
or :skipped, and optionally :error for failures). Populated during pipeline
step 5 by EXECUTE-ACTION. Used by --continue mode.")

(defvar *progress-reporter* nil
  "When non-nil, a function of (action phase &optional data) called by
EXECUTE-ACTION before and after each action execution.  PHASE is :BEFORE,
:AFTER, or :FAILED.  For :AFTER, DATA is the result plist.  For
:FAILED, DATA is the condition.")

(defvar *capture-subprocess-output* nil
  "When non-nil, RUN-PRIVILEGED in helpers.lisp captures subprocess stdout/stderr
into *CAPTURED-SUBPROCESS-LINES* instead of passing them through to the terminal.
Used by `linacs apply` to show live progress glyphs without subprocess noise.")

(defvar *captured-subprocess-lines* nil
  "List of (stream-type . string) entries captured during subprocess execution
when *CAPTURE-SUBPROCESS-OUTPUT* is non-nil.  Reset per-action in
EXECUTE-ACTION.  Stream-type is :STDOUT or :STDERR.")

(defun register-action-type (type executor-fn &key description identity dedup-behavior)
  (setf (gethash type *action-types*) executor-fn)
  (when description (setf (gethash type *action-type-descriptions*) description))
  (when identity (setf (gethash type *action-identity-functions*) identity))
  (when dedup-behavior (setf (gethash type *action-type-dedup-behavior*) dedup-behavior)))

(defun action-type-description (type)
  (or (gethash type *action-type-descriptions*) ""))

(defun find-executor (type)
  (or (gethash type *action-types*)
      (error 'execution-failure :action-type type :target nil
             :underlying (format nil "No executor registered for action type ~a" type))))

(defun action-type (action) (getf action :action))
(defun action-target (action) (or (getf action :target) (getf action :to)))

(defun action-identity (action)
  "Compute the canonical identity for ACTION. Delegates to the type's
registered identity function in *ACTION-IDENTITY-FUNCTIONS* (set via
REGISTER-ACTION-TYPE :identity), or falls back to (type . target).
Plugin authors register identity functions for new action types so
ACTION-IDENTITY never needs a hardcoded cond chain:

    (register-action-type :my-type #'my-executor
      :identity (lambda (a) (list :my-type (getf a :qualifier) (action-target a))))"
  (let* ((type (action-type action))
         (fn (gethash type *action-identity-functions*)))
    (if fn
        (funcall fn action)
        (cons type (action-target action)))))

(defun register-provenance (action-id provenance)
  "Record PROVENANCE plist for ACTION-ID in *PROVENANCE*."
  (setf (gethash action-id *provenance*) provenance))

(defun action-provenance (action-id)
  "Retrieve the provenance plist for ACTION-ID from *PROVENANCE*, or NIL."
  (gethash action-id *provenance*))

(defun action-result-status (action-id)
  "Retrieve the result status (:applied :already-met :failed :skipped) for
ACTION-ID from *ACTION-RESULTS*, or NIL if not yet executed."
  (let ((result (gethash action-id *action-results*)))
    (and result (getf result :status))))

(defun action-source-label (action)
  "Human-readable label of where ACTION came from, for conflict reports."
  (or (getf action :source) "unspecified"))

(defun same-action-content-p (a b)
  "Two actions are content-equal if their plists are EQUAL once :source,
:priority, and identity-irrelevant bookkeeping keys are stripped."
  (flet ((strip (a) (let ((c (copy-list a)))
                       (remf c :source)
                       (remf c :priority)
                       c)))
    (equal (strip a) (strip b))))

(defun via-available-p (via)
  "Return T if VIA is available on this system.
:system is always available; everything else is checked through facts
by the convention that :via :toolbox -> fact :toolbox-p."
  (if (eq via :system)
      t
      (let ((fact-key (intern (concatenate 'string (string via) "-P") :keyword)))
        (and (fact-known-p fact-key) (fact fact-key)))))

(defun resolve-package-via (action)
  "Choose a :via method for ACTION (which has no :via) by walking the
package-preference chain and picking the first available one.  Warns
and falls back to :system if nothing in the chain is available."
  (let* ((chain (or (getf action :via-preference)
                    *package-preference-chain*
                    '(:system)))
         (available (loop for via in chain
                          when (via-available-p via)
                            collect via)))
    (if available
        (first available)
        (progn
          (linacs.log:warn* "None of the package vias in ~a are available for ~s; falling back to :system"
                            chain (action-target action))
          :system))))

(defun resolve-package-vias (actions)
  "Walk ACTIONS and inject :via for any :package action missing it.
Uses RESOLVE-PACKAGE-VIA which reads *PACKAGE-PREFERENCE-CHAIN*,
dynamically bound during RUN-PIPELINE.  Extends each plist in place
with NCONC so the change is visible to code that holds a reference
to the same cons cells (e.g. the ordered action list in CMD-PLAN)."
  (dolist (action actions)
    (when (and (eq (action-type action) :package)
               (not (getf action :via)))
      (let ((via (resolve-package-via action)))
        (nconc action (list :via via))))))

(defun dedup-actions (actions)
  "Deduplicate ACTIONS by identity. :priority :user (highest) beats
:priority :provider. :force t wins any tie regardless of priority. Two
actions of the same priority with the same identity but different content
signal ACTION-CONFLICT. For types registered with :dedup-behavior :additive
(e.g. :config-lines), same-identity duplicates at the same priority only
warn and both survive -- they're additive by identity construction, so
true duplicates there mean literally identical content. Priority still
outranks :additive: a user-level definition beats a provider-level one
even for additive types."
  (let ((by-identity (make-hash-table :test 'equal))
        (result '()))
    (dolist (action actions)
      (let* ((id (action-identity action))
             (existing (gethash id by-identity)))
        (cond
          ((null existing)
           (setf (gethash id by-identity) action)
           (push action result))
          ((getf action :force)
           (setf result (substitute action existing result))
           (setf (gethash id by-identity) action))
          ((getf existing :force)
           nil) ; existing already forced; keep it, drop new
          ((same-action-content-p action existing)
           nil) ; identical, drop the duplicate silently
          (t
           (let ((pa (or (getf action :priority) :provider))
                 (pe (or (getf existing :priority) :provider)))
             (cond
               ((and (eq pa :user) (eq pe :provider))
                (setf result (substitute action existing result))
                (setf (gethash id by-identity) action))
               ((and (eq pa :provider) (eq pe :user))
                nil) ; existing user-level def wins, drop provider action
               ((eq (gethash (action-type action) *action-type-dedup-behavior*) :additive)
                (linacs.log:warn* "Duplicate ~a identity for ~a; keeping both, continuing."
                                  (action-type action) (action-target action))
                (push action result))
               (t
                (restart-case
                    (error 'action-conflict :identity id
                           :def-a (action-source-label existing)
                           :def-b (action-source-label action))
                  (use-first () :report "Keep definition A (the existing action)"
                             nil) ; existing is already in result/by-identity; nothing to do
                   (use-second () :report "Keep definition B (the new action)"
                               (setf result (substitute action existing result))
                               (setf (gethash id by-identity) action))))))))))
    (nreverse result)))

(defun order-actions (actions)
  "Topologically order ACTIONS using explicit :depends-on identity edges,
refining declaration order. Signals DEPENDENCY-CYCLE on cycles and simply
ignores :depends-on edges that reference an identity not present in ACTIONS
(a missing dependency is not itself an error at this layer)."
  (let* ((id->action (make-hash-table :test 'equal))
         (visited (make-hash-table :test 'equal))
         (visiting (make-hash-table :test 'equal))
         (result '()))
    (dolist (a actions) (setf (gethash (action-identity a) id->action) a))
    (labels ((visit (action path)
               (let ((id (action-identity action)))
                 (cond
                   ((gethash id visited) nil)
                   ((gethash id visiting)
                    (error 'dependency-cycle :cycle (reverse (cons id path))))
                   (t
                    (setf (gethash id visiting) t)
                    (dolist (dep-id (getf action :depends-on))
                      (let ((dep (gethash dep-id id->action)))
                        (when dep (visit dep (cons id path)))))
                    (remhash id visiting)
                    (setf (gethash id visited) t)
                    (push action result))))))
      (dolist (a actions) (visit a nil)))
    (nreverse result)))

(defun execute-action (action &key (mode :apply))
  "Dispatch ACTION to its registered executor under MODE (:apply or :check).
Records the outcome in *ACTION-RESULTS* for --continue support and verbose
progress reporting.  Calls *PROGRESS-REPORTER* (if bound) before and after.

The RETRY / SKIP / ABORT-PROCESSING restarts are live for the duration of
the executor call, with real bodies: RETRY re-runs the executor (recursively,
re-establishing the restarts), SKIP records the action as skipped and moves
on, and ABORT-PROCESSING stops the whole run via the LINACS-ABORT catch."
  (let* ((id (action-identity action))
         (executor (find-executor (action-type action))))
    (setf *captured-subprocess-lines* nil)
    (when *progress-reporter*
      (funcall *progress-reporter* action :before))
    (labels ((run ()
               (with-linacs-restarts
                   (:on-retry #'run
                    :on-skip (lambda ()
                               (setf (gethash id *action-results*) (list :status :skipped))
                               (values nil :skipped))
                    :on-abort (lambda () (throw 'linacs-abort nil)))
                 (let ((reentered nil))
                   (flet ((record-and-reraise (err)
                            ;; Record the failure and re-signal, but only for
                            ;; the FIRST signal. The guard keeps the re-signaled
                            ;; condition from being re-caught by this same
                            ;; handler-bind, which would loop forever.
                            ;;
                            ;; HANDLER-BIND (not HANDLER-CASE) is deliberate:
                            ;; it never unwinds the protected form, so any
                            ;; restarts the executor established (e.g. the
                            ;; :stow FORCE restart) are still live when the
                            ;; condition reaches the interactive handler at
                            ;; signal time. HANDLER-CASE would have destroyed
                            ;; them, making those restarts invisible to the
                            ;; restart menu.
                            (unless reentered
                              (setf reentered t)
                              (setf (gethash id *action-results*)
                                    (list :status :failed :error err))
                              (when *progress-reporter*
                                (funcall *progress-reporter* action :failed err))
                              (error err))))
                     (handler-bind
                         ((linacs-error #'record-and-reraise)
                          (error (lambda (e)
                                   (record-and-reraise
                                    (make-condition 'execution-failure
                                                    :action-type (action-type action)
                                                    :target (action-target action)
                                                    :underlying e)))))
                       (let ((result (funcall executor action :mode mode)))
                         (let ((status (getf result :status)))
                           (when (and mode (eq mode :apply))
                             (unless status
                               (setf status :applied))
                             (setf (gethash id *action-results*) (list :status status)))
                           (when *progress-reporter*
                             (funcall *progress-reporter* action :after result))
                           (values result status)))))))))
      (run))))
