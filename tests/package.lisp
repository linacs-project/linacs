(defpackage #:linacs-tests
  (:use #:common-lisp
        #:it.bese.fiveam)
  (:shadow #:directory)
  (:import-from #:linacs.core
   #:file
   #:run-pipeline
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