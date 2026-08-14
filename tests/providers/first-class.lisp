;;;; tests/providers/first-class.lisp
;;;;
;;;; Tests for REFACTOR.org Action 9 -- providers as first-class objects.
;;;;
;;;; The registry stores PROVIDER instances (src/domain/provider.lisp) instead
;;;; of 4-element lists, PROVIDE-ACTIONS is the protocol seam over the provider
;;;; function, SELECT-PROVIDER keeps its historic (values function name)
;;;; contract, and SELECT-PROVIDER-OBJECT exposes the instance for the
;;;; pipeline and reporting. Selection results must be identical to the old
;;;; representation, and provider provenance must be reportable.

(in-package #:linacs-tests)

(def-suite provider-first-class
  :in linacs-tests
  :description "Tests for first-class PROVIDER objects and PROVIDE-ACTIONS (Action 9)")
(in-suite provider-first-class)

(defun provider-facts ()
  "Fixture fact plist used when invoking provider functions directly."
  (list :test-key :test-value))

(def-test define-provider-registers-provider-object ()
  "DEFINE-PROVIDER through REGISTER-PROVIDER stores a PROVIDER instance with
the expected slots, not a 4-element list."
  (reset-project-registries)
  (linacs.core:define-provider :first-class-editor :for :first-class-feature
    :default t :description "A test provider"
    (lambda (facts) (declare (ignore facts)) nil))
  (let ((provider (first (linacs.core:find-providers-for :first-class-feature))))
    (is (typep provider 'linacs.core:provider))
    (is (eq :first-class-editor (linacs.core:provider-name provider)))
    (is (eq :first-class-feature (linacs.core:provider-feature provider)))
    (is (functionp (linacs.core:provider-function provider)))
    (is (eq t (linacs.core:provider-default-p provider)))
    (is (equal "A test provider" (linacs.core:provider-description provider))))
  (reset-project-registries))

(def-test make-provider-constructs-and-provide-actions-calls ()
  "MAKE-PROVIDER builds a provider whose function PROVIDE-ACTIONS invokes with
the given facts."
  (let* ((called-with nil)
         (fn (lambda (facts) (setf called-with facts)
               (list (list :action :package :target :demo :via :system))))
         (provider (linacs.core:make-provider
                    :name :demo :feature :demo-feature :function fn)))
    (is (typep provider 'linacs.core:provider))
    (is (equal (list :action :package :target :demo :via :system)
               (car (linacs.core:provide-actions provider (provider-facts)))))
    (is (equal (provider-facts) called-with))
    (is (null (linacs.core:provider-default-p provider)))))

(def-test register-provider-replaces-same-name ()
  "Re-registering a provider name for the same feature replaces the old
instance (no duplicates accumulate in the registry)."
  (reset-project-registries)
  (linacs.core:define-provider :repl :for :repl-feature
    (lambda (facts) (declare (ignore facts)) (list :first)))
  (linacs.core:define-provider :repl :for :repl-feature
    (lambda (facts) (declare (ignore facts)) (list :second)))
  (let ((providers (linacs.core:find-providers-for :repl-feature)))
    (is (= 1 (length providers)))
    (is (equal (list :second)
               (linacs.core:provide-actions (first providers) (provider-facts)))))
  (reset-project-registries))

(def-test select-provider-returns-function-and-name ()
  "The historic contract is preserved: SELECT-PROVIDER returns (values fn name)
for a sole registered provider."
  (reset-project-registries)
  (linacs.core:define-provider :only :for :sole-feature
    (lambda (facts) (declare (ignore facts)) nil))
  (multiple-value-bind (fn name) (linacs.core:select-provider :sole-feature)
    (is (functionp fn))
    (is (eq :only name)))
  (reset-project-registries))

(def-test select-provider-via-override ()
  "A :via chooses the named provider over a default."
  (reset-project-registries)
  (linacs.core:define-provider :p-default :for :via-feature :default t
    (lambda (facts) (declare (ignore facts)) nil))
  (linacs.core:define-provider :p-via :for :via-feature
    (lambda (facts) (declare (ignore facts)) nil))
  (multiple-value-bind (fn name) (linacs.core:select-provider :via-feature :p-via)
    (is (functionp fn))
    (is (eq :p-via name)))
  (reset-project-registries))

(def-test select-provider-default-selection ()
  "With several providers and exactly one :default t, the default is chosen
without a :via."
  (reset-project-registries)
  (linacs.core:define-provider :p-a :for :default-feature :default t
    (lambda (facts) (declare (ignore facts)) nil))
  (linacs.core:define-provider :p-b :for :default-feature
    (lambda (facts) (declare (ignore facts)) nil))
  (multiple-value-bind (fn name) (linacs.core:select-provider :default-feature)
    (is (functionp fn))
    (is (eq :p-a name)))
  (reset-project-registries))

(def-test select-provider-ambiguous-signals ()
  "Several providers with none marked default signal MISSING-PROVIDER."
  (reset-project-registries)
  (linacs.core:define-provider :p-a :for :ambiguous-feature
    (lambda (facts) (declare (ignore facts)) nil))
  (linacs.core:define-provider :p-b :for :ambiguous-feature
    (lambda (facts) (declare (ignore facts)) nil))
  (signals linacs.core:missing-provider
    (linacs.core:select-provider :ambiguous-feature))
  (reset-project-registries))

(def-test select-provider-object-returns-instance ()
  "SELECT-PROVIDER-OBJECT returns the provider instance itself for sole and
:via selection."
  (reset-project-registries)
  (linacs.core:define-provider :p-a :for :obj-feature
    (lambda (facts) (declare (ignore facts)) nil))
  (let ((p (linacs.core:select-provider-object :obj-feature)))
    (is (typep p 'linacs.core:provider))
    (is (eq :p-a (linacs.core:provider-name p))))
  (reset-project-registries))

(def-test find-provider-returns-function ()
  "FIND-PROVIDER returns the plain provider function (not the instance), the
contract plugin tests rely on via FUNCALL."
  (reset-project-registries)
  (linacs.core:define-provider :fn-contract :for :fn-feature
    (lambda (facts) (declare (ignore facts)) (list :from-fn)))
  (let ((fn (linacs.core:find-provider :fn-contract :for :fn-feature)))
    (is (functionp fn))
    (is (equal (list :from-fn) (funcall fn (provider-facts)))))
  (is (null (linacs.core:find-provider :missing-provider :for :fn-feature)))
  (reset-project-registries))

(def-test pipeline-provenance-stamped-from-provider ()
  "Actions collected for a feature carry provider provenance (feature +
provider name) resolved through the first-class provider object."
  (reset-project-registries)
  (linacs.core:define-feature :prov-feature :description "provenance test feature")
  (linacs.core:define-provider :prov-provider :for :prov-feature
    (lambda (facts) (declare (ignore facts))
      (list (list :action :package :target :provenance-pkg :via :system))))
  (let ((*current-home-thunk* (lambda ()
                                (setf *current-home-name* :prov-test
                                      *current-home-traits* nil
                                      *current-home-use-features* nil
                                      *current-home-actions* nil)
                                (list :name :prov-test
                                      :traits nil
                                      :asset-root nil
                                      :use-features (list (list :feature :prov-feature))
                                      :actions nil))))
    (multiple-value-bind (ordered home)
        (linacs.core:run-pipeline :project-root (uiop:temporary-directory)
                                  :execute-mode :plan-only)
      (declare (ignore home))
      (is (= 1 (length ordered)))
      (let* ((id (linacs.core:action-identity (first ordered)))
             (provenance (linacs.core:action-provenance id)))
        (is (eq :prov-feature (linacs.core:provenance-feature provenance)))
        (is (eq :prov-provider (linacs.core:provenance-provider provenance))))))
  (reset-project-registries))