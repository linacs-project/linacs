(in-package #:linacs-tests)

(def-suite pipeline-execution
  :description "Tests for pipeline execution")

(def-test simple-pipeline-execution ()
  "Simple pipeline execution works"
  (reset-project-registries)
  (linacs.core:register-provider :test-provider :for :test-feature
    (lambda (facts)
      (declare (ignore facts))
      (list (list :action :copy-file :from "test.txt" :to "/tmp/test.txt"))))

  (linacs.core:define-feature :test-feature
    :description "Test feature"
    :provides :test)

  (let ((actions (linacs.core:resolve-feature-graph (list :test-feature))))
    (it.bese.fiveam:is (and actions (listp actions))))

  (reset-project-registries))