;;;; src/action-types/service.lisp
;;;;
;;;; The :service executor. Enables/starts a systemd unit only if it isn't
;;;; already in the desired enabled/running state.
;;;;
;;;; Usage:
;;;;     (:action :service :target :sshd :enabled t :running t)

(in-package :linacs.core)

(defun service-active-p (name)
  (zerop (nth-value 2 (uiop:run-program (list "systemctl" "is-active" "--quiet" (string-downcase name))
                                          :ignore-error-status t))))

(defun service-enabled-p (name)
  (zerop (nth-value 2 (uiop:run-program (list "systemctl" "is-enabled" "--quiet" (string-downcase name))
                                          :ignore-error-status t))))

(defun execute-service (action &key mode)
  (let* ((target (string-downcase (string (action-target action))))
         (want-enabled (getf action :enabled))
         (want-running (getf action :running))
         (is-enabled (service-enabled-p target))
         (is-running (service-active-p target))
         (needs-enable (and want-enabled (not is-enabled)))
         (needs-start (and want-running (not is-running)))
         (changed (or needs-enable needs-start)))
    (case mode
      (:check (report (if changed :would-change :unchanged)
                       :target target :current (list :enabled is-enabled :running is-running)
                       :desired (list :enabled want-enabled :running want-running)))
      (:apply
       (when needs-enable (run-privileged (list "systemctl" "enable" target)))
       (when needs-start (run-privileged (list "systemctl" "start" target)))
       (report (if changed :changed :unchanged) :target target))
      (:remove
       (run-privileged (list "systemctl" "disable" "--now" target))
       (report :removed :target target)))))

(register-action-type :service #'execute-service
  :description "Enable/start a systemd service unit")
