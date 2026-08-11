;;;; src/providers.lisp
;;;;
;;;; Provider registration and selection. A Provider is a plain function from
;;;; facts to a list of action plists, registered against a feature name. A
;;;; feature may have several providers; SELECT-PROVIDER picks one via an
;;;; explicit :via, the sole provider if only one is registered, or the one
;;;; marked :default t if several are and exactly one is marked default --
;;;; otherwise it signals MISSING-PROVIDER with real SPECIFY-PROVIDER /
;;;; SKIP-FEATURE restarts rather than guessing.
;;;;
;;;; Usage:
;;;;     (define-provider :emacs :for :editor :default t :description "..."
;;;;       (lambda (facts) (list '(:action :package :target :emacs :via :system))))

(in-package :linacs.core)

(defvar *providers* (make-hash-table :test 'eq)
  "Maps feature name -> list of (provider-name provider-function default-p
description), one entry per registered provider for that feature.")

(defun register-provider (provider-name feature-name fn &key default description)
  "Programmatically register PROVIDER-NAME as an implementation of
FEATURE-NAME. Replaces any existing provider of the same name for that
feature. Exists so the registration surface is consistent (every
extension point has a REGISTER-* function); DEFINE-PROVIDER is a thin
macro over this."
  (let ((alist (remove provider-name (gethash feature-name *providers*) :key #'first)))
    (push (list provider-name fn default description) alist)
    (setf (gethash feature-name *providers*) alist)))

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
  (gethash feature-name *providers*))

(defun find-provider (provider-name &key for)
  (second (assoc provider-name (gethash for *providers*))))

(defun prompt-for-provider-name (candidates)
  (format *query-io* "Provider name (one of ~{~a~^, ~}): " (mapcar #'first candidates))
  (force-output *query-io*)
  (intern (string-upcase (read-line *query-io*)) :keyword))

(defun select-provider (feature-name &optional via)
  "Select a single provider function for FEATURE-NAME, returned as the
primary value; the chosen provider's own name is returned as a second
value (existing callers that only want the function are unaffected).
VIA, if given, names a specific provider. If VIA is nil: with exactly one
provider registered, that one is used; with several, the one registered
:default t is used, if exactly one is so marked. Otherwise signals
MISSING-PROVIDER, since LINACS never guesses between equally-plausible
providers -- but offers real restarts to resolve it interactively (see
SPECIFY-PROVIDER / SKIP-FEATURE below) rather than only ever aborting."
  (let ((candidates (find-providers-for feature-name)))
    (cond
      (via
       (let ((entry (assoc via candidates)))
         (if entry
             (values (second entry) (first entry))
             (error 'missing-provider :feature feature-name
                    :message (format nil "No provider ~a registered for feature ~a." via feature-name)))))
      ((null candidates)
       (restart-case
           (error 'missing-provider :feature feature-name)
         (skip-feature ()
           :report "Continue without this feature"
           (values (lambda (facts) (declare (ignore facts)) nil) nil))))
      ((= (length candidates) 1)
       (values (second (first candidates)) (first (first candidates))))
      (t
       (let ((defaults (remove-if-not #'third candidates)))
         (cond
           ((= (length defaults) 1)
            (values (second (first defaults)) (first (first defaults))))
           ((> (length defaults) 1)
            (error 'missing-provider :feature feature-name
                   :message (format nil "Multiple providers for ~a are marked :default t (~{~a~^, ~}); only one may be."
                                     feature-name (mapcar #'first defaults))))
           (t
            (restart-case
                (error 'missing-provider :feature feature-name
                       :message (format nil "Multiple providers registered for ~a (~{~a~^, ~}); specify :via, or mark one :default t."
                                         feature-name (mapcar #'first candidates)))
              (specify-provider (chosen)
                :report "Manually select a provider"
                :interactive (lambda () (list (prompt-for-provider-name candidates)))
                (let ((entry (assoc chosen candidates)))
                  (if entry
                      (values (second entry) (first entry))
                      (error 'missing-provider :feature feature-name
                             :message (format nil "~a is not among the registered providers for ~a (~{~a~^, ~})."
                                               chosen feature-name (mapcar #'first candidates))))))
              (skip-feature ()
                :report "Continue without this feature"
                (values (lambda (facts) (declare (ignore facts)) nil) nil))))))))))
