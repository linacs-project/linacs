(in-package #:linacs-tests)

(def-suite profile-metadata
  :in linacs-tests
  :description "Tests for profile fact-override metadata warnings")
(in-suite profile-metadata)

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

(def-test declare-fact-registers-metadata-only ()
  "declare-fact populates *fact-metadata* but not *fact-probers*"
  (reset-project-registries)
  (linacs.core:declare-fact :profile-only-key
    :type '(member t nil) :doc "Set only by a profile")
  (is (equal (getf (gethash :profile-only-key linacs.core:*fact-metadata*) :type)
             '(member t nil)))
  (is (equal (getf (gethash :profile-only-key linacs.core:*fact-metadata*) :doc)
             "Set only by a profile"))
  (is-false (gethash :profile-only-key linacs.core:*fact-probers*))
  (reset-project-registries))

(def-test profile-override-declared-fact-does-not-warn ()
  "apply-profile does not warn on a profile-only fact documented via declare-fact"
  (reset-project-registries)
  (linacs.core:default-fact-probers)
  (linacs.core:declare-fact :profile-only-key
    :type '(member t nil) :doc "Set only by a profile")
  (linacs.core:define-profile :test-prof '((:profile-only-key . t)))
  (linacs.core:probe-all-facts)
  (let ((*standard-output* (make-string-output-stream)))
    (linacs.core:apply-profile :test-prof)
    (is (equal (get-output-stream-string *standard-output*) "")
        "no warning output for a declared fact"))
  (is (eq (linacs.core:fact :profile-only-key) t))
  (reset-project-registries))

(def-test profile-override-unknown-key-still-warns ()
  "apply-profile still warns on a genuinely unknown fact key"
  (reset-project-registries)
  (linacs.core:default-fact-probers)
  (linacs.core:define-profile :test-prof '((:not-a-real-fact . 42)))
  (linacs.core:probe-all-facts)
  (let ((*standard-output* (make-string-output-stream)))
    (linacs.core:apply-profile :test-prof)
    (let ((out (get-output-stream-string *standard-output*)))
      (is-true (search "possible typo" out)
               "unknown key produces a warning")))
  (reset-project-registries))
