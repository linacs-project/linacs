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

(defun action-needs-privilege-p (action)
  "T if ACTION is a :package install that will typically need root. Every
:package via is privileged EXCEPT a Flatpak install explicitly scoped
:user, which deliberately never escalates (see package-action.lisp). This
is used only for the informational notice below, not to gate anything."
  (and (eq (action-type action) :package)
       (not (and (eq (getf action :via) :flatpak) (eq (getf action :scope :system) :user)))))

(defun preflight-notice (ordered-actions)
  "Log a one-line, purely informational notice if the plan contains
actions that will likely prompt for a sudo password when :apply actually
runs. Never aborts and never requires the whole linacs process to already
be root -- sudo's own credential cache (about 15 minutes by default) means
a plan with several such actions normally only prompts once."
  (let ((count (count-if #'action-needs-privilege-p ordered-actions)))
    (when (and (> count 0) (not (privileged-p)))
      (linacs.log:info "~d action(s) in this plan will use sudo for just that step; you may be prompted for your password."
                       count))))
