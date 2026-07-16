;; Comprehensive test runner with detailed summary
(setf asdf:*central-registry* nil)
(push (make-pathname :directory '(:absolute "home" "echjansen" "Projects" "codeberg" "linacs-project" "linacs"))
      asdf:*central-registry*)

(format t "~%======================================~%")
(format t "COMPREHENSIVE TEST SUITE~%")
(format t "======================================~%~%")

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

;; Then load all test modules
(format t "~%Loading test modules...~%")

(format t "Loading DSL tests...~%")
(load "tests/dsl/macros.lisp")
(load "tests/dsl/validation.lisp")
(format t "DSL tests loaded~%")

(format t "Loading features tests...~%")
(load "tests/features/graph.lisp")
(format t "Features tests loaded~%")

(format t "Loading pipeline tests...~%")
(load "tests/pipeline/execution.lisp")
(format t "Pipeline tests loaded~%")

(format t "Loading executor tests...~%")
(load "tests/executors/copy-file.lisp")
(load "tests/executors/ensure-dir.lisp")
(load "tests/executors/symlink.lisp")
(load "tests/executors/service.lisp")
(load "tests/executors/package-action.lisp")
(load "tests/executors/config-lines.lisp")
(format t "Executor tests loaded~%")

(format t "Loading action tests...~%")
(load "tests/actions/dedup.lisp")
(load "tests/actions/ordering.lisp")
(format t "Action tests loaded~%")

(format t "~%Loading main test file...~%")
(load "tests/actions/identity.lisp")
(format t "Main test file loaded~%")

(format t "~%Running all tests...~%")

;; Run all tests
(let ((results (fiveam:run-all-tests :summary nil)))
  (format t "~%======================================~%")
  (format t "TEST RESULTS SUMMARY~%")
  (format t "======================================~%~%")

  (if results
      (progn
        (format t "✗ Tests failed: ~a~%~%" results)
        (format t "Status: FAILED~%~%"))
      (progn
        (format t "✓ All tests passed~%~%")
        (format t "Status: PASSED~%~%")))

  (format t "Test run complete!~%")
  (format t "======================================~%~%"))