;;;; src/backends/filesystem/real.lisp
;;;;
;;;; The host-filesystem implementation of the FS-* protocol. Methods
;;;; delegate to the escalate-on-demand helpers in action-types/helpers.lisp
;;;; (READ-FILE-STRING / WRITE-FILE-WITH-ESCALATION /
;;;; ENSURE-DIRECTORIES-WITH-ESCALATION / SET-FILE-MODE / SET-FILE-OWNER /
;;;; RUN-PRIVILEGED), preserving the historic policy exactly: never require
;;;; the whole process to run as root -- every operation tries as the
;;;; invoking user first and escalates via sudo, for just that one command,
;;;; only when a plain attempt fails.
;;;;
;;;; Loaded after action-types/helpers.lisp (see linacs.asd), so it can
;;;; reference those helpers by name.

(in-package :linacs.core)

(defun fs-apply-ownership (fs path action)
  "Apply ACTION's :mode / :owner / :group to PATH, honoring the per-spec
  defaults: :owner defaults to the calling (non-root) user and :group to the
  calling user's primary group, exactly as HELPERS:APPLY-FILE-OWNERSHIP did
  -- so the real backend still chowns every written file to the invoking
  user, even when the action specifies no owner."
  (fs-set-mode fs path (getf action :mode))
  (fs-set-owner fs path (resolve-owner action) (resolve-group action)))

(defmethod fs-exists-p ((fs real-filesystem) path)
  "Exists as anything -- including a broken symlink, which PROBE-FILE cannot
  see."
  (let ((p (fs-path-string path)))
    (zerop (nth-value 2
            (uiop:run-program (list "test" "-e" p "-o" "-L" p)
                              :ignore-error-status t)))))

(defmethod fs-directory-p ((fs real-filesystem) path)
  (uiop:directory-exists-p path))

(defmethod fs-file-p ((fs real-filesystem) path)
  (and (probe-file path) (not (uiop:directory-exists-p path))))

(defmethod fs-symlink-p ((fs real-filesystem) path)
  (zerop (nth-value 2
          (uiop:run-program (list "test" "-L" (fs-path-string path))
                            :ignore-error-status t))))

(defmethod fs-read-link ((fs real-filesystem) path)
  (ignore-errors
   (let ((out (uiop:run-program (list "readlink" (fs-path-string path))
                                :output '(:string :stripped t))))
     (and (stringp out) (plusp (length out)) out))))

(defmethod fs-directory-entries ((fs real-filesystem) path)
  (when (fs-directory-p fs path)
    (remove "" (uiop:split-string
                (uiop:run-program (list "ls" "-A"
                                        (namestring
                                         (uiop:ensure-directory-pathname path)))
                                  :output '(:string :stripped t))
                :separator '(#\Newline))
             :test #'string=)))

(defmethod fs-read-file ((fs real-filesystem) path)
  "NIL when the file cannot be read -- missing, dangling symlink (SBCL's
  PROBE-FILE returns the path for one but opening it fails), or unreadable."
  (handler-case
      (when (probe-file path)
        (uiop:read-file-string path))
    (error () nil)))

(defmethod fs-truename ((fs real-filesystem) path)
  (or (ignore-errors (namestring (truename path)))
      (string-right-trim "/" (fs-path-string path))))

(defmethod fs-file-mode ((fs real-filesystem) path)
  (file-mode path))

(defmethod fs-make-directory ((fs real-filesystem) path)
  (ensure-directories-with-escalation
   (namestring (uiop:ensure-directory-pathname path))))

(defmethod fs-write-file ((fs real-filesystem) path content)
  (write-file-with-escalation (fs-path-string path) content))

(defmethod fs-symlink ((fs real-filesystem) source target)
  (let ((args (list "ln" "-sf" (fs-path-string source) (fs-path-string target))))
    (unless (zerop (nth-value 2 (uiop:run-program args :ignore-error-status t)))
      (run-privileged args))))

(defmethod fs-delete ((fs real-filesystem) path)
  (if (fs-directory-p fs path)
      (fs-rmdir fs path)
      (handler-case
          (progn (delete-file path) t)
        (error () (run-privileged (list "rm" "-f" (fs-path-string path))) t))))

(defmethod fs-rmdir ((fs real-filesystem) path)
  "T if removed; NIL if not empty or missing. A non-zero rmdir is the
  normal signal that the directory isn't empty -- a cascade stop condition,
  not a failure -- so escalation happens only when the directory is actually
  empty (a pure permission problem), never for a mere non-empty stop."
  (or (zerop (nth-value 2
                (uiop:run-program (list "rmdir" (fs-path-string path))
                                  :ignore-error-status t)))
      (when (null (fs-directory-entries fs path))
        (run-privileged (list "rmdir" (fs-path-string path)))
        t)))

(defun real-delete-tree (fs path)
  "Recursively remove the directory at PATH using only the FS-* protocol:
symlinks and files are deleted, subdirectories recursed, and only an
empty directory is rmdir'd -- so the escalate-on-demand policy applies
per operation and a user-owned tree never touches sudo. Idempotent: a
missing PATH is a no-op returning T."
  (labels ((join (p name)
             (format nil "~a/~a" (string-right-trim "/" p) name))
           (remove-node (p)
             (cond
               ((fs-symlink-p fs p) (fs-delete fs p))
               ((fs-directory-p fs p)
                (unless (fs-rmdir fs p)
                  (dolist (name (fs-directory-entries fs p))
                    (remove-node (join p name)))
                  (fs-rmdir fs p)))
               ((fs-file-p fs p) (fs-delete fs p))
               (t nil))))
    (remove-node (string-right-trim "/" (fs-path-string path)))
    t))

(defmethod fs-delete-directory-tree ((fs real-filesystem) path)
  (real-delete-tree fs path))

(defmethod fs-set-mode ((fs real-filesystem) path mode)
  (when mode (set-file-mode path mode)))

(defmethod fs-set-owner ((fs real-filesystem) path owner group)
  (when (or owner group) (set-file-owner path owner group)))