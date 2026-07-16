;;;; src/action-types/command.lisp
;;;;
;;;; The :command executor, the final escape hatch. Runs a raw shell
;;;; command, but only when its own idempotency check (:creates / :unless /
;;;; :only-if) says it's needed; with none given, it honestly reports the
;;;; command as always needing to run rather than guessing. Give :sudo t
;;;; when the command itself needs root -- per the project-wide escalation
;;;; policy (see action-types/helpers.lisp), this is the one action type
;;;; where LINACS can't detect that for you: an arbitrary shell string isn't
;;;; something LINACS can try plain-first-then-escalate the way a known
;;;; filesystem/service operation can, so the author has to say so up
;;;; front, and LINACS runs it straight through RUN-PRIVILEGED (which itself
;;;; still skips sudo if the whole process already happens to be root).
;;;;
;;;; Usage:
;;;;     (:action :command :target "clone dotfiles" :run "git clone ... ~/.dotfiles" :creates "~/.dotfiles")
;;;;     (:action :command :target "set timezone" :run "timedatectl set-timezone America/New_York" :sudo t)

(in-package :linacs.core)

(defun command-needed-p (action)
  (cond
    ((getf action :creates) (not (probe-file (expand-home (getf action :creates)))))
    ((getf action :unless) (not (shell-ok-p (getf action :unless))))
    ((getf action :only-if) (shell-ok-p (getf action :only-if)))
    (t t)))

(defun run-command-string (command sudo-p &key ignore-error-status)
  "Run COMMAND through /bin/sh, escalating via RUN-PRIVILEGED when SUDO-P.
IGNORE-ERROR-STATUS suppresses a non-zero exit as a hard error (used for
:remove-run, where \"already gone\" shouldn't fail the run) in both the
plain and privileged paths, so :sudo doesn't change that contract."
  (if sudo-p
      (if ignore-error-status
          (ignore-errors (run-privileged (list "sh" "-c" command)))
          (run-privileged (list "sh" "-c" command)))
      (uiop:run-program (list "sh" "-c" command)
                        :output t :error-output t
                        :ignore-error-status ignore-error-status)))

(defun execute-command (action &key mode)
  (let* ((name (action-target action))
         (needed (command-needed-p action))
         (sudo-p (getf action :sudo)))
    (case mode
      (:check (report (if needed :would-change :unchanged) :target name))
      (:apply
       (when needed (run-command-string (getf action :run) sudo-p))
       (report (if needed :changed :unchanged) :target name))
      (:remove
       (when (getf action :remove-run)
         (run-command-string (getf action :remove-run) sudo-p :ignore-error-status t))
       (report :removed :target name)))))

(register-action-type :command #'execute-command
                      :description "Run a raw shell command, gated by a :creates/:unless/:only-if idempotency check. Give :sudo t if the command itself needs root.")
