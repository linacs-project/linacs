;;;; src/action-types/ensure-dir.lisp
;;;;
;;;; The :ensure-dir executor. Creates a directory and sets its
;;;; mode/ownership only if it doesn't already match.
;;;;
;;;; Usage:
;;;;     (:action :ensure-dir :target "~/.config/emacs" :mode #o755)

(in-package :linacs.core)

(defun execute-ensure-dir (action &key mode)
  (let* ((fs (context-filesystem))
         (target (expand-home (action-target action)))
         (dir (uiop:ensure-directory-pathname target))
         (exists (fs-directory-p fs dir))
         (mode-needed (and exists (getf action :mode)
                           (/= (or (fs-file-mode fs dir) -1) (getf action :mode)))))
    (case mode
      (:check (report (if (or (not exists) mode-needed) :would-change :unchanged) :target target))
      (:apply
       (unless exists (fs-make-directory fs dir))
       (when (or (not exists) mode-needed) (fs-apply-ownership fs dir action))
       (report (if (or (not exists) mode-needed) :changed :unchanged) :target target))
      (:remove
       (when (fs-directory-p fs dir)
         (fs-delete-directory-tree fs dir))
       (report :removed :target target)))))

(register-action-type :ensure-dir #'execute-ensure-dir
  :description "Ensure a directory exists with the given mode/ownership")
