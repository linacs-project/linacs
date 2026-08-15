;;;; tests/json.lisp
;;;;
;;;; Boundary tests for src/json.lisp (REFACTOR.org Action 10 -- thought 19,
;;;; Action 11 -- thought 33): the JSON encoder is a :linacs LIBRARY module,
;;;; independent of the CLI. These tests assert the encoder is usable from a
;;;; library-only image -- i.e. without loading :linacs-cli -- by checking
;;;; that ENCODE-JSON etc. are external in :linacs.core and callable with
;;;; plain library data shapes. (The full encoder behavior -- escaping,
;;;; round-trips, nesting -- is exercised in depth by tests/cli/report.lisp's
;;;; cli-report suite; this file pins the boundary, not the behavior.)

(in-package #:linacs-tests)

(def-suite json-boundary
  :in linacs-tests
  :description "Boundary tests for the :linacs JSON encoder module")
(in-suite json-boundary)

(def-test json-encoder-symbols-are-external-in-core ()
  "ENCODE-JSON and the public encoder helpers must be findable as EXTERNAL
in :linacs.core (the library), so programmatic consumers can reach them
without the CLI. The low-level JSON-ESCAPE-STRING is deliberately internal
-- an implementation helper, not part of the encoder's public surface."
  (let ((core (find-package :linacs.core)))
    (dolist (name '("ENCODE-JSON" "JSON-QUOTE-STRING" "JSON-KEY-NAME"))
      (is (eq (nth-value 1 (find-symbol name core)) :external)
          "~a must be external in :linacs.core" name))
    (is (not (eq (nth-value 1 (find-symbol "JSON-ESCAPE-STRING" core)) :external))
        "JSON-ESCAPE-STRING is an internal helper, not exported")))

(def-test json-encoder-works-without-cli ()
  "The encoder is a pure function of library data -- a library-only image
can serialize actions-shaped plists without any command-line machinery."
  (let* ((input '(:action :package :target :emacs :via :system))
         (out (linacs.core:encode-json input)))
    (is (stringp out))
    (is (search "package" out))
    (is (search "emacs" out))))
