;;;; src/domain/execution/result.lisp
;;;;
;;;; ACTION-RESULT: the object stored in the execution results (and
;;;; provenance context) table, one per action identity, recording what
;;;; happened when the action ran. Typed replacement for the historic
;;;; (:status ... :error ...) plists (REFACTOR.org Action 5); the generic
;;;; RESULT-* readers accept either an ACTION-RESULT or a historic plist,
;;;; so mixed call sites keep working during migration.

(in-package :linacs.core)

(defclass action-result ()
  ((action   :initarg :action   :initform nil
             :documentation "The action (plist) this result describes.")
   (status   :initarg :status   :initform nil
             :documentation "The status keyword from the executor result:
:applied, :already-met, :changed, :unchanged, :removed, :failed,
:skipped, or a :check-mode status.")
   (error    :initarg :error    :initform nil
             :documentation "The condition object when STATUS is :failed.")
   (duration :initarg :duration :initform nil
             :documentation "Elapsed seconds of the executor call, if timed.")
   (mode     :initarg :mode     :initform :apply
             :documentation "The mode (:apply / :check / :remove) under
which this result was recorded.")))

(defun make-action-result (&key action status error duration (mode :apply))
  "Construct an ACTION-RESULT. MODE defaults to :apply, DURATION to NIL.
The result is inert data: status canonicalization (:applied vs
:already-met, check-mode statuses) stays EXECUTOR-STATUS's job, applied by
the state executors at execution time."
  (make-instance 'action-result
                 :action action :status status :error error
                 :mode mode :duration duration))

(defgeneric result-status (result)
  (:documentation "The :status keyword of RESULT. RESULT may be an
ACTION-RESULT instance *or* a historic (:status ...) plist; anything else
(including NIL) yields NIL."))
(defmethod result-status ((result action-result)) (slot-value result 'status))
(defmethod result-status ((result list)) (getf result :status))
(defmethod result-status (result) (declare (ignore result)) nil)

(defgeneric result-error (result)
  (:documentation "The error condition recorded on RESULT (:failed results),
or NIL. RESULT may be an ACTION-RESULT or a plist."))
(defmethod result-error ((result action-result)) (slot-value result 'error))
(defmethod result-error ((result list)) (getf result :error))
(defmethod result-error (result) (declare (ignore result)) nil)

(defgeneric result-action (result)
  (:documentation "The action plist RESULT describes. RESULT may be an
ACTION-RESULT or a plist."))
(defmethod result-action ((result action-result)) (slot-value result 'action))
(defmethod result-action ((result list)) (getf result :action))
(defmethod result-action (result) (declare (ignore result)) nil)

(defgeneric result-duration (result)
  (:documentation "The elapsed-seconds of RESULT, or NIL. RESULT may be an
ACTION-RESULT or a plist."))
(defmethod result-duration ((result action-result)) (slot-value result 'duration))
(defmethod result-duration ((result list)) (getf result :duration))
(defmethod result-duration (result) (declare (ignore result)) nil)

(defgeneric result-mode (result)
  (:documentation "The mode under which RESULT was recorded. RESULT may be
an ACTION-RESULT or a plist."))
(defmethod result-mode ((result action-result)) (slot-value result 'mode))
(defmethod result-mode ((result list)) (getf result :mode))
(defmethod result-mode (result) (declare (ignore result)) nil)

(defun result->plist (result)
  "Serialize RESULT to the historic (:status ... :error ...) plist shape.
The inverse is PLIST->RESULT."
  (list :action (result-action result)
        :status (result-status result)
        :error (result-error result)
        :duration (result-duration result)
        :mode (result-mode result)))

(defun plist->result (plist)
  "Reconstruct an ACTION-RESULT from a historic result plist. The inverse
of RESULT->PLIST."
  (make-action-result :action (getf plist :action)
                      :status (getf plist :status)
                      :error (getf plist :error)
                      :duration (getf plist :duration)
                      :mode (or (getf plist :mode) :apply)))