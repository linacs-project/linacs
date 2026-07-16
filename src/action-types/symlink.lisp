;;;; src/action-types/symlink.lisp
;;;;
;;;; The :symlink executor. Applies `ln -sf` semantics, checking the
;;;; existing link target before touching anything.
;;;;
;;;; Usage:
;;;;     (:action :symlink :target "~/.emacs.d" :to "~/.config/emacs")

(in-package :linacs.core)

(defun current-symlink-target (path)
  (ignore-errors
   (string-trim '(#\Newline)
                (uiop:run-program (list "readlink" (namestring path))
                                   :output '(:string :stripped t)))))

(defun execute-symlink (action &key mode)
  (let* ((target (expand-home (action-target action)))
         (to (getf action :to))
         (current (current-symlink-target target))
         (changed (not (equal current to))))
    (case mode
      (:check (report (if changed :would-change :unchanged) :target target))
      (:apply
       (when changed
         (ignore-errors (uiop:run-program (list "ln" "-sf" to (namestring target)))))
       (report (if changed :changed :unchanged) :target target))
      (:remove
       (when (probe-file target) (ignore-errors (delete-file target)))
       (report :removed :target target)))))

(register-action-type :symlink #'execute-symlink
  :description "Apply ln -sf semantics for a symlink")
