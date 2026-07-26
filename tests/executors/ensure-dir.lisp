(in-package #:linacs-tests)

(def-suite executor-ensure-dir
  :in linacs-tests
  :description "Tests for ensure-dir executor")
(in-suite executor-ensure-dir)

(def-test ensure-dir-identity ()
  "Ensure dir action has correct identity"
  (it.bese.fiveam:is (equal (linacs.core:action-identity '(:action :ensure-dir :target "/tmp/dir"))
                             '(:ensure-dir . "/tmp/dir"))))

(def-test ensure-dir-simple ()
  "Ensure dir action can be created"
  (it.bese.fiveam:is (typep (linacs.core:directory "~/.test-dir") 'linacs.core:action-plist)))