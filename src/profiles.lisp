;;;; src/profiles.lisp
;;;;
;;;; Named, independent sets of fact overrides, selected with `linacs apply
;;;; --profile NAME`. A profile never extends another profile -- each one is
;;;; a complete override set merged on top of already-probed facts.
;;;;
;;;; Usage:
;;;;     (define-profile :laptop '((:hostname . "thinkpad") (:gpu . :nvidia) (:laptop-p . t)))

(in-package :linacs.core)

(defvar *profiles* (make-hash-table :test 'eq)
  "Maps profile name (keyword) -> alist of (fact-key . value) overrides.")

(defmacro define-profile (name overrides-form)
  "Register a profile. OVERRIDES-FORM should evaluate to an alist of
 (fact-keyword . value)."
  `(setf (gethash ,name *profiles*) ,overrides-form))

(defun apply-profile (profile-name)
  "Merge PROFILE-NAME's overrides on top of the already-probed *FACTS*.
Signals an ordinary error if the profile is undefined."
  (when profile-name
    (let ((overrides (gethash profile-name *profiles*)))
      (unless overrides
        (error "Undefined profile: ~a" profile-name))
      (dolist (pair overrides)
        (setf (getf *facts* (car pair)) (cdr pair)))))
  *facts*)
