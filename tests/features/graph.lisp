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