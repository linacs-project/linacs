(in-package #:linacs-tests)

(def-suite pipeline-disabled-actions
  :description "Tests for disabled actions with :prune-explicitly-disabled trait")

(def-test disabled-actions-are-not-removed-in-dry-run ()
  "Disabled actions with :prune-explicitly-disabled trait are NOT deleted in --dry-run mode"
  (reset-project-registries)

  (let ((test-file (merge-pathnames (user-homedir-pathname) ".test-disabled-file.txt")))
    ;; Create a file
    (when (probe-file test-file)
      (delete-file test-file))
    (with-open-file (s test-file :direction :output :if-exists :supersede)
      (write-line "test" s))

    ;; Set up home with trait
    (let ((*current-home-thunk* (lambda ()
                                  (setf *current-home-name* :test)
                                  (setf *current-home-traits* '(:prune-explicitly-disabled))
                                  (setf *current-home-actions* nil)
                                  (file test-file :from "test-content")))))

    ;; Run in dry-run mode (should NOT delete the file)
    (multiple-value-bind (ordered home)
        (run-pipeline :execute-mode :plan-only)
      ;; File should still exist after dry-run
      (it.bese.fiveam:is (probe-file test-file)))))

(def-test disabled-actions-are-removed-in-apply-mode ()
  "Disabled actions with :prune-explicitly-disabled trait ARE deleted in apply mode"
  (reset-project-registries)

  (let ((test-file (merge-pathnames (user-homedir-pathname) ".test-disabled-file.txt")))
    ;; Create a file
    (when (probe-file test-file)
      (delete-file test-file))
    (with-open-file (s test-file :direction :output :if-exists :supersede)
      (write-line "test" s))

    ;; Set up home with trait
    (let ((*current-home-thunk* (lambda ()
                                  (setf *current-home-name* :test)
                                  (setf *current-home-traits* '(:prune-explicitly-disabled))
                                  (setf *current-home-actions* nil)
                                  (file test-file :from "test-content")))))

    ;; Run in apply mode (SHOULD delete the file)
    (multiple-value-bind (ordered home)
        (run-pipeline :execute-mode :apply)
      ;; File should be deleted after apply
      (it.bese.fiveam:is (not (probe-file test-file))))))

(def-test disabled-actions-without-trait-are-skipped-in-dry-run ()
  "Disabled actions WITHOUT :prune-explicitly-disabled trait are skipped in dry-run"
  (reset-project-registries)

  (let ((test-file (merge-pathnames (user-homedir-pathname) ".test-disabled-file-no-trait.txt")))
    ;; Create a file
    (when (probe-file test-file)
      (delete-file test-file))
    (with-open-file (s test-file :direction :output :if-exists :supersede)
      (write-line "test" s))

    ;; Set up home WITHOUT trait
    (let ((*current-home-thunk* (lambda ()
                                  (setf *current-home-name* :test)
                                  (setf *current-home-traits* nil)
                                  (setf *current-home-actions* nil)
                                  (file test-file :from "test-content")))))

    ;; Run in dry-run mode (should NOT delete the file)
    (multiple-value-bind (ordered home)
        (run-pipeline :execute-mode :plan-only)
      ;; File should still exist (action was skipped, not pruned)
      (it.bese.fiveam:is (probe-file test-file)))))
