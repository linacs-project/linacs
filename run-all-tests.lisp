;;; run-all-tests.lisp -- thin dev/CI convenience wrapper over the canonical
;;; linacs-tests.asd system. The asd is the single source of truth for the
;;; test file list; this script only locates and loads it, then runs the
;;; whole suite. Equivalent to `make test` from tests/, but usable directly
;;; from the linacs project root without make.
;;;
;;; Run from the linacs project root: sbcl --load run-all-tests.lisp
;;;
;;; Exits 0 on success, 1 if any check fails (CI-friendly).

(require :asdf)
(push (truename ".") asdf:*central-registry*)
(push (truename "tests/") asdf:*central-registry*)
(asdf:load-system :linacs-tests)

(format t "~%Running LINACS test suite...~%")
(if (fiveam:run-all-tests :summary nil)
    (progn
      (format t "~%Status: PASSED~%")
      (uiop:quit 0))
    (progn
      (format t "~%Status: FAILED~%")
      (uiop:quit 1)))
