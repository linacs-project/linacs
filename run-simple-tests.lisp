;; Simple test runner with detailed results
(setf asdf:*central-registry* nil)
(push (make-pathname :directory '(:absolute "home" "echjansen" "Projects" "codeberg" "linacs-project" "linacs"))
      asdf:*central-registry*)

(format t "Loading dependencies...~%")
(ql:quickload :asdf)
(ql:quickload :uiop)
(ql:quickload :fiveam)
(format t "Dependencies loaded~%")

(format t "Loading linacs...~%")
(asdf:load-system :linacs)
(format t "linacs loaded~%")

;; Load test package FIRST before anything else
(format t "Loading test package...~%")
(load "tests/package.lisp")
(format t "Package loaded~%")

;; Then load helpers
(format t "Loading helpers...~%")
(load "tests/helpers.lisp")
(format t "Helpers loaded~%")

;; Then load tests
(format t "Loading action identity tests...~%")
(load "tests/actions/identity.lisp")
(format t "Test file loaded~%")

(format t "Running action-identity tests...~%")

;; Run tests and get results
(let ((results (fiveam:run-all-tests :summary nil)))
  (format t "~%--- TEST RESULTS ---~%")
  (format t "All tests passed: ~a~%" results)
  (format t "Test run complete!~%"))