(in-package #:linacs-tests)

(def-suite executor-symlink
  :in linacs-tests
  :description "Tests for symlink executor")
(in-suite executor-symlink)

(def-test symlink-identity ()
  "Symlink action has correct identity"
  (it.bese.fiveam:is (equal (linacs.core:action-identity '(:action :symlink :target "/tmp/link" :to "/tmp/target"))
                             '(:symlink . "/tmp/link"))))

(def-test symlink-simple ()
  "Symlink action can be created"
  (it.bese.fiveam:is (typep (linacs.core:symlink "~/.test-link") 'linacs.core:action-plist)))

(def-test symlink-apply-in-memory ()
  "symlink becomes a link in an in-memory fs"
  (let* ((fs (linacs.core:make-memory-filesystem))
         (to "/memic/link")
         (ctx (linacs.core:make-execution-context :filesystem fs)))
    (let ((result (linacs.core:execute-action
                   `(:action :symlink :target ,to :to "/memic/real")
                   :mode :apply :context ctx)))
      (is (eq :changed (getf result :status)))
      (is (linacs.core:fs-symlink-p fs to))
      (is (string= "/memic/real" (linacs.core:fs-read-link fs to)))
      (is (string= "x" (progn (linacs.core:fs-write-file fs "/memic/real" "x")
                              (linacs.core:fs-read-file fs to)))))))

(def-test symlink-check-in-memory ()
  "symlink in :check mode reports a :would-change without creating the link"
  (let* ((fs (linacs.core:make-memory-filesystem))
         (to "/memic/link")
         (ctx (linacs.core:make-execution-context :filesystem fs)))
    (let ((result (linacs.core:execute-action
                   `(:action :symlink :target ,to :to "/memic/real")
                   :mode :check :context ctx)))
      (is (eq :would-change (getf result :status)))
      (is (not (linacs.core:fs-symlink-p fs to))))))