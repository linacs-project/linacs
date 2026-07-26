(in-package #:linacs-tests)

(def-suite fact-schema
  :in linacs-tests
  :description "Tests for fact metadata schema and type validation")
(in-suite fact-schema)

(def-test register-prober-with-metadata ()
  "Registering a fact prober with :type and :doc populates *fact-metadata*"
  (reset-project-registries)
  (linacs.core:register-fact-prober :test-key (lambda () :foo) "test"
    :type '(member :foo :bar)
    :doc "Test fact")
  (is (equal (getf (gethash :test-key linacs.core:*fact-metadata*) :type)
             '(member :foo :bar)))
  (is (equal (getf (gethash :test-key linacs.core:*fact-metadata*) :doc)
             "Test fact"))
  (reset-project-registries))

(def-test register-prober-without-metadata ()
  "Registering a fact prober without :type/:doc does NOT populate *fact-metadata*"
  (reset-project-registries)
  (linacs.core:register-fact-prober :bare-key (lambda () t) "test")
  (is-false (gethash :bare-key linacs.core:*fact-metadata*))
  (reset-project-registries))

(def-test probe-all-facts-populates-facts ()
  "probe-all-facts runs registered probers and populates *facts*"
  (reset-project-registries)
  (linacs.core:register-fact-prober :test-a (lambda () :avalue) "test" :type 'keyword)
  (linacs.core:register-fact-prober :test-b (lambda () 42) "test" :type 'integer)
  (linacs.core:probe-all-facts)
  (is (eq (linacs.core:fact :test-a) :avalue))
  (is (= (linacs.core:fact :test-b) 42))
  (is (linacs.core:fact-known-p :test-a))
  (is (linacs.core:fact-known-p :test-b))
  (is-false (linacs.core:fact-known-p :not-registered))
  (reset-project-registries))

(def-test metadata-from-default-probers ()
  "All built-in fact probers have registered type metadata"
  (reset-project-registries)
  (linacs.core:default-fact-probers)
  (let ((count 0))
    (maphash (lambda (key meta)
               (declare (ignore key))
               (incf count)
               (is-true (getf meta :type) "Each fact has :type")
               (is-true (getf meta :doc) "Each fact has :doc"))
             linacs.core:*fact-metadata*)
    (is (= count (hash-table-count linacs.core:*fact-probers*))
        "Every prober has metadata"))
  (reset-project-registries))
