(in-package #:linacs-tests)

(def-suite pipeline-disabled-actions
  :in linacs-tests
  :description "Tests for disabled actions with :prune-explicitly-disabled trait")
(in-suite pipeline-disabled-actions)

(def-test disabled-actions-are-not-removed-in-dry-run ()
  "Disabled actions with :prune-explicitly-disabled trait are NOT deleted in --dry-run mode"
  (reset-project-registries)

  (let ((test-file (concatenate 'string (namestring (user-homedir-pathname)) ".test-disabled-file.txt")))
    ;; Create a file
    (when (probe-file test-file)
      (delete-file test-file))
    (with-open-file (s test-file :direction :output :if-exists :supersede)
      (write-line "test" s))

    ;; Set up home with trait and run in dry-run mode (should NOT delete the file)
    (let ((*current-home-thunk* (lambda ()
                                  (setf *current-home-name* :test)
                                  (setf *current-home-traits* '(:prune-explicitly-disabled))
                                  (setf *current-home-actions* nil)
                                  (push (list :action :copy-file
                                               :target test-file :to test-file
                                               :from "test-content"
                                               :disabled t
                                               :priority :user :source "user:test")
                                        *current-home-actions*)
                                  (list :name :test
                                        :traits '(:prune-explicitly-disabled)
                                        :use-features nil
                                        :actions (reverse *current-home-actions*)))))
      (multiple-value-bind (ordered home)
          (run-pipeline :execute-mode :plan-only)
        (declare (ignore ordered home))
        ;; File should still exist after dry-run
        (it.bese.fiveam:is (probe-file test-file))))))

(def-test disabled-actions-are-removed-in-apply-mode ()
  "Disabled actions with :prune-explicitly-disabled trait ARE deleted in apply mode"
  (reset-project-registries)

  (let ((test-file (concatenate 'string (namestring (user-homedir-pathname)) ".test-disabled-file.txt")))
    ;; Create a file
    (when (probe-file test-file)
      (delete-file test-file))
    (with-open-file (s test-file :direction :output :if-exists :supersede)
      (write-line "test" s))

    ;; Set up home with trait and run in apply mode (SHOULD delete the file)
    (let ((*current-home-thunk* (lambda ()
                                  (setf *current-home-name* :test)
                                  (setf *current-home-traits* '(:prune-explicitly-disabled))
                                  (setf *current-home-actions* nil)
                                  (push (list :action :copy-file
                                               :target test-file :to test-file
                                               :from "test-content"
                                               :disabled t
                                               :priority :user :source "user:test")
                                        *current-home-actions*)
                                  (list :name :test
                                        :traits '(:prune-explicitly-disabled)
                                        :use-features nil
                                        :actions (reverse *current-home-actions*)))))
      (multiple-value-bind (ordered home)
          (run-pipeline :execute-mode :apply)
        (declare (ignore ordered home))
        ;; File should be deleted after apply
        (it.bese.fiveam:is (not (probe-file test-file)))))))

(def-test disabled-actions-without-trait-are-skipped-in-dry-run ()
  "Disabled actions WITHOUT :prune-explicitly-disabled trait are skipped in dry-run"
  (reset-project-registries)

  (let ((test-file (concatenate 'string (namestring (user-homedir-pathname)) ".test-disabled-file-no-trait.txt")))
    ;; Create a file
    (when (probe-file test-file)
      (delete-file test-file))
    (with-open-file (s test-file :direction :output :if-exists :supersede)
      (write-line "test" s))

    ;; Set up home WITHOUT trait and run in dry-run mode (should NOT delete the file)
    (let ((*current-home-thunk* (lambda ()
                                  (setf *current-home-name* :test)
                                  (setf *current-home-traits* nil)
                                  (setf *current-home-actions* nil)
                                  (push (list :action :copy-file
                                               :target test-file :to test-file
                                               :from "test-content"
                                               :disabled t
                                               :priority :user :source "user:test")
                                        *current-home-actions*)
                                  (list :name :test
                                        :traits nil
                                        :use-features nil
                                        :actions (reverse *current-home-actions*)))))
      (multiple-value-bind (ordered home)
          (run-pipeline :execute-mode :plan-only)
        (declare (ignore ordered home))
        ;; File should still exist (action was skipped, not pruned)
        (it.bese.fiveam:is (probe-file test-file))))))
