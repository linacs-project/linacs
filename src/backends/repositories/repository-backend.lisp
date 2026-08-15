;;;; src/backends/repositories/repository-backend.lisp
;;;;
;;;; The repository backend protocol (REFACTOR.org Action 16). A
;;;; REPOSITORY-BACKEND is the first-class representation of one way a
;;;; distro configures a software repository (a Fedora COPR, an Ubuntu PPA,
;;;; an apt line, ...), replacing the historic *repository-methods* plist
;;;; registry. Like the package-backend / service-backend protocols, it wraps
;;;; the primitive operations -- present-p / ensure / remove -- as an object
;;;; with queryable metadata, and the generics REPOSITORY-PRESENT-P /
;;;; REPOSITORY-ENSURE / REPOSITORY-REMOVE default to funcalling those stored
;;;; functions.
;;;;
;;;; The mode-aware driver EXECUTE-REPOSITORY lives in
;;;; src/action-types/repository.lisp: it resolves the backend by :method via
;;;; FIND-REPOSITORY-BACKEND and drives the primitives, signalling an
;;;; EXECUTION-FAILURE when the distro plugin that provides the method was not
;;;; loaded (so `linacs check` surfaces it before `apply`). Keeping the mode
;;;; logic out of this file lets it load early with no dependency on the
;;;; action model or the REPORT helper.
;;;;
;;;; Core ships no repository backends -- 'how a distro adds a repository' is
;;;; exactly the distribution knowledge this design keeps out of core. Distro
;;;; plugins (e.g. linacs-fedora's :dnf-copr) register theirs with
;;;; REGISTER-REPOSITORY-BACKEND.

(in-package :linacs.core)

(defclass repository-backend ()
  ((method        :initarg :method        :reader repository-backend-method
                  :documentation "The method keyword this backend serves
(:DNF-COPR, :APT-PPA, ...).")
   (present-p     :initarg :present-p     :reader repository-backend-present-p-fn
                  :documentation "Optional (action) -> T/NIL predicate for
REPOSITORY-PRESENT-P: T when the repository is already configured.")
   (ensure        :initarg :ensure        :reader repository-backend-ensure-fn
                  :documentation "Optional (action) enabler, adding the
repository idempotently.")
   (remove        :initarg :remove        :reader repository-backend-remove-fn
                  :documentation "Optional (action) remover, removing the
repository idempotently.")
   (description   :initarg :description   :reader repository-backend-description
                  :initform nil
                  :documentation "Free-text description, shown by `linacs list`."))
  (:documentation "A concrete way a distribution configures a software
repository: a method keyword, the primitive present-p/ensure/remove functions,
and a description."))

(defun make-repository-backend (&key method (present-p nil) (ensure nil)
                                     (remove nil) (description nil))
  "Construct a REPOSITORY-BACKEND from its parts. METHOD is the method keyword
(e.g. :DNF-COPR); PRESENT-P / ENSURE / REMOVE are the primitive functions;
DESCRIPTION mirrors the corresponding slot."
  (make-instance 'repository-backend
                 :method method
                 :present-p present-p :ensure ensure :remove remove
                 :description description))

(defvar *repository-backends* (make-hash-table :test 'eq)
  "Maps repository method keyword → REPOSITORY-BACKEND instance. Replaces the
historic *repository-methods* function/plist table (REFACTOR.org Action 16).
Registered by plugins via REGISTER-REPOSITORY-BACKEND -- core ships no
backends, since 'how a distro adds a repository' is exactly the distribution
knowledge this design keeps out of core.")

(defun register-repository-backend (backend)
  "Register REPOSITORY-BACKEND under its :method, replacing any earlier
backend. Like the historic REGISTER-REPOSITORY-METHOD, methods are pure
dispatch -- the last registration wins rather than aborting."
  (setf (gethash (repository-backend-method backend) *repository-backends*) backend)
  backend)

(defun find-repository-backend (method)
  "Look up the REPOSITORY-BACKEND registered for method keyword METHOD, or NIL."
  (gethash method *repository-backends*))

;;; --- Protocol primitives --------------------------------------------------

(defgeneric repository-present-p (backend action)
  (:documentation
   "T when the repository referenced by ACTION is already configured under
BACKEND. Defaults to the backend's PRESENT-P function."))

(defgeneric repository-ensure (backend action)
  (:documentation
   "Ensure the repository referenced by ACTION is configured under BACKEND,
idempotently. Defaults to the backend's ENSURE function."))

(defgeneric repository-remove (backend action)
  (:documentation
   "Remove the repository referenced by ACTION from BACKEND, idempotently.
Defaults to the backend's REMOVE function."))

(defmethod repository-present-p ((backend repository-backend) action)
  (funcall (repository-backend-present-p-fn backend) action))

(defmethod repository-ensure ((backend repository-backend) action)
  (funcall (repository-backend-ensure-fn backend) action))

(defmethod repository-remove ((backend repository-backend) action)
  (funcall (repository-backend-remove-fn backend) action))
