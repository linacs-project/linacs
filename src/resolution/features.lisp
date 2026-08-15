;;;; src/resolution/features.lisp
;;;;
;;;; Feature definitions, dependency-graph resolution, and configuration.
;;;; A Feature is a named capability (:editor, :docker, ...) with an optional
;;;; list of other features it :requires; RESOLVE-FEATURE-GRAPH walks that DAG
;;;; starting from a home definition's USE-FEATURE calls, dependencies first.
;;;;
;;;; Configuration is passed at the use-site via :custom and can be queried
;;;; by feature implementations using FEATURE-CUSTOM.
;;;;
;;;; Usage:
;;;;     (define-feature :editor :description "Text editor capability" :requires nil)
;;;;
;;;;     ;; In a home definition:
;;;;     (use-feature :version-control
;;;;       :custom (:username "bob" :useremail "bob@mail.com"))
;;;;
;;;;     ;; In a feature implementation:
;;;;     (feature-custom :version-control :username)  ; => "bob"

(in-package :linacs.core)

;;; ---- Feature struct and registry ----------------------------------------

(defstruct feature
  name
  description
  tags
  provides
  requires
  composed-of)

(defvar *feature-registry* (make-hash-table :test 'eq)
  "Maps feature name (keyword) -> FEATURE struct.")

(defvar *feature-customs* (make-hash-table :test 'eq)
  "Maps feature name (keyword) -> custom plist from USE-FEATURE :custom.")

;;; ---- Feature definition -------------------------------------------------

(defun register-feature (name &key description tags provides requires composed-of)
  "Programmatically register (or replace) a FEATURE struct under NAME.
All keyword arguments are the same as DEFINE-FEATURE's. Exists so the
registration surface is consistent (every extension point has a
REGISTER-* function); DEFINE-FEATURE is a thin macro over this."
  (setf (gethash name *feature-registry*)
        (make-feature :name name :description description
                      :tags tags :provides provides
                      :requires (or requires composed-of)
                      :composed-of composed-of)))

(defmacro define-feature (name &key description tags provides requires composed-of)
  "All of DESCRIPTION, TAGS, PROVIDES, REQUIRES, and COMPOSED-OF are taken
as literal data at macroexpansion time.  If REQUIRES is not given but
COMPOSED-OF is, COMPOSED-OF is also used as the :requires dependency list."
  `(register-feature ,name
                     :description ',description
                     :tags ',tags
                     :provides ',provides
                     :requires ',requires
                     :composed-of ',composed-of))

;;; ---- Feature lookup ------------------------------------------------------

(defun feature-by-name (name)
  (or (gethash name *feature-registry*)
      (error 'missing-provider :feature name
             :message (format nil "No feature named ~a is registered." name))))

;;; ---- Feature configuration -----------------------------------------------

(defun register-feature-customs (use-features)
  "Extract :custom from each USE-FEATURE entry and register it.
Called by the pipeline after running the home thunk."
  (clrhash *feature-customs*)
  (dolist (uf use-features)
    (let* ((name (getf uf :feature))
           (custom (getf uf :custom)))
      (when custom
        (setf (gethash name *feature-customs*) custom)))))

(defun feature-custom (name &optional key)
  "Retrieve custom for a feature.

Without KEY: returns the full custom plist, or NIL.
With KEY:    returns (getf custom key), or NIL if key not present."
  (let ((custom (gethash name *feature-customs*)))
    (if key
        (getf custom key)
        custom)))

(defun (setf feature-custom) (value name &optional key)
  "Set custom for a feature. If KEY is provided, sets a single key in the
existing custom plist; otherwise replaces the entire custom."
  (if key
      (setf (getf (gethash name *feature-customs*) key) value)
      (setf (gethash name *feature-customs*) value))
  value)

(defun clear-feature-customs ()
  "Clear all registered feature customs."
  (clrhash *feature-customs*))

;;; ---- Dependency resolution -----------------------------------------------

(defun resolve-feature-graph (root-names)
  "Given the list of top-level feature names requested via USE-FEATURE,
recursively resolve :requires, returning an ordered list of feature names
(dependencies before dependents), duplicates removed. Detects cycles."
  (let ((visited (make-hash-table :test 'eq))
        (visiting (make-hash-table :test 'eq))
        (order '()))
    (labels ((visit (name path)
               (cond
                 ((gethash name visited) nil)
                 ((gethash name visiting)
                  (error 'dependency-cycle :cycle (reverse (cons name path))))
                 (t
                  (setf (gethash name visiting) t)
                  (let ((f (feature-by-name name)))
                    (dolist (dep (feature-requires f))
                      (visit dep (cons name path))))
                  (remhash name visiting)
                  (setf (gethash name visited) t)
                  (push name order)))))
      (dolist (name root-names)
        (visit name nil)))
    (nreverse order)))
