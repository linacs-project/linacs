;;;; tests/providers/macros.lisp
;;;;
;;;; Tests for DEFINE-PROVIDER argument validation (TODO 2.6).
;;;;
;;;; The provider function used to be taken as (car (last args)) with no
;;;; validation, so a provider written with the lambda NOT last (e.g. options
;;;; after the function form) was silently misparsed and registered a keyword
;;;; or literal as the provider function. The calling convention is now strict
;;;; and enforced at macroexpansion time:
;;;;
;;;;     (define-provider PROVIDER-NAME :for FEATURE-NAME
;;;;                      [:default BOOL] [:description STR]
;;;;                      FUNCTION-FORM)
;;;;
;;;; Nothing may precede :for, options must precede the trailing function
;;;; form, and any deviation signals an error rather than silently breaking.

(in-package #:linacs-tests)

(def-suite provider-macro-validation
  :in linacs-tests
  :description "Tests for DEFINE-PROVIDER argument parsing/validation")
(in-suite provider-macro-validation)

(defun parse-provider-ok (args)
  "Parse ARGS (a DEFINE-PROVIDER argument list after the provider name) and
return the (values feature fn-form default description) as a list."
  (multiple-value-list (parse-provider-args :test-provider args)))

(defun parse-provider-errs-p (args)
  "Return T if parsing ARGS signals an error, NIL if it completes."
  (handler-case
      (progn (parse-provider-args :test-provider args) nil)
    (error () t)))

(def-test parse-provider-args-returns-feature-fn-options ()
  "The canonical form -- options before a trailing lambda -- parses to the
feature name, function form, :default, and :description."
  (let ((v (parse-provider-ok
            '(:for :f :default t :description "d" (lambda (facts) nil)))))
    (is (eq :f (nth 0 v)))
    (is (equal '(lambda (facts) nil) (nth 1 v)))
    (is (eq t (nth 2 v)))
    (is (equal "d" (nth 3 v)))))

(def-test parse-provider-args-function-only ()
  "A provider with no options and only the trailing function form parses."
  (let ((v (parse-provider-ok '(:for :f (lambda (facts) nil)))))
    (is (eq :f (nth 0 v)))
    (is (equal '(lambda (facts) nil) (nth 1 v)))
    (is (null (nth 2 v)))
    (is (null (nth 3 v)))))

(def-test parse-provider-args-accepts-function-forms ()
  "A function-symbol or (function ...) form is accepted as the provider."
  (let ((v (parse-provider-ok '(:for :f my-fn))))
    (is (eq 'my-fn (nth 1 v))))
  (let ((v (parse-provider-ok '(:for :f (function my-fn)))))
    (is (equal '(function my-fn) (nth 1 v)))))

(def-test parse-provider-args-rejects-options-after-function ()
  "Options written after the lambda -- the original silent-misparse case --
must signal an error."
  (is (parse-provider-errs-p '(:for :f (lambda (facts) nil) :default t)))
  (is (parse-provider-errs-p '(:for :f (lambda (facts) nil) :description "d"))))

(def-test parse-provider-args-rejects-missing-function ()
  "A provider with no function form must signal an error, not register a
keyword/literal as the function."
  (is (parse-provider-errs-p '(:for :f)))
  (is (parse-provider-errs-p '(:for :f :default t)))
  (is (parse-provider-errs-p '(:for :f :default t :description "d"))))

(def-test parse-provider-args-rejects-arguments-before-for ()
  "Nothing may precede :for."
  (is (parse-provider-errs-p '(:default t :for :f (lambda (facts) nil))))
  (is (parse-provider-errs-p '(:description "d" :for :f (lambda (facts) nil))))
  (is (parse-provider-errs-p '(:bogus :for :f (lambda (facts) nil)))))

(def-test parse-provider-args-rejects-missing-for ()
  "A define-provider without :for at all must signal an error."
  (is (parse-provider-errs-p nil))
  (is (parse-provider-errs-p '((lambda (facts) nil)))))

(def-test parse-provider-args-rejects-missing-feature ()
  "A :for with no feature name must signal an error."
  (is (parse-provider-errs-p '(:for))))

(def-test parse-provider-args-rejects-unknown-option ()
  "An option keyword other than :default/:description must signal an error."
  (is (parse-provider-errs-p '(:for :f :bogus 1 (lambda (facts) nil)))))

(def-test parse-provider-args-rejects-option-without-value ()
  "An option with no value must signal an error."
  (is (parse-provider-errs-p '(:for :f :default)))
  (is (parse-provider-errs-p '(:for :f :description))))

(def-test parse-provider-args-rejects-stray-argument ()
  "A stray non-option literal before the function form must signal an error."
  (is (parse-provider-errs-p '(:for :f "hello" (lambda (facts) nil))))
  (is (parse-provider-errs-p '(:for :f 42 (lambda (facts) nil)))))

(def-test parse-provider-args-rejects-non-function-form ()
  "A literal that cannot be a function (t, a number, a string, a quote) must
signal an error rather than be registered as the provider function."
  (is (parse-provider-errs-p '(:for :f t)))
  (is (parse-provider-errs-p '(:for :f nil)))
  (is (parse-provider-errs-p '(:for :f 42)))
  (is (parse-provider-errs-p '(:for :f "str")))
  (is (parse-provider-errs-p '(:for :f 'my-fn))))

(defun signals-provider-macro-error-p (form)
  "EVAL FORM (a DEFINE-PROVIDER call); T if it signals an error at
macroexpansion time, NIL if it completes."
  (handler-case (progn (eval form) nil)
    (error () t)))

(def-test define-provider-macro-registers-with-options ()
  "A well-formed DEFINE-PROVIDER registers the function, :default, and
:description through the macro end to end."
  (reset-project-registries)
  (linacs.core:define-provider :test-emacs :for :test-editor
    :default t
    :description "Test editor provider"
    (lambda (facts) (declare (ignore facts)) nil))
  (let ((entry (first (linacs.core:find-providers-for :test-editor))))
    (is (eq :test-emacs (linacs.core:provider-name entry)))
    (is (functionp (linacs.core:provider-function entry)))
    (is (eq t (linacs.core:provider-default-p entry)))
    (is (equal "Test editor provider" (linacs.core:provider-description entry))))
  (reset-project-registries))

(def-test define-provider-macro-rejects-misordered-args ()
  "The macro surfaces the same errors at macroexpansion time, so a plugin
miswriting its provider fails fast at load time instead of registering
garbage."
  (is (signals-provider-macro-error-p
       '(linacs.core:define-provider :p :for :f (lambda (facts) nil) :default t)))
  (is (signals-provider-macro-error-p
       '(linacs.core:define-provider :p :for :f)))
  (is (signals-provider-macro-error-p
       '(linacs.core:define-provider :p :default t :for :f (lambda (facts) nil))))
  (is (signals-provider-macro-error-p
       '(linacs.core:define-provider :p :for))))
