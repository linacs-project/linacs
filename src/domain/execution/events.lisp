;;;; src/domain/execution/events.lisp
;;;;
;;;; Structured execution events (REFACTOR.org Thought 8). The execution
;;;; pipeline -- resolve, feature walk, and per-action execution -- emits a
;;;; stream of typed events via REPORT-EVENT instead of (or, during this
;;;; migration, in addition to) the historic (action phase &optional data)
;;;; calls into *PROGRESS-REPORTER*.
;;;;
;;;; Event taxonomy (one CLOS class per event kind):
;;;;   plan-started / plan-completed -- whole-run bookends, carrying the
;;;;     ACTION-PLAN being resolved/executed.
;;;;   feature-resolved            -- one per resolved feature, carrying the
;;;;     selected feature and provider.
;;;;   action-started / action-completed / action-skipped / action-failed
;;;;                              -- the per-action lifecycle.
;;;;   action-output               -- one chunk of captured subprocess output
;;;;     (the (:stdout . string) / (:stderr . string) entries that the
;;;;     capture path in helpers.lisp accumulates into
;;;;     *CAPTURED-SUBPROCESS-LINES*).
;;;;
;;;; Every event carries a :STAGE keyword (its own kind) so consumers that
;;;; prefer a single dispatch key can read EVENT-STAGE without class-testing.
;;;;
;;;; REPORT-EVENT is the emission seam: a generic with one method per event
;;;; kind. The concrete methods for the action lifecycle translate the event
;;;; back into the historic (action phase &optional data) contract and
;;;; forward it to *PROGRESS-REPORTER* when bound, so the CLI's
;;;; APPLY-PROGRESS-REPORTER keeps rendering the exact same stream it always
;;;; did -- byte-identical output, zero churn in the reporter. Events with no
;;;; historic phase (plan-started, feature-resolved, plan-completed,
;;;; action-output) are dropped by their no-op methods; pluggable reporters
;;;; (REFACTOR.org Thought 19) arrive as additional, more-specific methods.

(in-package :linacs.core)

(defclass execution-event ()
  ((stage :initarg :stage :reader event-stage
          :documentation "Names the event kind (a keyword like
:ACTION-STARTED); concrete events add the payload slots that describe what
happened."))
  (:documentation "The base class of every structured execution event."))

(defclass plan-started (execution-event)
  ((plan :initarg :plan :reader event-plan))
  (:default-initargs :stage :plan-started))

(defclass feature-resolved (execution-event)
  ((feature  :initarg :feature  :reader event-feature)
   (provider :initarg :provider :reader event-provider))
  (:default-initargs :stage :feature-resolved))

(defclass plan-completed (execution-event)
  ((plan :initarg :plan :reader event-plan))
  (:default-initargs :stage :plan-completed))

(defclass action-started (execution-event)
  ((action :initarg :action :reader event-action))
  (:default-initargs :stage :action-started))

(defclass action-output (execution-event)
  ((action :initarg :action :reader event-action)
   (stream :initarg :stream :reader event-stream)
   (line   :initarg :line   :reader event-line))
  (:default-initargs :stage :action-output))

(defclass action-completed (execution-event)
  ((action :initarg :action :reader event-action)
   (result :initarg :result :reader event-result))
  (:default-initargs :stage :action-completed))

(defclass action-skipped (execution-event)
  ((action :initarg :action :reader event-action))
  (:default-initargs :stage :action-skipped))

(defclass action-failed (execution-event)
  ((action :initarg :action :reader event-action)
   (error  :initarg :error  :reader event-error))
  (:default-initargs :stage :action-failed))

(defun make-plan-started (&key plan)
  "Construct a PLAN-STARTED event: the whole-run bookend emitted just
before execution begins, carrying the ACTION-PLAN being run."
  (make-instance 'plan-started :plan plan))

(defun make-feature-resolved (&key feature provider)
  "Construct a FEATURE-RESOLVED event: one per resolved feature, carrying
the feature keyword and the provider keyword actually selected."
  (make-instance 'feature-resolved :feature feature :provider provider))

(defun make-plan-completed (&key plan)
  "Construct a PLAN-COMPLETED event: the whole-run bookend emitted just
after execution finishes, carrying the ACTION-PLAN that was run."
  (make-instance 'plan-completed :plan plan))

(defun make-action-started (&key action)
  "Construct an ACTION-STARTED event: emitted immediately before an action's
executor runs."
  (make-instance 'action-started :action action))

(defun make-action-output (&key action stream line)
  "Construct an ACTION-OUTPUT event: one chunk of captured subprocess output
(STREAM is :STDOUT or :STDERR, LINE the chunk string)."
  (make-instance 'action-output :action action :stream stream :line line))

(defun make-action-completed (&key action result)
  "Construct an ACTION-COMPLETED event: emitted immediately after an action's
executor returns, carrying the executor's result plist."
  (make-instance 'action-completed :action action :result result))

(defun make-action-skipped (&key action)
  "Construct an ACTION-SKIPPED event: emitted when an action is skipped
without running its executor (disabled under the pruning trait, or a
dependent of a failed action under --continue)."
  (make-instance 'action-skipped :action action))

(defun make-action-failed (&key action error)
  "Construct an ACTION-FAILED event: emitted when an action's executor
signals a condition, carrying the condition."
  (make-instance 'action-failed :action action :error error))

(defgeneric report-event (event)
  (:documentation "Emit EVENT to the registered reporters.

The default methods translate the per-action lifecycle events back into
the historic (action phase &optional data) contract and forward them to
*PROGRESS-REPORTER* when bound, so the CLI's APPLY-PROGRESS-REPORTER
keeps rendering exactly what it always rendered. Events with no historic
phase (plan-started, feature-resolved, plan-completed, action-output) are
no-ops by default.

Pluggable reporters (REFACTOR.org Thought 19) define more-specific
methods on REPORT-EVENT -- e.g. (defmethod report-event ((e action-output))
...) -- to consume the structured stream directly."))

(defmethod report-event ((e plan-started))
  (declare (ignore e))
  nil)

(defmethod report-event ((e feature-resolved))
  (declare (ignore e))
  nil)

(defmethod report-event ((e plan-completed))
  (declare (ignore e))
  nil)

(defmethod report-event ((e action-output))
  (declare (ignore e))
  nil)

(defmethod report-event ((e action-started))
  (when *progress-reporter*
    (funcall *progress-reporter* (event-action e) :before)))

(defmethod report-event ((e action-completed))
  (when *progress-reporter*
    (funcall *progress-reporter* (event-action e) :after (event-result e))))

(defmethod report-event ((e action-skipped))
  (when *progress-reporter*
    (funcall *progress-reporter* (event-action e) :skipped)))

(defmethod report-event ((e action-failed))
  (when *progress-reporter*
    (funcall *progress-reporter* (event-action e) :failed (event-error e))))
