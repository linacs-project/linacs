;;;; src/catalogs.lisp
;;;;
;;;; Translation tables from a canonical package keyword to a
;;;; distribution-specific string, consulted by the :package executor when
;;;; :via :system. A keyword absent from the catalog gracefully falls back
;;;; to its own name, so a project never needs a catalog entry for every
;;;; single package on every single distro.
;;;;
;;;; Usage:
;;;;   Defining many catalog entries at once.  Each entry merges into the
;;;;   existing catalog, so it is safe to use alongside other catalog files:
;;;;
;;;;     (define-catalog :packages (:emacs (:fedora . "emacs") (:ubuntu . "emacs-nox")))
;;;;
;;;;   Adding a single entry to an existing catalog programmatically:
;;;;
;;;;     (register-catalog :packages :git '((:arch . "git")))

(in-package :linacs.core)

(defvar *catalogs* (make-hash-table :test 'eq)
  "Maps catalog name (e.g. :packages) -> hash-table of
 canonical-keyword -> alist of (distro . string).")

(defmacro define-catalog (name &body entries)
  "Define entries in a catalog. Each entry looks like:
 (:emacs (:fedora . \"emacs\") (:ubuntu . \"emacs-nox\"))
 Merges into any existing catalog of the same name -- never replaces."
  `(progn
     ,@(mapcar (lambda (entry)
                 `(register-catalog ,name ,(car entry) ',(cdr entry)))
               entries)))

(defun register-catalog (catalog-name canonical-key distro-alist)
  "Programmatically add/merge one entry into a catalog. Used by plugins
that extend an existing catalog (e.g. linacs-catalog-nix).  Merges by
distro: existing entries are updated in place (no duplicates), new
entries are added.  Idempotent across repeated reloads."
  (let ((table (or (gethash catalog-name *catalogs*)
                   (setf (gethash catalog-name *catalogs*) (make-hash-table :test 'eq)))))
    (loop for (distro . name) in distro-alist
          for existing = (assoc distro (gethash canonical-key table))
          if existing do (setf (cdr existing) name)
          else do (push (cons distro name) (gethash canonical-key table)))
    (gethash canonical-key table)))

(defun catalog-lookup (catalog-name canonical-key distro &key via)
  "Resolve CANONICAL-KEY through CATALOG-NAME for DISTRO and VIA. If VIA is
non-nil and not :system, look for a `(:via-keyword . \"name\")` entry first;
for :system (or when VIA is nil/omitted), use the existing distro-keyed entry
`(:distro . \"name\")`.  In either case, if nothing is found, fall back to the
keyword's symbol name (or the string itself if CANONICAL-KEY is already a
string -- as with user-level `package` declarations like (package \"vim\" ...))."
  (let* ((table (gethash catalog-name *catalogs*))
         (entry (and table (gethash canonical-key table)))
         (found (and entry
                     (if (and via (not (eq via :system)))
                         (cdr (assoc via entry))
                         (cdr (assoc distro entry))))))
    (or found
        (if (stringp canonical-key) canonical-key (string-downcase (symbol-name canonical-key))))))
