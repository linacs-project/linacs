;;;; src/action-types/hostname.lisp
;;;;
;;;; The :hostname executor. Sets the hostname at runtime AND writes
;;;; /etc/hostname, since either alone is a common half-fix (one doesn't
;;;; survive reboot, the other doesn't take effect until one).
;;;;
;;;; Usage:
;;;;     (:action :hostname :target "app-server-01")

(in-package :linacs.core)

(defun current-hostname ()
  (ignore-errors (string-trim '(#\Newline) (uiop:run-program '("hostname") :output '(:string :stripped t)))))

(defun execute-hostname (action &key mode)
  (let* ((name (action-target action))
         (current (current-hostname))
         (file-content (string-trim '(#\Newline) (or (read-file-string "/etc/hostname") "")))
         (runtime-ok (equal current name))
         (file-ok (equal file-content name))
         (changed (or (not runtime-ok) (not file-ok))))
    (case mode
      (:check (report (if changed :would-change :unchanged) :target name))
      (:apply
       (unless file-ok (write-privileged-file "/etc/hostname" (format nil "~a~%" name)))
       (unless runtime-ok (run-privileged (list "hostnamectl" "set-hostname" name)))
       (report (if changed :changed :unchanged) :target name))
      (:remove
       (report :unchanged :target name))))) ; nothing sensible to "remove" for a hostname

(register-action-type :hostname #'execute-hostname
  :description "Set the system hostname, both at runtime and persisted")
