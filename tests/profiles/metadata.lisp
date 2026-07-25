(in-package #:linacs-tests)

(def-suite profile-metadata
  :description "Tests for profile fact-override metadata warnings")

(def-test profile-applies-overrides ()
  "apply-profile merges overrides into *facts*"
  (reset-project-registries)
  (linacs.core:default-fact-probers)
  (linacs.core:define-profile :test-prof '((:hostname . "overridden") (:laptop-p . nil)))
  ;; probe real facts, then apply profile
  (linacs.core:probe-all-facts)
  (linacs.core:apply-profile :test-prof)
  (is (equal (linacs.core:fact :hostname) "overridden"))
  (is-false (linacs.core:fact :laptop-p))
  (reset-project-registries))

(def-test profile-signals-error-for-undefined ()
  "apply-profile signals an error for undefined profiles"
  (reset-project-registries)
  (linacs.core:default-fact-probers)
  (handler-case
      (progn
        (linacs.core:apply-profile :nonexistent)
        (fail "Should have errored"))
    (error () (pass "Correctly signalled error for undefined profile")))
  (reset-project-registries))
