;;;; src/action-types/cron.lisp
;;;;
;;;; The :cron executor. Manages one entry under /etc/cron.d/, in
;;;; system-crontab format (which includes a user field, unlike a personal
;;;; crontab) -- for minimal installs that still rely on cron rather than
;;;; systemd timers.
;;;;
;;;; Usage:
;;;;     (:action :cron :target "nightly-backup" :schedule "0 2 * * *" :command "/usr/local/bin/backup.sh")

(in-package :linacs.core)

(defun cron-file-path (name) (format nil "/etc/cron.d/~a" name))

(defun cron-line (action)
  (format nil "~a ~a ~a"
          (getf action :schedule) (or (getf action :user) "root") (getf action :command)))

(defun execute-cron (action &key mode)
  (let* ((name (action-target action))
         (path (cron-file-path name))
         (intended (cron-line action))
         (current (string-trim '(#\Newline) (or (read-file-string path) "")))
         (changed (not (equal current intended))))
    (case mode
      (:check (report (if changed :would-change :unchanged) :target name))
      (:apply
       (when changed (write-privileged-file path (format nil "~a~%" intended)))
       (report (if changed :changed :unchanged) :target name))
      (:remove
       (when (probe-file path) (run-privileged (list "rm" "-f" path)))
       (report :removed :target name)))))

(register-action-type :cron #'execute-cron
  :description "Manage one entry under /etc/cron.d/")
