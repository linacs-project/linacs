(in-package #:linacs-tests)

(def-suite privilege-basics
  :description "Tests for privilege detection and preflight notice")

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
