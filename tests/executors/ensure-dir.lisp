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

(def-test ensure-dir-apply-in-memory ()
  "ensure-dir creates the directory in an in-memory fs"
  (let* ((fs (linacs.core:make-memory-filesystem))
         (to "/memic/app/config")
         (ctx (linacs.core:make-execution-context :filesystem fs)))
    (let ((result (linacs.core:execute-action
                   `(:action :ensure-dir :target ,to :mode #o755)
                   :mode :apply :context ctx)))
      (is (eq :changed (getf result :status)))
      (is (linacs.core:fs-directory-p fs to)))))

(def-test ensure-dir-check-in-memory ()
  "ensure-dir in :check mode reports a :would-change for a missing dir without creating it"
  (let* ((fs (linacs.core:make-memory-filesystem))
         (to "/memic/app/config")
         (ctx (linacs.core:make-execution-context :filesystem fs)))
    (let ((result (linacs.core:execute-action
                   `(:action :ensure-dir :target ,to :mode #o755)
                   :mode :check :context ctx)))
      (is (eq :would-change (getf result :status)))
      (is (not (linacs.core:fs-directory-p fs to))))))