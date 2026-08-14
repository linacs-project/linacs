;;;; src/backends/filesystem/memory.lisp
;;;;
;;;; The hermetic in-memory filesystem: a node tree keyed by canonicalized
;;;; path strings, with zero host interaction. This is the unit-test seam for
;;;; the file-heavy executors -- stow, copy-file, ensure-dir, symlink, secret,
;;;; and the config executors run against it with no host writes.
;;;;
;;;; Construction and fixture seeding use the same FS-* generics the
;;;; executors use, so a test can build a package tree and a target root
;;;; purely in memory.

(in-package :linacs.core)

(defun memory-node (fs path)
  (gethash (fs-canonical-path path) (memory-filesystem-nodes fs)))

(defun (setf memory-node) (node fs path)
  (setf (gethash (fs-canonical-path path) (memory-filesystem-nodes fs)) node))

(defun memory-resolve (fs path &optional (hops 0))
  "Follow symlinks in EVERY path component of PATH (OS-style resolution),
  returning the canonical path string of the final non-symlink node, or
  NIL when some component is missing, the chain is broken, or the hop
  count exceeds 32. This is what lets a folded directory symlink (e.g. a
  whole ~/.config folded to a package source) be walked through."
  (when (< hops 32)
    (let* ((canon (fs-canonical-path path))
           (components (remove "" (uiop:split-string canon :separator '(#\/))
                               :test #'string=)))
      (labels ((resolve-prefix (prefix rest)
                 (if (null rest)
                     prefix
                     (let* ((child (car rest))
                            (full (cond
                                    ((string= prefix "/") (format nil "/~a" child))
                                    ((string= prefix "") child)
                                    (t (format nil "~a/~a" prefix child))))
                            (node (memory-node fs full)))
                       (cond
                         ((and node (eq (getf node :type) :symlink))
                          (let ((target (memory-resolve fs (getf node :target) (1+ hops))))
                            (and target (resolve-prefix target (cdr rest)))))
                         (node (resolve-prefix full (cdr rest)))
                         (t nil))))))
        (resolve-prefix (if (and (plusp (length canon)) (char= (char canon 0) #\/))
                            "/" "")
                        components)))))

(defun memory-make-parents (fs path)
  "Create every ancestor directory of PATH (mkdir -p semantics)."
  (let ((parent (fs-parent-path path)))
    (when parent
      (memory-make-parents fs parent)
      (unless (memory-node fs parent)
        (setf (memory-node fs parent) '(:type :directory :mode 755))))))

(defmethod fs-exists-p ((fs memory-filesystem) path)
  (not (null (memory-node fs path))))

(defmethod fs-symlink-p ((fs memory-filesystem) path)
  (let ((node (memory-node fs path)))
    (and node (eq (getf node :type) :symlink))))

(defmethod fs-directory-p ((fs memory-filesystem) path)
  (let ((resolved (memory-resolve fs path)))
    (and resolved (eq (getf (memory-node fs resolved) :type) :directory))))

(defmethod fs-file-p ((fs memory-filesystem) path)
  (let ((resolved (memory-resolve fs path)))
    (and resolved (eq (getf (memory-node fs resolved) :type) :file))))

(defmethod fs-read-link ((fs memory-filesystem) path)
  (let ((node (memory-node fs path)))
    (and node (eq (getf node :type) :symlink) (getf node :target))))

(defmethod fs-directory-entries ((fs memory-filesystem) path)
  (let ((dir (or (memory-resolve fs path)
                 (fs-canonical-path path))))
    (when (fs-directory-p fs dir)
      (let ((prefix (format nil "~a/" dir)))
        (sort (loop for key being the hash-keys of (memory-filesystem-nodes fs)
                    when (and (>= (length key) (length prefix))
                              (string= prefix key :end1 (length prefix)
                                                    :end2 (length prefix))
                              (not (find #\/ key
                                         :start (length prefix)))
                              )
                    collect (subseq key (length prefix)))
              #'string<)))))

(defmethod fs-read-file ((fs memory-filesystem) path)
  (let ((resolved (memory-resolve fs path)))
    (when (and resolved (eq (getf (memory-node fs resolved) :type) :file))
      (getf (memory-node fs resolved) :content))))

(defmethod fs-truename ((fs memory-filesystem) path)
  (or (memory-resolve fs path) (fs-canonical-path path)))

(defmethod fs-file-mode ((fs memory-filesystem) path)
  (let ((resolved (memory-resolve fs path)))
    (and resolved (getf (memory-node fs resolved) :mode))))

(defmethod fs-make-directory ((fs memory-filesystem) path)
  (memory-make-parents fs path)
  (unless (memory-node fs path)
    (setf (memory-node fs path) '(:type :directory :mode 755)))
  path)

(defmethod fs-write-file ((fs memory-filesystem) path content)
  (memory-make-parents fs path)
  (let ((existing (memory-node fs path)))
    (setf (memory-node fs path)
          (list :type :file
                :content (if (stringp content) content (prin1-to-string content))
                :mode (getf existing :mode 644))))
  path)

(defmethod fs-symlink ((fs memory-filesystem) source target)
  (memory-make-parents fs target)
  (setf (memory-node fs target)
        (list :type :symlink :target (fs-path-string source) :mode 777))
  target)

(defmethod fs-delete ((fs memory-filesystem) path)
  (let ((node (memory-node fs path)))
    (cond
      ((null node) t)
      ((eq (getf node :type) :directory)
       (and (null (fs-directory-entries fs path)) (remhash (fs-canonical-path path)
                                                          (memory-filesystem-nodes fs))))
      (t (remhash (fs-canonical-path path) (memory-filesystem-nodes fs)) t))))

(defmethod fs-rmdir ((fs memory-filesystem) path)
  (let ((node (memory-node fs path)))
    (and node
         (eq (getf node :type) :directory)
         (null (fs-directory-entries fs path))
         (progn (remhash (fs-canonical-path path) (memory-filesystem-nodes fs)) t))))

(defmethod fs-delete-directory-tree ((fs memory-filesystem) path)
  (let* ((dir (fs-canonical-path path))
         (prefix (format nil "~a/" dir)))
    (maphash (lambda (key value)
               (declare (ignore value))
(when (or (string= key dir)
                         (and (>= (length key) (length prefix))
                              (string= prefix key :end1 (length prefix)
                                                    :end2 (length prefix))))
                 (remhash key (memory-filesystem-nodes fs))))
             (memory-filesystem-nodes fs)))
  t)

(defmethod fs-set-mode ((fs memory-filesystem) path mode)
  (let ((node (memory-node fs path)))
    (when (and node mode)
      (setf (getf node :mode) mode)))
  path)

(defmethod fs-set-owner ((fs memory-filesystem) path owner group)
  (let ((node (memory-node fs path)))
    (when node
      (when owner (setf (getf node :owner) owner))
      (when group (setf (getf node :group) group))))
  path)