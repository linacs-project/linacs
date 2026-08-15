;;;; src/backends/services/service-backend.lisp
;;;;
;;;; The service backend protocol (REFACTOR.org Action 16). A
;;;; SERVICE-BACKEND is the first-class representation of one mechanism for
;;;; enabling/starting/stopping a unit -- :systemd (system scope),
;;;; :systemd-user (user scope), or a plugin's custom :openrc, :runit, ...
;;;; It wraps the five primitive operations a service executor needs:
;;;; enabled-p / active-p probes and enable / start / disable actions.
;;;;
;;;; The seam is the primitive generic functions SERVICE-ENABLED-P /
;;;; SERVICE-ACTIVE-P / SERVICE-ENABLE / SERVICE-START / SERVICE-DISABLE.
;;;; Their default methods funcall the functions stored on the backend, so a
;;;; backend that only provides functions satisfies the protocol, and a
;;;; plugin that needs something unusual may defmethod the generic instead.
;;;; The mode-aware executors that drive these primitives (:service, :timer)
;;;; live in src/action-types/ -- they resolve a backend by name/scope and
;;;; call the primitives. Keeping the mode logic out of this file lets it
;;;; load early (next to the package-backend protocol) with no dependency on
;;;; the action model or the REPORT helper.
;;;;
;;;; The registry itself (*SERVICE-BACKENDS*) is the single place a scope or
;;;; mechanism resolves to its implementation. Built-in backends are
;;;; registered in systemd.lisp in this directory; plugins register further
;;;; mechanisms the same way.

(in-package :linacs.core)

(defclass service-backend ()
  ((name          :initarg :name          :reader service-backend-name
                  :documentation "The mechanism keyword this backend serves
(:SYSTEMD, :SYSTEMD-USER, ...).")
   (scope         :initarg :scope         :reader service-backend-scope
                  :initform :system
                  :documentation "The unit scope: :SYSTEM (system-wide units,
privileged) or :USER (units under ~/.config/systemd/user, never privileged).")
   (enabled-p     :initarg :enabled-p     :reader service-enabled-p-fn
                  :documentation "Optional (name) -> T/NIL predicate for
SERVICE-ENABLED-P, defaulting to a systemctl is-enabled probe.")
   (active-p      :initarg :active-p      :reader service-active-p-fn
                  :documentation "Optional (name) -> T/NIL predicate for
SERVICE-ACTIVE-P, defaulting to a systemctl is-active probe.")
   (enable        :initarg :enable        :reader service-enable-fn
                  :documentation "Optional (name) enabler, defaulting to
systemctl enable.")
   (start         :initarg :start         :reader service-start-fn
                  :documentation "Optional (name) starter, defaulting to
systemctl start.")
   (disable       :initarg :disable       :reader service-disable-fn
                  :documentation "Optional (name) disabler/stopper, defaulting
to systemctl disable --now.")
   (privileged-p  :initarg :privileged-p  :reader service-backend-privileged-p
                  :initform t
                  :documentation "T when operating units via this backend
needs privilege escalation (system scope), NIL when it never does (user
scope). Consulted by ACTION-NEEDS-PRIVILEGE-P.")
   (description   :initarg :description   :reader service-backend-description
                  :initform nil
                  :documentation "Free-text description, shown by `linacs list`."))
  (:documentation "A concrete mechanism for managing units: a name, the unit
scope it operates on, the primitive functions that probe and mutate unit
state, privilege semantics, and a description."))

(defun make-service-backend (&key name scope (enabled-p nil) (active-p nil)
                                  (enable nil) (start nil) (disable nil)
                                  (privileged-p t) (description nil))
  "Construct a SERVICE-BACKEND from its parts. NAME is the mechanism keyword
(:SYSTEMD, :SYSTEMD-USER, ...); SCOPE is :SYSTEM or :USER; ENABLED-P /
ACTIVE-P / ENABLE / START / DISABLE are the primitive functions; PRIVILEGED-P
and DESCRIPTION mirror the corresponding slots."
  (make-instance 'service-backend
                 :name name :scope scope
                 :enabled-p enabled-p :active-p active-p
                 :enable enable :start start :disable disable
                 :privileged-p privileged-p :description description))

(defvar *service-backends* (make-hash-table :test 'eq)
  "Maps mechanism keyword → SERVICE-BACKEND instance. Built-in entries
(:systemd, :systemd-user) are registered in src/backends/services/systemd.lisp;
plugins register further mechanisms (e.g. :openrc) the same way.")

(defun register-service-backend (backend)
  "Register SERVICE-BACKEND under its :name, replacing any earlier backend."
  (setf (gethash (service-backend-name backend) *service-backends*) backend)
  backend)

(defun find-service-backend (name)
  "Look up the SERVICE-BACKEND registered for mechanism NAME, or NIL."
  (gethash name *service-backends*))

;;; --- Protocol primitives --------------------------------------------------

(defgeneric service-enabled-p (backend name)
  (:documentation
   "T when unit NAME is currently enabled under BACKEND. Defaults to the
backend's ENABLED-P function."))

(defgeneric service-active-p (backend name)
  (:documentation
   "T when unit NAME is currently active (running) under BACKEND. Defaults to
the backend's ACTIVE-P function."))

(defgeneric service-enable (backend name)
  (:documentation
   "Enable unit NAME under BACKEND, idempotently. Defaults to the backend's
ENABLE function. The backend decides whether the underlying command needs
privilege escalation (see SERVICE-BACKEND-PRIVILEGED-P)."))

(defgeneric service-start (backend name)
  (:documentation
   "Start unit NAME under BACKEND, idempotently. Defaults to the backend's
START function."))

(defgeneric service-disable (backend name)
  (:documentation
   "Disable and stop unit NAME under BACKEND, idempotently. Defaults to the
backend's DISABLE function."))

(defmethod service-enabled-p ((backend service-backend) name)
  (funcall (service-enabled-p-fn backend) name))

(defmethod service-active-p ((backend service-backend) name)
  (funcall (service-active-p-fn backend) name))

(defmethod service-enable ((backend service-backend) name)
  (funcall (service-enable-fn backend) name))

(defmethod service-start ((backend service-backend) name)
  (funcall (service-start-fn backend) name))

(defmethod service-disable ((backend service-backend) name)
  (funcall (service-disable-fn backend) name))
