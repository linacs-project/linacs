;;;; src/action-types/service.lisp
;;;;
;;;; The :service executor. Enables/starts a unit only if it isn't already in
;;;; the desired enabled/running state.
;;;;
;;;; Usage:
;;;;     (:action :service :target :sshd :enabled t :running t)
;;;;     (:action :service :target :syncthing :scope :user :enabled t :running t)
;;;;
;;;; Dispatch (REFACTOR.org Action 16): the executor resolves a
;;;; SERVICE-BACKEND by :scope -- :system (default) → the :systemd backend,
;;;; :user → the :systemd-user backend -- and drives its primitives via
;;;; SERVICE-ENABLED-P / SERVICE-ACTIVE-P / SERVICE-ENABLE / SERVICE-START /
;;;; SERVICE-DISABLE. All distro/scope knowledge (which command, whether sudo)
;;;; lives in the backend, never here.

(in-package :linacs.core)

(defun service-backend-for-action (action)
  "Resolve the SERVICE-BACKEND for ACTION from its :scope (:system default,
:user for user-scope units). Signals EXECUTION-FAILURE if no backend is
registered -- that scope's mechanism plugin was not loaded."
  (let* ((scope (getf action :scope :system))
         (name (if (eq scope :user) :systemd-user :systemd))
         (backend (find-service-backend name)))
    (unless backend
      (error 'execution-failure :action-type :service
             :target (action-target action)
             :underlying (format nil "No service backend registered for ~a (scope ~a)."
                                 name scope)))
    backend))

(defun execute-service (action &key mode)
  (let* ((backend (service-backend-for-action action))
         (target (string-downcase (string (action-target action))))
         (want-enabled (getf action :enabled))
         (want-running (getf action :running))
         (is-enabled (service-enabled-p backend target))
         (is-running (service-active-p backend target))
         (needs-enable (and want-enabled (not is-enabled)))
         (needs-start (and want-running (not is-running)))
         (changed (or needs-enable needs-start)))
    (case mode
      (:check (report (if changed :would-change :unchanged)
                       :target target :current (list :enabled is-enabled :running is-running)
                       :desired (list :enabled want-enabled :running want-running)))
      (:apply
       (when needs-enable (service-enable backend target))
       (when needs-start (service-start backend target))
       (report (if changed :changed :unchanged) :target target))
      (:remove
       (service-disable backend target)
       (report :removed :target target)))))

(register-action-type :service #'execute-service
  :description "Enable/start a systemd service unit")
