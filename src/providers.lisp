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

(defun %define-provider (provider-name feature-name fn &key default description)
  (let ((alist (remove provider-name (gethash feature-name *providers*) :key #'first)))
    (push (list provider-name fn default description) alist)
    (setf (gethash feature-name *providers*) alist)))

(defmacro define-provider (provider-name &rest args)
  "(define-provider PROVIDER-NAME :for FEATURE-NAME [:default BOOL] [:description STR] FUNCTION-FORM)
Matches the spec's calling convention where the provider function is a
trailing positional argument after the :for keyword pair; an optional
:default t marks this provider as the one to use automatically when
(use-feature FEATURE-NAME) is written with no :via and more than one
provider is registered for FEATURE-NAME. An optional :description is
purely documentation, shown by `linacs list` and similar reporting."
  (let ((for-pos (position :for args)))
    (unless for-pos (error "define-provider requires :for FEATURE-NAME"))
    (let* ((feature-name (nth (1+ for-pos) args))
           (tail (nthcdr (+ for-pos 2) args))
           (fn-form (car (last tail)))
           (opts (butlast tail))
           (default (getf opts :default))
           (description (getf opts :description)))
      `(%define-provider ,provider-name ,feature-name ,fn-form
                            :default ,default :description ,description))))

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
       (error 'missing-provider :feature feature-name))
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
