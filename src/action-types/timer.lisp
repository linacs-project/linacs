;;;; src/action-types/timer.lisp
;;;;
;;;; The :timer executor. Creates and enables a systemd timer unit only if
;;;; its content or enabled state needs to change.
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
         (path (timer-unit-path name))
         (intended (timer-unit-content action))
         (current (read-file-string path))
         (needs-write (not (equal intended current)))
         (enabled (service-enabled-p (format nil "~a.timer" name))))
    (case mode
      (:check (report (if (or needs-write (not enabled)) :would-change :unchanged) :target name))
      (:apply
       (when needs-write (write-file-string path intended))
       (unless enabled
         (ignore-errors (uiop:run-program (list "systemctl" "--user" "enable" "--now"
                                                  (format nil "~a.timer" name)))))
       (report (if (or needs-write (not enabled)) :changed :unchanged) :target name))
      (:remove
       (ignore-errors (uiop:run-program (list "systemctl" "--user" "disable" "--now"
                                                (format nil "~a.timer" name))))
       (when (probe-file path) (delete-file path))
       (report :removed :target name)))))

(register-action-type :timer #'execute-timer
  :description "Create and enable a systemd timer unit")
