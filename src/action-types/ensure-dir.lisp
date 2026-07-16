;;;; src/action-types/ensure-dir.lisp
;;;;
;;;; The :ensure-dir executor. Creates a directory and sets its
;;;; mode/ownership only if it doesn't already match.
;;;;
;;;; Usage:
;;;;     (:action :ensure-dir :target "~/.config/emacs" :mode #o755)

(in-package :linacs.core)

(defun execute-ensure-dir (action &key mode)
  (let* ((target (expand-home (action-target action)))
         (dir (uiop:ensure-directory-pathname target))
         (exists (uiop:directory-exists-p dir))
         (mode-needed (and exists (getf action :mode)
                           (/= (or (file-mode dir) -1) (getf action :mode)))))
    (case mode
      (:check (report (if (or (not exists) mode-needed) :would-change :unchanged) :target target))
      (:apply
       (unless exists (ensure-directories-with-escalation dir))
       (when (or (not exists) mode-needed) (apply-file-ownership dir action))
       (report (if (or (not exists) mode-needed) :changed :unchanged) :target target))
      (:remove
       (when (uiop:directory-exists-p dir)
         (handler-case (uiop:delete-directory-tree dir :validate t)
           (error () (run-privileged (list "rm" "-rf" (namestring dir))))))
       (report :removed :target target)))))

(register-action-type :ensure-dir #'execute-ensure-dir
  :description "Ensure a directory exists with the given mode/ownership")
