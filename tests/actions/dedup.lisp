(in-package #:linacs-tests)

(def-suite action-deduplication
  :description "Tests for action deduplication")

(def-test simple-deduplication ()
  "Identical actions are deduplicated"
  (let ((actions (list '(:action :copy-file :target "/tmp/file.txt")
                       '(:action :copy-file :target "/tmp/file.txt"))))
    (it.bese.fiveam:is (= (length (linacs.core:dedup-actions actions)) 1))))

(def-test different-identities-kept ()
  "Different actions are not deduplicated"
  (let ((actions (list '(:action :copy-file :target "/tmp/file1.txt")
                       '(:action :copy-file :target "/tmp/file2.txt"))))
    (it.bese.fiveam:is (= (length (linacs.core:dedup-actions actions)) 2))))