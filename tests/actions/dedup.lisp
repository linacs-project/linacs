(in-package #:linacs-tests)

(def-suite action-deduplication
  :in linacs-tests
  :description "Tests for action deduplication")
(in-suite action-deduplication)

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

(def-test default-dedup-behavior-is-conflict ()
  "Same-identity, different-content, same-priority actions on a type with
no registered dedup behavior signal ACTION-CONFLICT (the default)."
  (linacs.core:register-action-type :test-conflict-type (lambda (a &key mode) (declare (ignore a mode))))
  (it.bese.fiveam:signals linacs.core:action-conflict
    (linacs.core:dedup-actions
      (list '(:action :test-conflict-type :target "/tmp/x" :content "a")
            '(:action :test-conflict-type :target "/tmp/x" :content "b")))))

(def-test additive-dedup-behavior-keeps-both ()
  "A type registered with :dedup-behavior :additive keeps both
same-identity, same-priority actions instead of signaling a conflict."
  (linacs.core:register-action-type :test-additive-type (lambda (a &key mode) (declare (ignore a mode)))
    :dedup-behavior :additive)
  (let ((result (linacs.core:dedup-actions
                  (list '(:action :test-additive-type :target "/tmp/x" :content "a")
                        '(:action :test-additive-type :target "/tmp/x" :content "b")))))
    (it.bese.fiveam:is (= (length result) 2))))

(def-test config-lines-additive-dedup ()
  ":config-lines is registered with :dedup-behavior :additive, so
same-identity duplicates warn and both survive rather than conflicting."
  (let ((result (linacs.core:dedup-actions
                  (list '(:action :config-lines :target "/tmp/cfg" :ensure ("x = 1"))
                        '(:action :config-lines :target "/tmp/cfg" :ensure ("y = 2"))))))
    (it.bese.fiveam:is (= (length result) 2))))

(def-test additive-respects-priority ()
  "On an :additive type, a user-priority action still wins over a
provider-priority action with the same identity, and the provider copy
is dropped rather than both surviving."
  (linacs.core:register-action-type :test-additive-priority (lambda (a &key mode) (declare (ignore a mode)))
    :dedup-behavior :additive)
  (let ((result (linacs.core:dedup-actions
                  (list '(:action :test-additive-priority :target "/tmp/x" :content "p"
                                 :priority :provider :source "provider")
                        '(:action :test-additive-priority :target "/tmp/x" :content "u"
                                 :priority :user :source "user")))))
    (it.bese.fiveam:is (= (length result) 1))
    (it.bese.fiveam:is (string= (getf (first result) :source) "user"))))
