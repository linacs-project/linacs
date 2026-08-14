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

(def-test config-lines-apply-in-memory ()
  "config-lines writes through the filesystem backend into an in-memory fs"
  (let* ((fs (linacs.core:make-memory-filesystem))
         (to "/memic/config")
         (ctx (linacs.core:make-execution-context :filesystem fs)))
    (let* ((result (linacs.core:execute-action
                    `(:action :config-lines :target ,to :ensure ("line one") :remove nil)
                    :mode :apply :context ctx)))
      (is (eq :changed (getf result :status)))
      (is (string= (format nil "line one~%") (linacs.core:fs-read-file fs to))))))