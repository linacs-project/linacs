(in-package #:linacs-tests)

(def-suite executor-config-lines
  :description "Tests for config-lines executor")

(def-test config-lines-identity ()
  "Config-lines action has correct identity"
  (it.bese.fiveam:is (equal (linacs.core:action-identity '(:action :config-lines :target "~/.config/app/config" :ensure ("key = value")))
                             '(:config-lines ("key = value") . "~/.config/app/config"))))