(in-package #:linacs-tests)

(def-suite executor-copy-file
  :description "Tests for copy-file executor")

(def-test copy-file-identity ()
  "Copy file action has correct identity"
  (it.bese.fiveam:is (equal (linacs.core:action-identity '(:action :copy-file :from "test.txt" :to "/tmp/test.txt"))
                             '(:copy-file . "/tmp/test.txt"))))

(def-test copy-file-simple ()
  "Copy file action can be created"
  (it.bese.fiveam:is (typep (linacs.core:file "~/.test.txt") 'linacs.core:action-plist)))