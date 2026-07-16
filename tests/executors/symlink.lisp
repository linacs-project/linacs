(in-package #:linacs-tests)

(def-suite executor-symlink
  :description "Tests for symlink executor")

(def-test symlink-identity ()
  "Symlink action has correct identity"
  (it.bese.fiveam:is (equal (linacs.core:action-identity '(:action :symlink :target "/tmp/link" :to "/tmp/target"))
                             '(:symlink . "/tmp/link"))))

(def-test symlink-simple ()
  "Symlink action can be created"
  (it.bese.fiveam:is (typep (linacs.core:symlink "~/.test-link") 'linacs.core:action-plist)))