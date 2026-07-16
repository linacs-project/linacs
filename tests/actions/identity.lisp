(in-package #:linacs-tests)

(def-suite action-identity
  :description "Tests for action identity computation")

(def-test simple-identity ()
  "Simple action types have straightforward identities"
  (it.bese.fiveam:is (equal (linacs.core:action-identity '(:action :copy-file :target "/tmp/x"))
                             '(:copy-file . "/tmp/x")))
  (it.bese.fiveam:is (equal (linacs.core:action-identity '(:action :ensure-dir :target "/tmp/dir"))
                             '(:ensure-dir . "/tmp/dir")))
  (it.bese.fiveam:is (equal (linacs.core:action-identity '(:action :symlink :target "/tmp/link" :to "/tmp/target"))
                             '(:symlink . "/tmp/link"))))

(def-test multi-element-identity ()
  "Actions with multiple elements can have identical identities"
  (it.bese.fiveam:is (equal (linacs.core:action-identity '(:action :copy-file :target "/tmp/file" :from "/src/file"))
                             '(:copy-file . "/tmp/file"))))