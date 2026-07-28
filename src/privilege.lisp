;;;; src/privilege.lisp
;;;;
;;;; Privilege detection, and an informational pre-apply notice (not a
;;;; gate) about how many actions in the plan will need root. linacs never
;;;; requires the whole process to run as root: every action that
;;;; genuinely needs privilege escalates on its own, per-command, via
;;;; sudo (see the escalate-on-demand helpers in
;;;; action-types/helpers.lisp) -- so there is nothing to abort here
;;;; before :apply runs, only something worth telling you about up front.
;;;;
;;;; Usage:
;;;;     (privileged-p)                 ; => T if the process itself is root
;;;;     (preflight-notice ordered-actions) ; logs a one-line notice, never errors

(in-package :linacs.core)

(defun current-uid ()
  (ignore-errors
   (parse-integer
    (string-trim '(#\Newline)
                 (uiop:run-program (list "id" "-u") :output '(:string :stripped t))))))

(defun privileged-p ()
  "T if the current process itself is already root. Most runs of linacs
should answer NIL here -- individual actions escalate on their own as
needed, rather than requiring the whole process to run as root."
  (eql (current-uid) 0))

(defun preflight-notice (ordered-actions)
  "Log a one-line, purely informational notice if the plan contains
actions that will need sudo. A separate PREFLIGHT-SUDO-PROMPT call
(which happens just after this, in RUN-PIPELINE) handles the actual
upfront password prompt so individual action executors never need to
interrupt output to ask for a password mid-execution."
  (let ((count (count-if #'action-needs-privilege-p ordered-actions)))
    (when (and (> count 0) (not (privileged-p)))
      (linacs.log:info "~d action(s) in this plan will use sudo for just that step; you may be prompted for your password."
                       count))))
