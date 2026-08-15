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
Signals an ordinary error if the profile is undefined. Logs a warning
when an override key is genuinely unknown -- no registered fact source
(possible typo). Each override is recorded in *FACT-OBJECTS* with
confidence :PROFILE."
  (when profile-name
    (let ((overrides (gethash profile-name *profiles*)))
      (unless overrides
        (error "Undefined profile: ~a" profile-name))
      (dolist (pair overrides)
        (let ((key (car pair)))
          (unless (gethash key *fact-sources*)
            (linacs.log:warn* "Profile ~s overrides fact ~s, which has no registered metadata -- possible typo?"
                              profile-name key))
          (set-fact key (cdr pair) :confidence :profile :source profile-name)))))
  *facts*)
