(in-package #:linacs-tests)

(def-suite executor-package-action
  :in linacs-tests
  :description "Tests for package-action executor")
(in-suite executor-package-action)

(def-test package-action-identity ()
  "Package action has correct identity"
  (it.bese.fiveam:is (equal (linacs.core:action-identity '(:action :package :target :emacs :via :system))
                             '(:package :system . :emacs))))

(def-test package-action-simple ()
  "Package action can be created"
  (it.bese.fiveam:is (typep (linacs.core:package :emacs :via :system) 'linacs.core:action-plist)))