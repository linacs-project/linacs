;;;; src/providers.lisp
;;;;
;;;; Provider registration and selection. A provider is a plain function from
;;;; facts to a list of action plists, registered against a feature name,
;;;; wrapped in a PROVIDER instance (see src/domain/provider.lisp). A feature
;;;; may have several providers; SELECT-PROVIDER-OBJECT picks one via an
;;;; explicit :via, the sole provider if only one is registered, or the one
;;;; marked :default t if several are and exactly one is marked default --
;;;; otherwise it signals MISSING-PROVIDER with real SPECIFY-PROVIDER /
;;;; SKIP-FEATURE restarts rather than guessing. SELECT-PROVIDER is a thin
;;;; wrapper returning (values function name) for historic callers; selection
;;;; results are identical to the pre-object representation.
;;;;
;;;; Usage:
;;;;     (define-provider :emacs :for :editor :default t :description "..."
;;;;       (lambda (facts) (list '(:action :package :target :emacs :via :system))))

(in-package :linacs.core)

(defvar *providers* (make-hash-table :test 'eq)
  "Maps feature name -> list of PROVIDER instances, one entry per registered
provider for that feature.")

(defun register-provider (provider-name feature-name fn &key default description)
  "Programmatically register PROVIDER-NAME as an implementation of
FEATURE-NAME. Replaces any existing provider of the same name for that
feature. Exists so the registration surface is consistent (every
extension point has a REGISTER-* function); DEFINE-PROVIDER is a thin
macro over this."
  (let ((providers (remove provider-name (gethash feature-name *providers*)
                           :key #'provider-name)))
    (push (make-provider :name provider-name :feature feature-name :function fn
                         :default-p default :description description)
          providers)
    (setf (gethash feature-name *providers*) providers)))

(defun valid-provider-fn-form-p (form)
  "T if FORM is a plausible provider function form: a (lambda ...),
(named-lambda ...), or (function ...) expression, or a symbol naming a
function (but not a keyword or the boolean literals T/NIL)."
  (cond
    ((symbolp form) (and (not (keywordp form)) (not (member form '(t nil)))))
    ((consp form) (member (car form) '(lambda named-lambda function)))
    (t nil)))

(defun parse-provider-tail (provider-name feature-name tail)
  "Front-scan TAIL -- the arguments after :for FEATURE-NAME -- for
:default/:description pairs, then require exactly one remaining form as
the provider function. Returns (values opts-plist fn-form), signaling an
error at macroexpansion time on any deviation instead of silently
misparsing: options written after the function form, a missing function
form, a stray non-option argument, an unknown option keyword, or an
option with no value are all caught here."
  (let ((opts nil))
    (loop
      (cond
        ((null tail)
         (error "define-provider ~a for ~a: requires a provider function form as the last argument"
                provider-name feature-name))
        ((eq (car tail) :default)
         (unless (cdr tail)
           (error "define-provider ~a for ~a: :default requires a value"
                  provider-name feature-name))
         (setf opts (list* :default (cadr tail) opts))
         (setf tail (cddr tail)))
        ((eq (car tail) :description)
         (unless (cdr tail)
           (error "define-provider ~a for ~a: :description requires a value"
                  provider-name feature-name))
         (setf opts (list* :description (cadr tail) opts))
         (setf tail (cddr tail)))
        ((keywordp (car tail))
         (error "define-provider ~a for ~a: unknown option ~a (expected :default or :description before the provider function form)"
                provider-name feature-name (car tail)))
        (t
         (let ((fn-form (car tail)))
           (when (cdr tail)
             (error "define-provider ~a for ~a: unexpected argument ~a after the provider function form; options must precede the function form, which must be the last argument"
                    provider-name feature-name (cadr tail)))
           (unless (valid-provider-fn-form-p fn-form)
             (error "define-provider ~a for ~a: invalid provider function form ~a; expected (lambda ...), (function ...), or a function symbol"
                    provider-name feature-name fn-form))
           (return-from parse-provider-tail (values opts fn-form))))))))

(defun parse-provider-args (provider-name args)
  "Validate and parse DEFINE-PROVIDER's argument list. Returns
(values FEATURE-NAME FN-FORM DEFAULT DESCRIPTION).

The calling convention is strict:

    (define-provider PROVIDER-NAME :for FEATURE-NAME
                     [:default BOOL] [:description STR]
                     FUNCTION-FORM)

Nothing may precede :for, :default/:description must come before the
trailing FUNCTION-FORM, and any violation signals an error at
macroexpansion time."
  (cond
    ((eq (car args) :for)
     (let ((feature-name (second args))
           (tail (cddr args)))
       (unless feature-name
         (error "define-provider ~a: :for requires a feature name" provider-name))
       (multiple-value-bind (opts fn-form)
           (parse-provider-tail provider-name feature-name tail)
         (values feature-name fn-form (getf opts :default) (getf opts :description)))))
    ((member :for args)
     (error "define-provider: no arguments may precede :for (expected (define-provider ~a :for FEATURE-NAME [:default ...] [:description ...] FUNCTION-FORM))"
            provider-name))
    (t
     (error "define-provider requires :for FEATURE-NAME"))))

(defmacro define-provider (provider-name &rest args)
  "(define-provider PROVIDER-NAME :for FEATURE-NAME [:default BOOL] [:description STR] FUNCTION-FORM)
Matches the spec's calling convention where the provider function is a
single trailing argument after the :for keyword pair and the optional
:default/:description pairs must precede it. :default t marks this
provider as the one to use automatically when (use-feature FEATURE-NAME)
is written with no :via and more than one provider is registered for
FEATURE-NAME. :description is purely documentation, shown by `linacs
list` and similar reporting. Arguments are validated at macroexpansion
time -- misordering, a missing function form, stray arguments, unknown
options, or options without values signal an error rather than being
silently misparsed (see PARSE-PROVIDER-ARGS)."
  (multiple-value-bind (feature-name fn-form default description)
      (parse-provider-args provider-name args)
    `(register-provider ,provider-name ,feature-name ,fn-form
                        :default ,default :description ,description)))

(defun find-providers-for (feature-name)
  "Every PROVIDER registered for FEATURE-NAME, as a list of PROVIDER
instances (length 0 when none)."
  (gethash feature-name *providers*))

(defun find-provider (provider-name &key for)
  "The provider function of PROVIDER-NAME registered for feature FOR, or NIL.
Returns the plain function (the historic contract, relied on by in-tree
callers and plugin tests that funcall it); the instance itself is available
via SELECT-PROVIDER-OBJECT."
  (let ((provider (find provider-name (gethash for *providers*)
                        :key #'provider-name)))
    (and provider (provider-function provider))))

(defun prompt-for-provider-name (candidates)
  (format *query-io* "Provider name (one of ~{~a~^, ~}): "
          (mapcar #'provider-name candidates))
  (force-output *query-io*)
  (intern (string-upcase (read-line *query-io*)) :keyword))

(defun select-provider-object (feature-name &optional via)
  "Select a single PROVIDER instance for FEATURE-NAME and return it. VIA, if
given, names a specific provider. If VIA is nil: with exactly one provider
registered, that one is used; with several, the one registered :default t is
used, if exactly one is so marked. Otherwise signals MISSING-PROVIDER, since
LINACS never guesses between equally-plausible providers -- but offers real
restarts to resolve it interactively (see SPECIFY-PROVIDER / SKIP-FEATURE
below) rather than only ever aborting. Returns NIL when the feature is
skipped via the SKIP-FEATURE restart."
  (let ((candidates (find-providers-for feature-name)))
    (cond
      (via
       (let ((entry (find via candidates :key #'provider-name)))
         (if entry
             entry
             (error 'missing-provider :feature feature-name
                    :message (format nil "No provider ~a registered for feature ~a." via feature-name)))))
      ((null candidates)
       (restart-case
           (error 'missing-provider :feature feature-name)
         (skip-feature ()
           :report "Continue without this feature"
           nil)))
      ((= (length candidates) 1)
       (first candidates))
      (t
       (let ((defaults (remove-if-not #'provider-default-p candidates)))
         (cond
           ((= (length defaults) 1)
            (first defaults))
           ((> (length defaults) 1)
            (error 'missing-provider :feature feature-name
                   :message (format nil "Multiple providers for ~a are marked :default t (~{~a~^, ~}); only one may be."
                                    feature-name (mapcar #'provider-name defaults))))
           (t
            (restart-case
                (error 'missing-provider :feature feature-name
                       :message (format nil "Multiple providers registered for ~a (~{~a~^, ~}); specify :via, or mark one :default t."
                                        feature-name (mapcar #'provider-name candidates)))
              (specify-provider (chosen)
                :report "Manually select a provider"
                :interactive (lambda () (list (prompt-for-provider-name candidates)))
                (let ((entry (find chosen candidates :key #'provider-name)))
                  (if entry
                      entry
                      (error 'missing-provider :feature feature-name
                             :message (format nil "~a is not among the registered providers for ~a (~{~a~^, ~})."
                                              chosen feature-name (mapcar #'provider-name candidates))))))
              (skip-feature ()
                :report "Continue without this feature"
                nil)))))))))

(defun select-provider (feature-name &optional via)
  "Select a single provider function for FEATURE-NAME, returned as the
primary value; the chosen provider's own name is returned as a second value
(existing callers that only want the function are unaffected). Thin wrapper
over SELECT-PROVIDER-OBJECT, so selection results are identical to the
historic 4-element-list representation and the :via override semantics are
unchanged. When the feature is skipped via the SKIP-FEATURE restart, both
values are NIL."
  (let ((provider (select-provider-object feature-name via)))
    (values (and provider (provider-function provider))
            (and provider (provider-name provider)))))
