;;;; src/backends/filesystem/filesystem.lisp
;;;;
;;;; The filesystem backend protocol (REFACTOR.org Thought 11 / Action 8).
;;;; All filesystem access performed by the file-related action executors
;;;; goes through these generics, so the substrate can be swapped between a
;;;; REAL-FILESYSTEM (the host OS) and a MEMORY-FILESYSTEM (hermetic unit
;;;; tests that never touch the host) or wrapped by a RECORDING-FILESYSTEM
;;;; (audit the operations a run performed).
;;;;
;;;; Three implementations live alongside this protocol file:
;;;;   real.lisp       -- the host filesystem, preserving the historic
;;;;                      escalate-on-demand sudo policy from helpers.lisp
;;;;   memory.lisp     -- a self-contained node tree keyed by canonicalized
;;;;                      path strings; zero host interaction
;;;;   recording.lisp  -- a transparent wrapper that logs every call
;;;;
;;;; Executors obtain the active filesystem via CONTEXT-FILESYSTEM (see
;;;; domain/execution/context.lisp), which default to a lazily-created
;;;; REAL-FILESYSTEM when no execution context supplies one.

(in-package :linacs.core)

(defclass filesystem ()
  ()
  (:documentation "Abstract base class for a filesystem backend. The
  specific access protocol is the FS-* generic functions in this file."))

(defclass real-filesystem (filesystem)
  ()
  (:documentation "The host filesystem. Methods delegate to the helpers in
  action-types/helpers.lisp, preserving the escalate-on-demand sudo policy
  (never require the whole process to run as root)."))

(defclass memory-filesystem (filesystem)
  ((nodes :initarg :nodes :initform (make-hash-table :test 'equal)
          :reader memory-filesystem-nodes
          :documentation "Hash table mapping canonical path string -> node
          plist (:type :directory|:file|:symlink :mode ... :content ... :target ...)."))
  (:documentation "A hermetic in-memory filesystem: a node tree keyed by
  canonicalized path strings. No host interaction whatsoever -- the unit-test
  seam for the file-heavy executors. Construction and seeding use the same
  FS-* generics the executors use."))

(defclass recording-filesystem (filesystem)
  ((wrapped :initarg :wrapped :initform (make-instance 'real-filesystem)
            :reader recording-filesystem-wrapped
            :documentation "The filesystem being observed.")
   (log :initarg :log :initform nil
        :accessor recording-filesystem-log
        :documentation "List of (operation . arguments) pairs recorded in
        order, most recent first."))
  (:documentation "A transparent wrapper around another filesystem that
  records every operation, for auditing what a run actually did."))

(defun make-real-filesystem ()
  (make-instance 'real-filesystem))

(defun make-memory-filesystem ()
  (make-instance 'memory-filesystem))

(defun make-recording-filesystem (&optional (wrapped (make-real-filesystem)))
  (make-instance 'recording-filesystem :wrapped wrapped))

(defun fs-path-string (path)
  "Coerce PATH (a string, pathname, or other pathname designator) to a string."
  (if (stringp path) path (namestring path)))

(defun fs-canonical-path (path)
  "Normalize PATH into a canonical slash-separated string: collapse
  duplicate slashes, drop `.` segments, resolve `..` (never escaping above
  the root), preserve a leading `/` for absolute paths, and never end in
  `/` except for the root itself. Used by the in-memory filesystem as its
  node key and by the real backend's best-effort fallbacks."
  (let* ((str (fs-path-string path))
         (stack '()))
    (dolist (seg (uiop:split-string str :separator '(#\/)))
      (cond
        ((member seg '("" ".") :test #'string=))
        ((string= seg "..")
         (when stack (pop stack)))
        (t (push seg stack))))
    (let* ((absolute (and (plusp (length str)) (char= (char str 0) #\/)))
           (joined (format nil "~{~a~^/~}" (nreverse stack))))
      (cond
        (absolute (format nil "/~a" joined))
        ((zerop (length joined)) ".")
        (t joined)))))

(defun fs-parent-path (path)
  "The canonical path of PATH's parent directory, or NIL when PATH has no
  parent (the root, or a bare relative name)."
  (let ((c (fs-canonical-path path)))
    (cond
      ((member c '("/" "") :test #'string=) nil)
      (t (let ((pos (position #\/ c :from-end t)))
           (if pos (fs-canonical-path (subseq c 0 pos)) nil))))))

;;;; Protocol
;;;;
;;;; Naming: FS- prefix throughout, deliberately avoiding the bare names the
;;;; REFACTOR.org thought-11 sketch suggested (exists-p, symlink, delete, ...)
;;;; because several of those collide with CL symbols (cl:delete, cl:format
;;;; control) and would force shadowing imports into :linacs.core.

;;; Predicates
(defgeneric fs-exists-p (fs path)
  (:documentation "T if PATH exists as anything -- file, directory, or
  symlink (including a broken one)."))
(defgeneric fs-directory-p (fs path)
  (:documentation "T if PATH is a directory (following symlinks)."))
(defgeneric fs-file-p (fs path)
  (:documentation "T if PATH is a regular, non-directory file (following
  symlinks)."))
(defgeneric fs-symlink-p (fs path)
  (:documentation "T if PATH itself is a symlink (not followed)."))

;;; Reads
(defgeneric fs-read-link (fs path)
  (:documentation "The symlink target of PATH as a string, or NIL when PATH
  is not a symlink."))
(defgeneric fs-directory-entries (fs path)
  (:documentation "The entry names directly inside the directory PATH,
  sorted, or NIL when PATH is not a directory or is empty."))
(defgeneric fs-read-file (fs path)
  (:documentation "The contents of PATH as a string, or NIL when PATH cannot
  be read (missing file, dangling symlink, directory, or unreadable)."))
(defgeneric fs-truename (fs path)
  (:documentation "The canonical, absolute path string of PATH (following
  symlinks), falling back to a normalized form of PATH itself when it does
  not resolve."))
(defgeneric fs-file-mode (fs path)
  (:documentation "The POSIX permission bits of PATH as an integer, or NIL
  when unavailable."))

;;; Writes
(defgeneric fs-make-directory (fs path)
  (:documentation "Ensure PATH and all its ancestors exist as directories
  (mkdir -p semantics)."))
(defgeneric fs-write-file (fs path content)
  (:documentation "Write CONTENT to PATH, superseding any existing entry."))
(defgeneric fs-symlink (fs source target)
  (:documentation "Create or overwrite the symlink at TARGET pointing at
  SOURCE (ln -sf semantics)."))
(defgeneric fs-delete (fs path)
  (:documentation "Remove PATH if it is a file or symlink, or an EMPTY
  directory. Returns T when removed (or already absent), NIL when it
  remains (a non-empty directory)."))
(defgeneric fs-rmdir (fs path)
  (:documentation "Remove the directory PATH only if it is empty. Returns T
  when removed, NIL otherwise (non-empty or missing)."))
(defgeneric fs-delete-directory-tree (fs path)
  (:documentation "Remove the directory PATH and everything under it."))
(defgeneric fs-set-mode (fs path mode)
  (:documentation "Set the POSIX permission bits of PATH to MODE (an
  integer, or NIL for no-op)."))
(defgeneric fs-set-owner (fs path owner group)
  (:documentation "Set the owner/group of PATH (each may be NIL for no
  change)."))