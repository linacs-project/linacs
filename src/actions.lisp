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

(defvar *action-conflicts* nil
  "List of conflict records (identity -> (:type ... :kept ... :dropped ...))
accumulated by DEDUP-ACTIONS, in resolution order. Callers reset it before a
dedup pass (RESOLVE-PLAN does) and read it afterward to populate the plan's
:conflicts table for reporting -- e.g. `linacs plan` and `linacs check`
showing 'Conflicts: N'. Pure reporting; resolution semantics are unaffected.")

(defun register-action-type (type executor-fn &key description identity dedup-behavior)
  (setf (gethash type *action-types*) executor-fn)
  (when description (setf (gethash type *action-type-descriptions*) description))
  (when identity (setf (gethash type *action-identity-functions*) identity))
  (when dedup-behavior (setf (gethash type *action-type-dedup-behavior*) dedup-behavior)))

(defun action-type-description (type)
  (or (gethash type *action-type-descriptions*) ""))

(defgeneric action-description (action)
  (:documentation "The one-line description registered for ACTION's type
(via REGISTER-ACTION-TYPE :description), or \"\" if none. Works on plists
and ACTION instances."))
(defmethod action-description ((action list))
  (action-type-description (action-type action)))

(defgeneric action-dedup-behavior (action)
  (:documentation "The dedup behavior of ACTION's type: :conflict (default)
or :additive. Works on plists and ACTION instances; delegates to
*ACTION-TYPE-DEDUP-BEHAVIOR*, registered via REGISTER-ACTION-TYPE
:dedup-behavior."))
(defmethod action-dedup-behavior ((action list))
  (or (gethash (action-type action) *action-type-dedup-behavior*) :conflict))

(defun find-executor (type)
  (or (gethash type *action-types*)
      (error 'execution-failure :action-type type :target nil
             :underlying (format nil "No executor registered for action type ~a" type))))

(defgeneric action-type (action)
  (:documentation "The action type keyword for ACTION (a plist or an
ACTION instance), e.g. :COPY-FILE."))
(defmethod action-type ((action list)) (getf action :action))

(defgeneric action-target (action)
  (:documentation "The primary target of ACTION (a plist or an ACTION
instance). For plists, prefers :TARGET over :TO (the DSL's FILE form
historically emitted both). ACTION instances store a single canonical
TARGET slot; subclasses map :TO-only keys onto it at construction."))
(defmethod action-target ((action list)) (or (getf action :target) (getf action :to)))

(defgeneric action-priority (action)
  (:documentation "The priority (:user or :provider) of ACTION, a plist or
an ACTION instance. Defaults to :provider when unset."))
(defmethod action-priority ((action list)) (or (getf action :priority) :provider))

(defgeneric action-force (action)
  (:documentation "NIL, or T if ACTION (a plist or an ACTION instance) wins
any identity conflict outright."))
(defmethod action-force ((action list)) (getf action :force))

(defgeneric action-disabled (action)
  (:documentation "NIL, or T if ACTION (a plist or an ACTION instance) is
marked for explicit removal (subject to the :prune-explicitly-disabled trait)."))
(defmethod action-disabled ((action list)) (getf action :disabled))

(defgeneric action-depends-on (action)
  (:documentation "ACTION's explicit :depends-on identity edges (a plist or
an ACTION instance)."))
(defmethod action-depends-on ((action list)) (getf action :depends-on))

(defgeneric action-source (action)
  (:documentation "Human-readable origin label of ACTION, a plist or an
ACTION instance."))
(defmethod action-source ((action list)) (getf action :source))

(defgeneric action-location (action)
  (:documentation "PLACEBOOK location plist (:file ...) of ACTION, a plist
or an ACTION instance."))
(defmethod action-location ((action list)) (getf action :location))

(defgeneric action-project-root (action)
  (:documentation "Stamped --root value on ACTION, a plist or an ACTION
instance."))
(defmethod action-project-root ((action list)) (getf action :project-root))

(defgeneric action-identity (action)
  (:documentation "Compute the canonical identity for ACTION (a plist).
Delegates to the type's registered identity function in
*ACTION-IDENTITY-FUNCTIONS* (set via REGISTER-ACTION-TYPE :identity), or
falls back to (type . target). Plugin authors register identity functions
for new action types so ACTION-IDENTITY never needs a hardcoded cond chain:

    (register-action-type :my-type #'my-executor
      :identity (lambda (a) (list :my-type (getf a :qualifier) (action-target a))))"))
(defmethod action-identity ((action list))
  (let* ((type (action-type action))
         (fn (gethash type *action-identity-functions*)))
    (if fn
        (funcall fn action)
        (cons type (action-target action)))))

(defun register-provenance (action-id provenance)
  "Record PROVENANCE for ACTION-ID in the active context's provenance
table (else *PROVENANCE*). PROVENANCE may be an ACTION-PROVENANCE instance
or the historic (:feature ... :provider ... :source ...) plist; plists
are normalized to instances on the way in (REFACTOR.org Action 5)."
  (setf (gethash action-id (context-provenance))
        (if (typep provenance 'action-provenance)
            provenance
            (make-action-provenance-from-plist provenance))))

(defun action-provenance (action-id)
  "Retrieve the ACTION-PROVENANCE for ACTION-ID from the active context's
provenance table (else *PROVENANCE*), or NIL."
  (gethash action-id (context-provenance)))

(defun action-result-status (action-id)
  "Retrieve the result status (:applied :already-met :failed :skipped) for
ACTION-ID from the active context's results table (else *ACTION-RESULTS*),
or NIL if not yet executed. Results are stored as ACTION-RESULT instances;
historic plists read via RESULT-STATUS for compatibility."
  (let ((result (gethash action-id (context-results))))
    (and result (result-status result))))

(defgeneric action-source-label (action)
  (:documentation "Human-readable label of where ACTION came from, for
conflict reports."))
(defmethod action-source-label ((action list))
  (or (getf action :source) "unspecified"))

(defgeneric action->plist (action)
  (:documentation "The plist form of ACTION. A plist is its own plist.
The conversion seam between the plist convention and the external plist
convention (identity for plists)."))
(defmethod action->plist ((action list)) action)

(defgeneric same-action-content-p (a b)
  (:documentation "Two actions are content-equal if their plists are EQUAL
once :source, :priority, and identity-irrelevant bookkeeping keys are
stripped."))
(defmethod same-action-content-p ((a list) (b list))
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

(defun repository-spec-plist (spec)
  "Normalize the value CATALOG-LOOKUP returns for a :repositories entry
into a spec plist (:method <kw> :id <str>), or NIL.
Entries registered as (:fedora (:method :dnf-copr :id \"...\")) come back
wrapped in a one-element list; the dotted (:fedora . (:method ...)) form
arrives as the bare plist. String values (the catalog's no-entry fallback,
and ordinary distro string mappings) are not repository specs and yield NIL."
  (cond
    ((and (consp spec) (consp (car spec))) (car spec))
    ((and (consp spec) (keywordp (car spec))) spec)
    (t nil)))

(defun resolve-repository-prerequisites (actions)
  "Walk ACTIONS and, for every :package action whose :via is :system, consult
the :repositories catalog for the current distro: when the canonical target
maps to a repository spec plist (:method <kw> :id <str>), inject a
:repository action ahead of the package and make the package depend on it,
so the repository is configured before the install.

Mirrors RESOLVE-PACKAGE-VIAS (which injects :via for packages missing it):
called from RESOLVE-PLAN right after it, so :via is already decided and only
:system packages -- the ones that draw from distro repositories -- get a
prerequisite. Flatpak/pip/npm handle their own remotes and never appear here.

The catalog's string fallback (catalog-lookup returns the keyword's name
when no entry exists) is treated as 'no repository needed' -- those packages
behave exactly as before. A spec is only honored when it is a plist carrying
both :method and :id. A catalog entry written as (:fedora (:method ...)) is
returned by catalog-lookup wrapped in a one-element list, while the dotted
(:fedora . (:method ...)) form arrives unwrapped -- the normalizer in
REPOSITORY-SPEC-PLIST accepts both. String package targets (e.g.
(package \"vim\")) are skipped, since the :repositories catalog is keyed by
canonical keyword.

Any :depends-on the package already carries is preserved: the repository
identity is appended, never clobbering provider/user edges."
  (let ((injected '()))
    (dolist (action actions)
      (when (and (eq (action-type action) :package)
                 (eq (getf action :via) :system))
        (let* ((target (action-target action))
               (spec (repository-spec-plist
                      (catalog-lookup :repositories target (fact :os)))))
          (when (and (consp spec)
                     (getf spec :method)
                     (getf spec :id))
            (let* ((id (getf spec :id))
                   (method (getf spec :method))
                   (repo-id (list* :repository method id))
                   (repo-action (list :action :repository
                                      :target id
                                      :method method
                                      :priority :provider
                                      :source (format nil "repository prerequisite for ~a" target))))
              (push repo-action injected)
              (let ((existing (getf action :depends-on)))
                (if existing
                    (setf (getf action :depends-on) (append existing (list repo-id)))
                    (nconc action (list :depends-on (list repo-id))))))))))
    (append injected actions)))

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
          ((action-force action)
           (setf result (substitute action existing result))
           (setf (gethash id by-identity) action))
          ((action-force existing)
           nil) ; existing already forced; keep it, drop new
((same-action-content-p action existing)
            nil) ; identical, drop the duplicate silently
           (t
            (let ((pa (action-priority action))
                  (pe (action-priority existing)))
              (cond
                ((and (eq pa :user) (eq pe :provider))
                 (push (list id (list :type :override
                                      :kept :user
                                      :dropped (action-source-label existing)))
                       *action-conflicts*)
                 (setf result (substitute action existing result))
                 (setf (gethash id by-identity) action))
                ((and (eq pa :provider) (eq pe :user))
                 (push (list id (list :type :override
                                      :kept :user
                                      :dropped (action-source-label action)))
                       *action-conflicts*)
                 nil) ; existing user-level def wins, drop provider action
                ((eq (action-dedup-behavior action) :additive)
                 (linacs.log:warn* "Duplicate ~a identity for ~a; keeping both, continuing."
                                   (action-type action) (action-target action))
                 (push action result))
                (t
                 (restart-case
                     (error 'action-conflict :identity id
                            :def-a (action-source-label existing)
                            :def-b (action-source-label action))
                   (use-first () :report "Keep definition A (the existing action)"
                              (push (list id (list :type :conflict
                                                   :kept (action-priority existing)
                                                   :dropped (action-source-label action)))
                                    *action-conflicts*)
                              nil) ; existing is already in result/by-identity; nothing to do
                   (use-second () :report "Keep definition B (the new action)"
                               (push (list id (list :type :conflict
                                                    :kept (action-priority action)
                                                    :dropped (action-source-label existing)))
                                     *action-conflicts*)
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
                     (dolist (dep-id (action-depends-on action))
                      (let ((dep (gethash dep-id id->action)))
                        (when dep (visit dep (cons id path)))))
                    (remhash id visiting)
                    (setf (gethash id visited) t)
                    (push action result))))))
      (dolist (a actions) (visit a nil)))
    (nreverse result)))

(defgeneric execute-action (action &key mode context)
  (:documentation "Dispatch ACTION to its registered executor under MODE
(:apply or :check). Records the outcome in *ACTION-RESULTS* for --continue
support and verbose progress reporting.  Calls *PROGRESS-REPORTER* (if
bound) before and after.

ACCEPT APLISTS and ACTION objects alike: an ACTION instance is converted to
its plist first (ACTION->PLIST), so executors keep receiving plists no
matter which representation the caller chose.

CONTEXT is an optional EXECUTION-CONTEXT (see domain/execution/context.lisp)
owning the run's facts, project/asset roots, results and provenance tables,
and progress/capture controls. When supplied, the execution-scope dynamic
globals are bound FROM it for the duration of the executor call via
WITH-EXECUTION-CONTEXT; when NIL the historic dynamic globals are used
unchanged. Callers that build a context (EXECUTE-PLAN under a context)
pass it through here so executors read its state.

The RETRY / SKIP / ABORT-PROCESSING restarts are live for the duration of
the executor call, with real bodies: RETRY re-runs the executor
(recursively, re-establishing the restarts), SKIP records the action as
skipped and moves on, and ABORT-PROCESSING stops the whole run via the
LINACS-ABORT catch."))

(defmethod execute-action ((action list) &key (mode :apply) context)
  "EXECUTE-ACTION for a plist action: the full dispatch/recording body.
The execution-scope state is bound from CONTEXT (an EXECUTION-CONTEXT) for
the duration of the executor call via WITH-EXECUTION-CONTEXT; when CONTEXT
is NIL the historic dynamic globals are used unchanged."
  (with-execution-context context
    (let* ((id (action-identity action))
         (executor (find-executor (action-type action)))
         (*current-action* action))
    (setf *captured-subprocess-lines* nil)
    (report-event (make-action-started :action action))
    (labels ((run ()
               (with-linacs-restarts
                   (:on-retry #'run
                    :on-skip (lambda ()
                               (setf (gethash id *action-results*)
                                     (make-action-result :action action
                                                         :status :skipped
                                                         :mode mode))
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
                                    (make-action-result :action action
                                                        :status :failed
                                                        :error err
                                                        :mode mode))
                              (report-event
                               (make-action-failed :action action :error err))
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
                             (setf (gethash id *action-results*)
                                   (make-action-result :action action
                                                       :status status
                                                       :mode mode)))
                           (report-event
                             (make-action-completed :action action :result result))
                           (values result status)))))))))
      (run)))))

