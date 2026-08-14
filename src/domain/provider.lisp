;;;; src/domain/provider.lisp
;;;;
;;;; The first-class PROVIDER object (REFACTOR.org Thought 9 / Action 9). A
;;;; provider is a plain function from facts to a list of action plists,
;;;; registered against a feature name. This file gives that pair an explicit
;;;; representation: a PROVIDER instance carries the name, the feature it
;;;; serves, the function, the :default t flag, and the :description doc
;;;; string, and PROVIDE-ACTIONS is the protocol seam over the function.
;;;;
;;;; The registry itself (*PROVIDERS*) and the selection machinery live in
;;;; src/providers.lisp; that file stores instances of this class. Selection
;;;; results are identical to the historic 4-element-list representation --
;;;; SELECT-PROVIDER still returns (values function name), and the newly
;;;; added SELECT-PROVIDER-OBJECT returns the instance for the pipeline and
;;;; reporting to interrogate (provenance, default/description display).
;;;;
;;;; Usage (author-facing, unchanged from the spec):
;;;;     (define-provider :emacs :for :editor :default t :description "..."
;;;;       (lambda (facts) (list '(:action :package :target :emacs :via :system))))
;;;;
;;;; This loads before src/providers.lisp so REGISTER-PROVIDER can construct
;;;; instances (see linacs.asd).

(in-package :linacs.core)

(defclass provider ()
  ((name        :initarg :name        :reader provider-name
                :documentation "The provider's own name (a keyword, e.g. :EMACS).")
   (feature     :initarg :feature     :reader provider-feature
                :documentation "The feature this provider implements (a keyword, e.g. :EDITOR).")
   (function    :initarg :function    :reader provider-function
                :documentation "The plain function from facts to a list of action plists.")
   (default-p   :initarg :default-p   :reader provider-default-p
                :documentation "T when this provider is the automatic choice for its
feature among several, i.e. registered with :default t.")
   (description :initarg :description :reader provider-description
                :documentation "Free-text description, shown by `linacs list` and
similar reporting."))
  (:documentation "A concrete implementation of a feature: a name, the feature it
serves, the pure function mapping facts to actions, and the optional :default /
:description flags that drive automatic selection and reporting."))

(defun make-provider (&key name feature function (default-p nil) (description nil))
  "Construct a PROVIDER from its parts. FUNCTION is the plain provider
function (facts -> list of action plists); DEFAULT-P and DESCRIPTION mirror
the :default / :description options of DEFINE-PROVIDER."
  (make-instance 'provider
                 :name name :feature feature :function function
                 :default-p default-p :description description))

(defgeneric provide-actions (provider facts)
  (:documentation
   "Produce the list of action plists PROVIDER contributes for FACTS. This is
the object-level protocol seam over the provider function: the single method
calls the wrapped function, so providers stay pure, unit-testable functions
while the pipeline and authors interact with a PROVIDER object (REFACTOR.org
Thought 9)."))

(defmethod provide-actions ((provider provider) facts)
  (funcall (provider-function provider) facts))
