(in-package #:linacs-tests)

(def-suite executor-service
  :description "Tests for service executor")

(def-test service-identity ()
  "Service action has correct identity"
  (it.bese.fiveam:is (equal (linacs.core:action-identity '(:action :service :target :ssh-daemon :enabled t))
                             '(:service :ssh-daemon))))

(def-test service-simple ()
  "Service action can be created"
  (it.bese.fiveam:is (typep (linacs.core:file "~/.test-service") 'linacs.core:action-plist)))