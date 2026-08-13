(in-package #:linacs-tests)

(def-suite executor-copy-file
  :in linacs-tests
  :description "Tests for copy-file executor")
(in-suite executor-copy-file)

(def-test copy-file-identity ()
  "Copy file action has correct identity"
  (it.bese.fiveam:is (equal (linacs.core:action-identity '(:action :copy-file :from "test.txt" :to "/tmp/test.txt"))
                             '(:copy-file . "/tmp/test.txt"))))

(def-test copy-file-simple ()
  "Copy file action can be created"
  (it.bese.fiveam:is (typep (linacs.core:file "~/.test.txt") 'linacs.core:action-plist)))

(def-test copy-file-check-mode-reports-would-change-for-missing-target ()
  "A copy-file whose target doesn't exist is a :would-change, not an error."
  (with-scratch-dir (dir)
    (let* ((src (merge-pathnames "src.txt" dir))
           (dst (merge-pathnames "dst.txt" dir)))
      (with-open-file (s src :direction :output :if-exists :supersede)
        (write-string "content" s))
      (let ((result (linacs.core:execute-action
                     (list :action :copy-file :to (namestring dst) :from (namestring src))
                     :mode :check)))
        (is (eq (getf result :status) :would-change)
            "missing target should report :would-change, got ~s" result)))))

(def-test copy-file-check-mode-handles-dangling-symlink-target ()
  "A dangling symlink at the target reads as absent (SBCL's probe-file
  returns the dangling link, which can no longer trap the executor)."
  (with-scratch-dir (dir)
    (let* ((src (merge-pathnames "src.txt" dir))
           (dst (merge-pathnames "dst.txt" dir)))
      (with-open-file (s src :direction :output :if-exists :supersede)
        (write-string "content" s))
      (uiop:run-program (list "ln" "-s" "nowhere" (namestring dst))
                        :ignore-error-status t)
      (let ((result (linacs.core:execute-action
                     (list :action :copy-file :to (namestring dst) :from (namestring src))
                     :mode :check)))
        (is (listp result) "check should return a plist, got ~s" result)
        (is (eq (getf result :status) :would-change)
            "dangling symlink target should report :would-change, got ~s" result)))))