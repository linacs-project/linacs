(defpackage #:linacs-tests
  (:use #:common-lisp
        #:it.bese.fiveam)
  (:shadow #:directory)
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