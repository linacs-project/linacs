(in-package #:linacs-tests)

(def-suite executor-config-lines
  :in linacs-tests
  :description "Tests for config-lines executor")
(in-suite executor-config-lines)

(def-test config-lines-identity ()
  "Config-lines action has correct identity"
  (let ((identity (linacs.core:action-identity '(:action :config-lines :target "~/.config/app/config" :ensure ("key = value")))))
    (is (eq (first identity) :config-lines))
    (is (equal (second identity) '((:ensure "key = value") (:remove))))
    (is (string= (third identity) "~/.config/app/config"))))