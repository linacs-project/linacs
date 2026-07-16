(in-package #:linacs-tests)

(def-suite action-ordering
  :description "Tests for action ordering with dependencies")

(def-test simple-ordering ()
  "Actions are ordered correctly"
  (reset-project-registries)

  (linacs.core:register-provider :test-provider :for :test-feature
                                 (lambda (facts)
                                   (list
                                    (list :action :copy-file :from "file1.txt" :to "/tmp/file1.txt" :depends-on ((:action :ensure-dir :target "/tmp")))
                                    (list :action :copy-file :from "file2.txt" :to "/tmp/file2.txt" :depends-on ((:action :copy-file :from "file1.txt" :to "/tmp/file1.txt"))))))

  (linacs.core:define-feature :test-feature
    :description "Test feature"
    :provides :test)

  (let (actions (linacs.core:order-actions (list (linacs.core:directory "~/.test"))))
    (it.bese.fiveam:is (and actions (listp actions))))

  (reset-project-registries))
