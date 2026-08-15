;;;; src/backends/services/systemd.lisp
;;;;
;;;; Built-in service backends (REFACTOR.org Action 16). Registers the two
;;;; systemd SERVICE-BACKENDs -- :systemd (system scope, privileged) and
;;;; :systemd-user (user scope, never privileged) -- that wrap the historic
;;;; `systemctl` commands used by src/action-types/service.lisp and
;;;; src/action-types/timer.lisp. The :service executor drives :systemd (or
;;;; :systemd-user via :scope :user); the :timer executor drives
;;;; :systemd-user, matching its existing `systemctl --user` behaviour.
;;;;
;;;; This file loads after action-types/helpers.lisp (see linacs.asd), so its
;;;; lambdas can reference RUN-PRIVILEGED.

(in-package :linacs.core)

(defun systemctl-run (args &key privileged)
  "Run a systemctl command, escalating via sudo when PRIVILEGED is T."
  (if privileged
      (run-privileged args)
      (uiop:run-program args)))

(register-service-backend
 (make-service-backend
  :name :systemd
  :scope :system
  :privileged-p t
  :description "System-wide systemd units (systemctl, requires sudo)"
  :enabled-p (lambda (name)
               (zerop (nth-value 2
                       (uiop:run-program (list "systemctl" "is-enabled" "--quiet" name)
                                         :ignore-error-status t))))
  :active-p (lambda (name)
              (zerop (nth-value 2
                      (uiop:run-program (list "systemctl" "is-active" "--quiet" name)
                                        :ignore-error-status t))))
  :enable (lambda (name) (systemctl-run (list "systemctl" "enable" name) :privileged t))
  :start (lambda (name) (systemctl-run (list "systemctl" "start" name) :privileged t))
  :disable (lambda (name) (systemctl-run (list "systemctl" "disable" "--now" name) :privileged t))))

(register-service-backend
 (make-service-backend
  :name :systemd-user
  :scope :user
  :privileged-p nil
  :description "User-scope systemd units and timers (systemctl --user, ~/.config/systemd/user)"
  :enabled-p (lambda (name)
               (zerop (nth-value 2
                       (uiop:run-program (list "systemctl" "--user" "is-enabled" "--quiet" name)
                                         :ignore-error-status t))))
  :active-p (lambda (name)
              (zerop (nth-value 2
                      (uiop:run-program (list "systemctl" "--user" "is-active" "--quiet" name)
                                        :ignore-error-status t))))
  :enable (lambda (name) (systemctl-run (list "systemctl" "--user" "enable" "--now" name)))
  :start (lambda (name) (systemctl-run (list "systemctl" "--user" "start" name)))
  :disable (lambda (name) (systemctl-run (list "systemctl" "--user" "disable" "--now" name)))))
