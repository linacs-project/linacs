;;;; src/action-types/timer.lisp
;;;;
;;;; The :timer executor. Creates and enables a systemd timer unit only if
;;;; its content or enabled state needs to change. Timers live under
;;;; ~/.config/systemd/user and are managed through the :systemd-user
;;;; SERVICE-BACKEND (REFACTOR.org Action 16), which never escalates -- so a
;;;; :timer action is correctly accounted as non-privileged by
;;;; ACTION-NEEDS-PRIVILEGE-P.
;;;;
;;;; Usage:
;;;;     (:action :timer :target "backup-daily" :on-calendar "daily")

(in-package :linacs.core)

(defun timer-unit-path (name) (format nil "~a/.config/systemd/user/~a.timer" (uiop:getenv "HOME") name))

(defun timer-unit-content (action)
  (format nil "[Unit]~%Description=LINACS-managed timer ~a~%~%[Timer]~%OnCalendar=~a~%Persistent=true~%~%[Install]~%WantedBy=timers.target~%"
          (action-target action) (getf action :on-calendar)))

(defun execute-timer (action &key mode)
  (let* ((name (action-target action))
         (backend (find-service-backend :systemd-user))
         (unit (format nil "~a.timer" name))
         (path (timer-unit-path name))
         (intended (timer-unit-content action))
         (current (read-file-string path))
         (needs-write (not (equal intended current)))
         (enabled (and backend (service-enabled-p backend unit))))
    (case mode
      (:check (report (if (or needs-write (not enabled)) :would-change :unchanged) :target name))
      (:apply
       (when needs-write (write-file-string path intended))
       ;; The enable is best-effort: the unit file write is the source of
       ;; truth, and a systemctl --user hiccup should not fail the run.
       (unless enabled
         (ignore-errors (service-enable backend unit)))
       (report (if (or needs-write (not enabled)) :changed :unchanged) :target name))
      (:remove
       (ignore-errors (service-disable backend unit))
       (when (probe-file path) (delete-file path))
       (report :removed :target name)))))

(register-action-type :timer #'execute-timer
  :description "Create and enable a systemd timer unit")
