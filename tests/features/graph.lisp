(in-package #:linacs-tests)

(def-suite feature-graph
  :in linacs-tests
  :description "Tests for feature graph resolution")
(in-suite feature-graph)

(def-test simple-feature-graph ()
  "Simple feature dependency graph works"
  (reset-project-registries)
  (linacs.core:define-feature :test-feature
    :description "Test feature"
    :provides :test)
  (linacs.core:define-feature :dependency-feature
    :description "Dependency feature"
    :requires :test-feature)
  (linacs.core:define-feature :prerequisite-feature
    :description "Prerequisite feature"
    :requires :dependency-feature)

  (let ((graph (linacs.core:resolve-feature-graph (list :test-feature))))
    (it.bese.fiveam:is (and graph (listp graph))))

  (reset-project-registries))

(def-test provider-override-beats-via ()
  "collect-actions-from-features prefers a --provider T=P override over the request's :via"
  (reset-project-registries)
  (linacs.core:define-feature :test-editor :description "Editor capability")
  (linacs.core:define-provider :test-emacs :for :test-editor
    (lambda (facts) (declare (ignore facts))
      (list '(:action :package :target :emacs :via :system))))
  (linacs.core:define-provider :test-vim :for :test-editor
    (lambda (facts) (declare (ignore facts))
      (list '(:action :package :target :vim :via :system))))
  (let ((actions (linacs.core::collect-actions-from-features
                  (list (list :feature :test-editor :via :test-emacs))
                  :provider-overrides '((:test-editor . :test-vim)))))
    (is (= (length actions) 1))
    (is (eq (getf (first actions) :target) :vim))
    (is (search "TEST-VIM" (getf (first actions) :source))
        "The action's provenance source names the overridden provider"))
  (reset-project-registries))

(def-test provider-override-absent-uses-via ()
  "Without an override, collect-actions-from-features honors the request's :via"
  (reset-project-registries)
  (linacs.core:define-feature :test-editor :description "Editor capability")
  (linacs.core:define-provider :test-emacs :for :test-editor
    (lambda (facts) (declare (ignore facts))
      (list '(:action :package :target :emacs :via :system))))
  (linacs.core:define-provider :test-vim :for :test-editor
    (lambda (facts) (declare (ignore facts))
      (list '(:action :package :target :vim :via :system))))
  (let ((actions (linacs.core::collect-actions-from-features
                  (list (list :feature :test-editor :via :test-emacs)))))
    (is (= (length actions) 1))
    (is (eq (getf (first actions) :target) :emacs))
    (is (search "TEST-EMACS" (getf (first actions) :source))
        "The action's provenance source names the :via-selected provider"))
  (reset-project-registries))