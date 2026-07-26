;;;; src/catalogs.lisp
;;;;
;;;; Translation tables from a canonical package keyword to a
;;;; distribution-specific string, consulted by the :package executor when
;;;; :via :system. A keyword absent from the catalog gracefully falls back
;;;; to its own name, so a project never needs a catalog entry for every
;;;; single package on every single distro.
;;;;
;;;; Usage:
;;;;   Defining a whole catalog (only safe in a project with no other file also
;;;;   defining :packages, since this replaces it entirely):
;;;;
;;;;     (define-catalog :packages (:emacs (:fedora . "emacs") (:ubuntu . "emacs-nox")))
;;;;
;;;;   Adding to an existing catalog without touching anything else in it --
;;;;   the right choice for a feature file meant to be dropped into someone
;;;;   else's project:
;;;;
;;;;     (register-catalog :packages :git '((:arch . "git")))

(in-package :linacs.core)

(defvar *catalogs* (make-hash-table :test 'eq)
  "Maps catalog name (e.g. :packages) -> hash-table of
 canonical-keyword -> alist of (distro . string).")

(defmacro define-catalog (name &body entries)
  "Define/replace a catalog. Each entry looks like:
 (:emacs (:fedora . \"emacs\") (:ubuntu . \"emacs-nox\"))"
  `(let ((table (make-hash-table :test 'eq)))
     ,@(mapcar (lambda (entry)
                 `(setf (gethash ,(car entry) table) ',(cdr entry)))
               entries)
     (setf (gethash ,name *catalogs*) table)))

(defun register-catalog (catalog-name canonical-key distro-alist)
  "Programmatically add/merge one entry into a catalog. Used by plugins
that extend an existing catalog (e.g. linacs-catalog-nix)."
  (let ((table (or (gethash catalog-name *catalogs*)
                    (setf (gethash catalog-name *catalogs*) (make-hash-table :test 'eq)))))
    (setf (gethash canonical-key table)
          (append (gethash canonical-key table) distro-alist))
))

(defun catalog-lookup (catalog-name canonical-key distro)
  "Resolve CANONICAL-KEY through CATALOG-NAME for DISTRO. If the keyword
isn't in the catalog, gracefully fall back to the keyword's symbol name
 (or, if CANONICAL-KEY is already a string -- as with user-level `package`
declarations like (package \"vim\" ...) -- the string itself)."
  (let* ((table (gethash catalog-name *catalogs*))
         (entry (and table (gethash canonical-key table)))
         (found (and entry (cdr (assoc distro entry)))))
    (or found
        (if (stringp canonical-key) canonical-key (string-downcase (symbol-name canonical-key))))))
