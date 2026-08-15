;;;; src/action-types/repository.lisp
;;;;
;;;; The :repository executor. Ensures a distribution software repository
;;;; (PPA, COPR, apt line, ...) is configured before a :package install that
;;;; needs it. The executor itself is distro-agnostic: it dispatches on the
;;;; action's :method through REPOSITORY-BACKENDs registered via
;;;; REGISTER-REPOSITORY-BACKEND. All distro knowledge (how to check/add a
;;;; COPR vs a PPA) lives in plugins, never in core.
;;;;
;;;; Repositories become part of the plan as first-class actions:
;;;;     (:action :repository :target "@wez/wezterm" :method :dnf-copr)
;;;; The :system package executor does not mention repositories; the
;;;; resolve-time injector RESOLVE-REPOSITORY-PREREQUISITES (see
;;;; src/actions.lisp) consults the :repositories catalog and inserts the
;;;; :repository action ahead of the package that needs it.
;;;;
;;;; Identity: (:repository <method> . <target>), so two packages that need
;;;; the same repository collapse into a single action via the standard
;;;; dedup step, and :depends-on edges can reference it.
;;;;
;;;; Usage:
;;;;     (register-repository-backend
;;;;       (make-repository-backend :method :dnf-copr
;;;;         :present-p #'dnf-copr-present-p
;;;;         :ensure    #'dnf-copr-ensure
;;;;         :remove    #'dnf-copr-remove))

(in-package :linacs.core)

(defun execute-repository (action &key mode)
  "Dispatch ACTION (:repository) to its method's REPOSITORY-BACKEND
PRESENT-P/ENSURE/REMOVE functions. An unregistered method is a configuration
error -- the distro plugin that provides it was not loaded -- and is signaled
as an EXECUTION-FAILURE in every mode, so `linacs check` surfaces it before
`apply` would hit a half-configured system."
  (let* ((method-key (getf action :method))
         (backend (find-repository-backend method-key))
         (id (action-target action)))
    (flet ((config-error ()
             (error 'execution-failure :action-type :repository :target id
                    :underlying (format nil "No repository backend ~a registered for ~s. Load the distro plugin that provides it (e.g. linacs-fedora, linacs-ubuntu)."
                                        method-key id))))
      (unless backend
        (config-error))
      (let* ((present-p (repository-backend-present-p-fn backend))
             (present (and present-p (repository-present-p backend action))))
        (case mode
          (:check
           (report (if present :unchanged :would-change) :target id))
          (:apply
           (unless (repository-backend-ensure-fn backend)
             (config-error))
           (if present
               (report :unchanged :target id)
               (progn (repository-ensure backend action)
                      (report :changed :target id))))
          (:remove
           (when (and (repository-backend-remove-fn backend) present)
             (repository-remove backend action))
           (report :removed :target id)))))))

(register-action-type :repository #'execute-repository
  :description "Ensure a distribution software repository (PPA, COPR, apt line, ...) is configured"
  :identity (lambda (a) (list* :repository (getf a :method) (action-target a))))

(register-sudo-requiring-action-type :repository)
