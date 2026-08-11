(defpackage #:linacs-tests
  (:use #:common-lisp
        #:it.bese.fiveam)
  (:shadow #:directory)
  (:import-from #:linacs.core
   #:file
   #:run-pipeline
   #:register-pipeline-hook
   #:dsl-form-conflict
   #:parse-provider-args
   #:*pipeline-hooks*
   #:*current-home-thunk*
   #:*current-home-name*
   #:*current-home-traits*
   #:*current-home-actions*)
  (:export
   #:def-suite
   #:in-suite
   #:def-test
   #:is
   #:pass
   #:fail
   #:skip
   #:run
   #:run!
   #:run-all-tests))

;; A (:use :cl :linacs.api) consumer package -- the exact usage pattern of
;; a third-party plugin. Exercised by tests/api/surface.lisp. Defined here
;; (rather than in the test file) so the whole run has a stable package.
(defpackage #:linacs.api-consumer-test
  (:use #:common-lisp #:linacs.api)
  (:export #:api-exports-resolve #:consumer-package-finds-everything))