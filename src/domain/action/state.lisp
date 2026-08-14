;;;; src/domain/action/state.lisp
;;;;
;;;; State and status protocol (REFACTOR.org Action 3). On top of the plist
;;;; object model this provides:
;;;;
;;;;   * the five state generics -- CURRENT-STATE, DESIRED-STATE, DIFF-STATE,
;;;;     APPLY-STATE, REMOVE-STATE -- as the seam between an action's declared
;;;;     intent and the monolithic executors of today.  The default methods
;;;;     DELEGATE TO THE EXISTING REGISTRIES (the *ACTION-TYPES* executors, via
;;;;     EXECUTE-ACTION), so no registered action type changes behavior and
;;;;     plugins keep working unchanged.  Authors migrate an executor onto the
;;;;     state protocol by adding methods for its action type -- the default
;;;;     remains available as the "whole executor at once" fallback.
;;;;
;;;;   * the unified status vocabulary -- the canonical status keywords the
;;;;     executor `report` macro emits today (:would-change :unchanged :changed
;;;;     :removed :missing) plus the execution/pipeline statuses the
;;;;     *ACTION-RESULTS* table stores (:applied :already-met :failed
;;;;     :skipped) -- together with EXECUTOR-STATUS, which translates an
;;;;     executor's raw status into the canonical execution spelling.  Action 5
;;;;     (ActionResult) will store exactly these keywords, so the vocabulary is
;;;;     pinned here first.

(in-package :linacs.core)

(defparameter *action-statuses*
  '(:would-change :unchanged :changed :removed :missing
    :applied :already-met :failed :skipped)
  "The canonical action status vocabulary (REFACTOR.org Action 3),
unifying the two historical families:

  * change-detection family (check-mode executors, `plan`, `diff`,
    `--dry-run`): :would-change :unchanged :changed :removed :missing
  * execution/pipeline family (apply-mode results and the *ACTION-RESULTS*
    table): :applied :already-met :removed :failed :skipped

:removed belongs to both families (a remove-mode executor both reports and
performs a deletion).  These are the statuses ACTION-RESULT objects (Action
5) will store, and the spellings EXECUTOR-STATUS maps to.")

(defun executor-status (status &key (mode :apply))
  "Translate an executor-reported STATUS into its canonical spelling for the
given MODE.  In :check mode every executor status is already canonical
(:would-change / :unchanged / :changed / :removed / :missing) and passes
through unchanged.  In :apply/:remove mode the change-detection spellings
that prophesy a transition map to the execution spellings *ACTION-RESULTS*
stores: :would-change -> :applied, :unchanged -> :already-met.  :changed,
:removed, :missing, :failed, and :skipped pass through.  NIL (an executor
that performed its work without reporting a status) becomes :applied."
  (if (eq mode :apply)
      (case status
        (:would-change :applied)
        (:unchanged    :already-met)
        (:applied      :applied)
        (:changed      :applied)
        (:removed      :removed)
        (:missing      :missing)
        (:failed       :failed)
        (:skipped      :skipped)
        (otherwise     :applied))
      status))

(defgeneric current-state (action)
  (:documentation "Probe the current system state relevant to ACTION.
Returns the system's present state as a plist, or NIL when the executor
has not yet been split into probe/apply halves (today's executors conflate
them).  The default method returns NIL; authors migrate an executor onto
the state protocol by defining CURRENT-STATE and the other state generics
for its action type.  Works on plists and ACTION instances."))
(defmethod current-state ((action t))
  (declare (ignorable action))
  nil)

(defgeneric desired-state (action)
  (:documentation "The desired system state for ACTION, as a plist.  The
default method returns the action's plist itself -- today the declared
intent IS the desired state, and DIFF-STATE compares against it via the
executor.  Works on plists and ACTION instances."))
(defmethod desired-state ((action t))
  (if (action-p action) (action->plist action) action))

(defgeneric diff-state (action)
  (:documentation "Compare ACTION's desired state against the current system
state and report what WOULD change.  Default: delegate to the registered
executor in :check mode (EXECUTE-ACTION :mode :check), which is what `plan`,
`diff`, and `--dry-run` consume.  Executor statuses pass through
canonical (:would-change / :unchanged / :changed / :removed / :missing).
Works on plists and ACTION instances."))
(defmethod diff-state ((action t))
  (execute-action action :mode :check))

(defgeneric apply-state (action)
  (:documentation "Make the system match ACTION's desired state (idempotently).
Default: delegate to the registered executor in :apply mode (EXECUTE-ACTION
:mode :apply), with the returned status canonicalized to the execution
spelling via EXECUTOR-STATUS (e.g. :changed -> :applied, :unchanged ->
:already-met).  Works on plists and ACTION instances."))
(defmethod apply-state ((action t))
  (let* ((result (execute-action action :mode :apply))
         (out (copy-list result)))
    (when (getf out :status)
      (setf (getf out :status) (executor-status (getf out :status) :mode :apply)))
    out))

(defgeneric remove-state (action)
  (:documentation "Remove ACTION's artifact from the system (opt-in, for
:disabled actions under the :prune-explicitly-disabled trait).  Default:
delegate to the registered executor in :remove mode (EXECUTE-ACTION :mode
:remove), canonicalizing the status exactly as APPLY-STATE does.  Works on
plists and ACTION instances."))
(defmethod remove-state ((action t))
  (let* ((result (execute-action action :mode :remove))
         (out (copy-list result)))
    (when (getf out :status)
      (setf (getf out :status) (executor-status (getf out :status) :mode :apply)))
    out))
