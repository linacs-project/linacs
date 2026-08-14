;;;; src/planning/plan.lisp
;;;;
;;;; ACTION-PLAN: the single resolved object handed from RESOLVE-PLAN out
;;;; through RUN-PIPELINE to every command (plan, apply, apply --dry-run,
;;;; diff, explain, check), so they all consume the same result
;;;; (REFACTOR.org Action 5). The plan carries the ordered action list, the
;;;; provenance table, and the execution results table (populated as
;;;; EXECUTE-PLAN runs), plus a conflict log.

(in-package :linacs.core)

(defclass action-plan ()
  ((actions    :initarg :actions    :initform nil
               :documentation "The resolved, deduplicated, ordered action
list (Execution Model steps 2-4)."
               :accessor plan-actions)
   (provenance :initarg :provenance :initform nil
               :documentation "The provenance table (identity -> 
ACTION-PROVENANCE) for the plan's actions."
               :accessor plan-provenance)
   (results    :initarg :results    :initform nil
               :documentation "The execution results table (identity ->
ACTION-RESULT), populated as EXECUTE-PLAN runs. In :plan-only mode it is
empty."
               :accessor plan-results)
   (conflicts  :initarg :conflicts  :initform nil
               :documentation "A log of deduplication conflicts resolved
during resolution (identity -> resolution note), when one is kept."
               :accessor plan-conflicts)))

(defun make-action-plan (&key actions provenance results conflicts)
  "Construct an ACTION-PLAN. All tables default to NIL until supplied."
  (make-instance 'action-plan
                 :actions actions :provenance provenance
                 :results results :conflicts conflicts))

(defun add-action (action plan)
  "Add ACTION to PLAN's action list (prepended, matching the pipeline's
push-then-NREVERSE convention) and return ACTION."
  (push action (plan-actions plan))
  action)

(defun action-by-identity (plan id)
  "Find the action in PLAN's action list whose identity equals ID (EQUAL),
or NIL."
  (find id (plan-actions plan) :key #'action-identity :test #'equal))

(defun deduplicate-plan (plan)
  "Return a NEW plan with the same tables and the action list run through
DEDUP-ACTIONS. The original plan is untouched (pure operation)."
  (make-action-plan :actions (dedup-actions (plan-actions plan))
                    :provenance (plan-provenance plan)
                    :results (plan-results plan)
                    :conflicts (plan-conflicts plan)))

(defun order-plan (plan)
  "Return a NEW plan with the same tables and the action list run through
ORDER-ACTIONS (topological sort over :depends-on edges)."
  (make-action-plan :actions (order-actions (plan-actions plan))
                    :provenance (plan-provenance plan)
                    :results (plan-results plan)
                    :conflicts (plan-conflicts plan)))

(defun plan-result (plan id)
  "The ACTION-RESULT recorded for the action with identity ID in PLAN's
results table, or NIL if the plan has not executed that action."
  (and (plan-results plan) (gethash id (plan-results plan))))

(defun plan-status (plan id)
  "The :status keyword of the ACTION-RESULT for ID in PLAN's results table
(see RESULT-STATUS), or NIL if that action has not run."
  (result-status (plan-result plan id)))