;;;; tests/dsl/dsl-form-registration.lisp
;;;;
;;;; Tests for DEFINE-DSL-FORM / REGISTER-DSL-FORM -- the first-class way a
;;;; plugin adds a home-level DSL macro without the fragile hand-rolled
;;;; `(import '(...) :linacs.api)` pattern (TODO 2.1):
;;;;
;;;;   1. A (:use :cl :linacs.api) plugin's DEFINE-DSL-FORM is usable
;;;;      unqualified in :linacs.api (the package home.lisp and every
;;;;      discovered project file are read in), and expands to an action.
;;;;   2. DEFINE-ACTION-MACRO registers the same way, from a plugin package.
;;;;   3. Duplicate registration of the same name signals DSL-FORM-CONFLICT
;;;;      (abort-only, no silent winner).
;;;;   4. A plugin cannot shadow an existing :linacs.api form (e.g. FILE) --
;;;;      also DSL-FORM-CONFLICT.

(in-package #:linacs-tests)

(def-suite dsl-form-registration
  :in linacs-tests
  :description "Tests for DEFINE-DSL-FORM / REGISTER-DSL-FORM registration")

(in-suite dsl-form-registration)

;; A (:use :cl :linacs.api) consumer package standing in for a third-party
;; plugin -- the exact package a real linacs-* plugin source file runs in.
;; Defined here (not in tests/package.lisp) since only this suite needs it.
(defpackage #:linacs.dsl-form-test.plugin
  (:use #:common-lisp #:linacs.api))

(defmacro eval-in-plugin (form-string)
  "Read-and-eval FORM-STRING inside the simulated plugin package."
  `(let ((*package* (find-package :linacs.dsl-form-test.plugin)))
     (eval (read-from-string ,form-string))))

(defmacro eval-in-home (form-string)
  "Read-and-eval FORM-STRING in :linacs.api -- the exact package home.lisp
and every discovered project file are read in. Exercises the real
reader -> macroexpansion -> execution path."
  `(let ((*package* (find-package :linacs.api)))
     (eval (read-from-string ,form-string))))

(defun signals-dsl-form-conflict-p (form-string)
  "Evaluate FORM-STRING in the plugin package; return T if it signals
DSL-FORM-CONFLICT (the no-clobber rule), NIL if it completes instead."
  (handler-case
      (progn (eval-in-plugin form-string) nil)
    (dsl-form-conflict () t)))

(def-test dsl-form-reachable-unqualified-from-linacs-api ()
  "A plugin's DEFINE-DSL-FORM is findable and usable in :linacs.api, and
pushes the expected action."
  (reset-project-registries)
  (eval-in-plugin
   "(define-dsl-form test-form (cfg-file cfg-group cfg-key cfg-value &rest opts)
      (declare (ignore cfg-value opts))
      (let ((action (list :action :test-form
                          :target (format nil \"~a [~a] ~a\" cfg-file cfg-group cfg-key)
                          :priority :user :source \"plugin:test-form\")))
        `(progn (push ',action *current-home-actions*) ',action)))")
  (let ((linacs.core:*current-home-actions* nil))
    (eval-in-home "(test-form \"kdeglobals\" \"KDE\" \"SingleClick\" \"true\")")
    (let ((a (first linacs.core:*current-home-actions*)))
      (is (eq :test-form (getf a :action)))
      (is (equal "kdeglobals [KDE] SingleClick" (getf a :target)))
      (is (eq :user (getf a :priority)))))
  (reset-project-registries))

(def-test define-action-macro-registers-into-linacs-api ()
  "DEFINE-ACTION-MACRO from a plugin package registers the same way -- the
unified mechanism, so simple (target &rest opts) action macros need no manual
import either."
  (reset-project-registries)
  (eval-in-plugin
   "(define-action-macro test-amin-form :test-amin \"plugin:test-amin\")")
  (multiple-value-bind (sym status)
      (find-symbol "TEST-AMIN-FORM" (find-package :linacs.api))
    (is (eq status :internal))
    (is (macro-function sym))
    (let ((linacs.core:*current-home-actions* nil))
      (eval-in-home "(test-amin-form \"some-target\")")
      (let ((a (first linacs.core:*current-home-actions*)))
        (is (eq :test-amin (getf a :action)))
        (is (equal "some-target" (getf a :target)))
        (is (eq :user (getf a :priority))))))
  (reset-project-registries))

(def-test duplicate-dsl-form-signals-conflict ()
  "Registering the same DSL form name twice (from the same or another plugin)
signals DSL-FORM-CONFLICT -- no silent shadowing."
  (reset-project-registries)
  (eval-in-plugin
   "(define-dsl-form dup-form (a &rest opts) (declare (ignore a opts)) nil)")
  (is (signals-dsl-form-conflict-p
       "(define-dsl-form dup-form (a &rest opts) (declare (ignore a opts)) nil)")
      "re-registering an existing form name must signal DSL-FORM-CONFLICT")
  (reset-project-registries))

(def-test cannot-shadow-builtin-dsl-form ()
  "A plugin may not redefine an existing :linacs.api form like FILE."
  (reset-project-registries)
  (is (signals-dsl-form-conflict-p
       "(define-dsl-form file (x &rest opts) (declare (ignore x opts)) nil)")
      "redefining a built-in home-level form must signal DSL-FORM-CONFLICT")
  (reset-project-registries))