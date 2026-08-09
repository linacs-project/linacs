(in-package #:linacs-tests)

(def-suite pipeline-hooks
  :in linacs-tests
  :description "Tests for pipeline hook registration and deduplication")
(in-suite pipeline-hooks)

(def-test register-pipeline-hook-deduplicates-same-function ()
  "Registering the same hook function twice for a point yields one entry"
  (reset-project-registries)
  (let ((hook (lambda (facts actions)
                (declare (ignore facts actions)))))
    (register-pipeline-hook :after-resolve hook)
    (register-pipeline-hook :after-resolve hook)
    (is (= 1 (length (gethash :after-resolve *pipeline-hooks*))))
    (is (eq hook (first (gethash :after-resolve *pipeline-hooks*))))))

(def-test register-pipeline-hook-keeps-distinct-functions ()
  "Distinct hook functions (even with equal code) for the same point are
all kept, in registration order. Dedup is EQ-based on the function object."
  (reset-project-registries)
  (let ((h1 (lambda (facts actions) (declare (ignore facts actions))))
        (h2 (lambda (facts actions) (declare (ignore facts actions)))))
    (register-pipeline-hook :before-execute h1)
    (register-pipeline-hook :before-execute h2)
    (is (= 2 (length (gethash :before-execute *pipeline-hooks*))))
    (is (eq h1 (first (gethash :before-execute *pipeline-hooks*))))
    (is (eq h2 (second (gethash :before-execute *pipeline-hooks*))))))

(def-test register-pipeline-hook-points-are-isolated ()
  "Hooks registered at different points do not interfere"
  (reset-project-registries)
  (let ((after (lambda (facts actions) (declare (ignore facts actions))))
        (before (lambda (facts actions) (declare (ignore facts actions)))))
    (register-pipeline-hook :after-resolve after)
    (register-pipeline-hook :before-execute before)
    (is (= 1 (length (gethash :after-resolve *pipeline-hooks*))))
    (is (= 1 (length (gethash :before-execute *pipeline-hooks*))))))

(def-test run-pipeline-invokes-deduped-hook-once ()
  "A hook registered twice runs exactly once when the pipeline runs.
Exercises the real REGISTER-PIPELINE-HOOK -> RUN-HOOKS path via
RUN-PIPELINE, which is what a plugin or home hooks/ file does."
  (reset-project-registries)
  (let ((calls 0))
    (let ((hook (lambda (facts actions)
                  (declare (ignore facts actions))
                  (incf calls)))
          (*current-home-thunk* (lambda ()
                                  (setf *current-home-name* :test)
                                  (setf *current-home-actions* nil)
                                  (list :name :test
                                        :traits nil
                                        :use-features nil
                                        :actions nil))))
      (register-pipeline-hook :after-resolve hook)
      (register-pipeline-hook :after-resolve hook)
      (run-pipeline :execute-mode :plan-only)
      (is (= 1 calls))))
  (reset-project-registries))
