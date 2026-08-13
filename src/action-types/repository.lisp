;;;; src/action-types/repository.lisp
;;;;
;;;; The :repository executor. Ensures a distribution software repository
;;;; (PPA, COPR, apt line, ...) is configured before a :package install that
;;;; needs it. The executor itself is distro-agnostic: it dispatches on the
;;;; action's :method through *REPOSITORY-METHODS*, registered by plugins via
;;;; REGISTER-REPOSITORY-METHOD. All distro knowledge (how to check/add a
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
;;;;     (register-repository-method :dnf-copr
;;;;       :present-p #'dnf-copr-present-p
;;;;       :ensure    #'dnf-copr-ensure
;;;;       :remove    #'dnf-copr-remove)

(in-package :linacs.core)

(defvar *repository-methods* (make-hash-table :test 'eq)
  "Maps repository method keyword (e.g. :dnf-copr, :apt-ppa) to a plist
  (:present-p <fn> :ensure <fn> :remove <fn>). PRESENT-P takes the action
  and returns T when the repository is already configured; ENSURE adds it
  (idempotent); REMOVE removes it. All three are optional at registration,
  but :present-p and :ensure are required for :apply mode to be meaningful.

  Registered by plugins via REGISTER-REPOSITORY-METHOD -- core ships no
  methods, since 'how a distro adds a repository' is exactly the
  distribution knowledge this design keeps out of core.")

(defun register-repository-method (method &key present-p ensure remove)
  "Register a repository method. METHOD is a keyword (e.g. :dnf-copr).
  PRESENT-P is a function of (action) returning T when the repository is
  already configured; ENSURE is a function of (action) that adds it
  idempotently; REMOVE is a function of (action) that removes it.

  Like REGISTER-PACKAGE-VIA-HANDLER, registering an already-registered
  method keyword replaces the previous registration -- methods are pure
  dispatch, so the last registration wins rather than aborting."
  (setf (gethash method *repository-methods*)
        (list :present-p present-p :ensure ensure :remove remove))
  method)

(defun find-repository-method (method)
  "Return the plist of functions for repository method METHOD, or NIL."
  (gethash method *repository-methods*))

(defun execute-repository (action &key mode)
  "Dispatch ACTION (:repository) to its method's PRESENT-P/ENSURE/REMOVE
  functions. An unregistered method is a configuration error -- the distro
  plugin that provides it was not loaded -- and is signaled as an
  EXECUTION-FAILURE in every mode, so `linacs check` surfaces it before
  `apply` would hit a half-configured system."
  (let* ((method-key (getf action :method))
         (method (find-repository-method method-key))
         (id (action-target action)))
    (flet ((config-error ()
             (error 'execution-failure :action-type :repository :target id
                    :underlying (format nil "No repository method ~a registered for ~s. Load the distro plugin that provides it (e.g. linacs-fedora, linacs-ubuntu)."
                                        method-key id))))
      (unless method
        (config-error))
      (let* ((present-p (getf method :present-p))
             (present (and present-p (funcall present-p action))))
        (case mode
          (:check
           (report (if present :unchanged :would-change) :target id))
          (:apply
           (let ((ensure (getf method :ensure)))
             (unless ensure
               (config-error))
             (if present
                 (report :unchanged :target id)
                 (progn (funcall ensure action)
                        (report :changed :target id)))))
          (:remove
           (let ((remove (getf method :remove)))
             (when (and remove present)
               (funcall remove action)))
           (report :removed :target id)))))))

(register-action-type :repository #'execute-repository
  :description "Ensure a distribution software repository (PPA, COPR, apt line, ...) is configured"
  :identity (lambda (a) (list* :repository (getf a :method) (action-target a))))

(register-sudo-requiring-action-type :repository)
