;;;; src/backends/packages/package-backend.lisp
;;;;
;;;; The package backend protocol (REFACTOR.org Action 15). A PACKAGE-BACKEND
;;;; is the first-class representation of one :package :via ecosystem (:system,
;;;; :pip, :npm, :flatpak, :toolbox, :podman, :appimage, or a plugin's custom
;;;; :rpm-ostree). It wraps the historic mode-aware executor function so that
;;;; dispatch results are identical to the old *package-via-handlers* table,
;;;; while making the dispatch surface an object with queryable metadata
;;;; (via, executor, privilege requirement, description).
;;;;
;;;; Two seams:
;;;;   * EXECUTE-PACKAGE-BACKEND is the dispatch generic. The default method
;;;;     funcalls the wrapped executor, exactly like EXECUTE-PACKAGE did with
;;;;     a handler from *package-via-handlers*. Plugins may override the
;;;;     generic or (more commonly) supply an executor function at
;;;;     registration time -- both paths run through the same seam.
;;;;   * the INSTALLED-P / INSTALL / UNINSTALL generic functions give the
;;;;     protocol its stated surface. Their default methods derive from the
;;;;     wrapped executor (:check / :apply / :remove mode), so a backend that
;;;;     only provides an executor function still satisfies the full protocol.
;;;;
;;;; The registry itself (*PACKAGE-BACKENDS*) replaces *package-via-handlers*.
;;;; Built-in backends are registered in backends.lisp in this directory;
;;;; plugins register further :via ecosystems the same way.

(in-package :linacs.core)

(defclass package-backend ()
  ((via         :initarg :via         :reader backend-via
                :documentation "The :via keyword this backend serves (:SYSTEM, :PIP, ...).")
   (executor    :initarg :executor    :reader backend-executor
                :documentation "The mode-aware executor function, (action name &key
mode), that EXECUTE-PACKAGE-BACKEND dispatches to. This is the historic
:package handler contract, preserved unchanged.")
   (installed-p :initarg :installed-p :reader backend-installed-p-fn
                :initform nil
                :documentation "Optional (action name) -> T/NIL predicate for
INSTALLED-P, defaulting to a :check-mode probe via the executor.")
   (install     :initarg :install     :reader backend-install-fn
                :initform nil
                :documentation "Optional (action name) installer, defaulting to a
:apply-mode call via the executor.")
   (uninstall   :initarg :uninstall   :reader backend-uninstall-fn
                :initform nil
                :documentation "Optional (action name) uninstaller, defaulting to a
:remove-mode call via the executor.")
   (privileged-p :initarg :privileged-p :reader backend-privileged-p
                :initform t
                :documentation "T when installing via this backend needs privilege
escalation, NIL when it never does, or a function of one argument (the action)
for scope-dependent cases (e.g. flatpak :scope :user). Consulted by
ACTION-NEEDS-PRIVILEGE-P with *non-privileged-package-vias* as fallback.")
   (description :initarg :description :reader backend-description
                :initform nil
                :documentation "Free-text description, shown by `linacs list`."))
  (:documentation "A concrete implementation of a :package :via ecosystem: a name,
the executor function that runs it, optional installed-p/install/uninstall
functions, privilege semantics, and a description."))

(defun make-package-backend (&key via executor
                                 (installed-p nil) (install nil) (uninstall nil)
                                 (privileged-p t) (description nil))
  "Construct a PACKAGE-BACKEND from its parts. VIA is the :via keyword;
EXECUTOR is the mode-aware handler function; INSTALLED-P / INSTALL /
UNINSTALL are optional specialized functions; PRIVILEGED-P and DESCRIPTION
mirror the corresponding slots."
  (make-instance 'package-backend
                 :via via :executor executor
                 :installed-p installed-p :install install :uninstall uninstall
                 :privileged-p privileged-p :description description))

(defvar *package-backends* (make-hash-table :test 'eq)
  "Maps :via keyword → PACKAGE-BACKEND instance. Replaces the historic
*package-via-handlers* function table (REFACTOR.org Action 15).")

(defun register-package-backend (backend)
  "Register PACKAGE-BACKEND under its :via, replacing any earlier backend."
  (setf (gethash (backend-via backend) *package-backends*) backend)
  backend)

(defun find-package-backend (via)
  "Look up the PACKAGE-BACKEND registered for :via VIA, or NIL."
  (gethash via *package-backends*))

;;; --- Dispatch protocol ---------------------------------------------------

(defgeneric execute-package-backend (backend action name &key mode)
  (:documentation
   "Execute ACTION (a :package action plist, with target already resolved to
the string NAME) via BACKEND, in MODE (:apply :check :remove). This is the
object-level protocol seam over the executor function: the default method
funcalls the wrapped executor, so dispatch results are identical to the
historic via-handler table."))

(defmethod execute-package-backend ((backend package-backend) action name &key mode)
  (funcall (backend-executor backend) action name :mode mode))

;;; --- Protocol accessors ---------------------------------------------------

(defgeneric backend-installed-p (backend action name)
  (:documentation
   "T when NAME is installed via BACKEND for ACTION. Defaults to a :check-mode
probe through the executor (status :unchanged means installed)."))

(defgeneric backend-install (backend action name)
  (:documentation
   "Install NAME via BACKEND for ACTION, returning the executor's report.
Defaults to a :apply-mode call through the executor."))

(defgeneric backend-uninstall (backend action name)
  (:documentation
   "Uninstall NAME via BACKEND for ACTION, returning the executor's report.
Defaults to a :remove-mode call through the executor."))

(defmethod backend-installed-p ((backend package-backend) action name)
  (if (backend-installed-p-fn backend)
      (funcall (backend-installed-p-fn backend) action name)
      (eq (getf (execute-package-backend backend action name :mode :check) :status)
          :unchanged)))

(defmethod backend-install ((backend package-backend) action name)
  (if (backend-install-fn backend)
      (funcall (backend-install-fn backend) action name)
      (execute-package-backend backend action name :mode :apply)))

(defmethod backend-uninstall ((backend package-backend) action name)
  (if (backend-uninstall-fn backend)
      (funcall (backend-uninstall-fn backend) action name)
      (execute-package-backend backend action name :mode :remove)))

(defun backend-needs-privilege-p (backend action)
  "T if installing via BACKEND for ACTION needs privilege escalation.
PRIVILEGED-P may be a constant or a function of the action (e.g. flatpak
:scope :user)."
  (let ((p (backend-privileged-p backend)))
    (if (functionp p) (funcall p action) p)))
