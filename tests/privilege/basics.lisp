(in-package #:linacs-tests)

(def-suite privilege-basics
  :in linacs-tests
  :description "Tests for privilege detection and preflight notice")
(in-suite privilege-basics)

(def-test action-needs-privilege-detects-package ()
  "action-needs-privilege-p returns T for :package actions"
  (is-true (linacs.core:action-needs-privilege-p
            '(:action :package :target "emacs" :via :system)))
  (is-true (linacs.core:action-needs-privilege-p
            '(:action :package :target "vim" :via :pip))))

(def-test action-needs-privilege-detects-flatpak-user ()
  "action-needs-privilege-p returns NIL for :flatpak :user scope"
  (is-false (linacs.core:action-needs-privilege-p
             '(:action :package :target "org.vim.Vim" :via :flatpak :scope :user))))

(def-test action-needs-privilege-skips-non-package ()
  "action-needs-privilege-p returns NIL for non-package actions"
  (is-false (linacs.core:action-needs-privilege-p
             '(:action :copy-file :from "x" :to "/tmp/x")))
  (is-false (linacs.core:action-needs-privilege-p
             '(:action :ensure-dir :target "/tmp/x")))
  (is-false (linacs.core:action-needs-privilege-p
             '(:action :symlink :target "/tmp/link" :to "/tmp/target"))))

(def-test sudo-n-or-a-prefix-defaults-n ()
  "sudo-n-or-a-prefix returns (\"sudo\" \"-n\") when SUDO_ASKPASS is unset"
  (let ((linacs.core:*sudo-askpass* nil))
    (is (equal (linacs.core:sudo-n-or-a-prefix) '("sudo" "-n"))))

  (let ((linacs.core:*sudo-askpass* ""))
    (is (equal (linacs.core:sudo-n-or-a-prefix) '("sudo" "-n")))))

(def-test sudo-n-or-a-prefix-uses-askpass ()
  "sudo-n-or-a-prefix returns (\"sudo\" \"-A\") when SUDO_ASKPASS is set"
  (let ((linacs.core:*sudo-askpass* "/usr/bin/ssh-askpass"))
    (is (equal (linacs.core:sudo-n-or-a-prefix) '("sudo" "-A")))))

(def-test preflight-notice-is-noop-for-no-privilege ()
  "preflight-notice does not error with mixed action lists"
  (is (equal (linacs.core:preflight-notice
              '((:action :copy-file :to "/tmp/x")
                (:action :package :target "emacs" :via :system)))
             nil))
  (is (equal (linacs.core:preflight-notice '()) nil)))

(def-test register-sudo-requiring-action-type-marks-privileged ()
  "A newly registered action type is counted as sudo-needing by
action-needs-privilege-p"
  (let ((linacs.core::*sudo-requiring-action-types* '()))
    (linacs.core:register-sudo-requiring-action-type :my-priv-type)
    (is-true (linacs.core:action-needs-privilege-p
              '(:action :my-priv-type :target "/tmp/x")))))

(def-test register-sudo-requiring-action-type-is-idempotent ()
  "Registering the same action type twice does not duplicate the entry"
  (let ((linacs.core::*sudo-requiring-action-types* '()))
    (linacs.core:register-sudo-requiring-action-type :my-priv-type)
    (linacs.core:register-sudo-requiring-action-type :my-priv-type)
    (is (equal linacs.core::*sudo-requiring-action-types* '(:my-priv-type)))))

(def-test register-non-privileged-package-via-exempts-package ()
  "A registered plist pattern makes matching :package actions report
NIL from action-needs-privilege-p"
  (let ((linacs.core::*non-privileged-package-vias* '()))
    (linacs.core:register-non-privileged-package-via '(:via :pip))
    (is-false (linacs.core:action-needs-privilege-p
               '(:action :package :target "black" :via :pip)))
    (is-true (linacs.core:action-needs-privilege-p
              '(:action :package :target "emacs" :via :system)))))

(def-test register-non-privileged-package-via-is-idempotent ()
  "Registering the same pattern twice does not duplicate the entry"
  (let ((linacs.core::*non-privileged-package-vias* '()))
    (linacs.core:register-non-privileged-package-via '(:via :pip))
    (linacs.core:register-non-privileged-package-via '(:via :pip))
    (is (equal linacs.core::*non-privileged-package-vias* '((:via :pip))))))
