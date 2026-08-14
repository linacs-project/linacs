;;;; src/action-types/symlink.lisp
;;;;
;;;; The :symlink executor. Applies `ln -sf` semantics, checking the
;;;; existing link target before touching anything.
;;;;
;;;; Usage:
;;;;     (:action :symlink :target "~/.emacs.d" :to "~/.config/emacs")

(in-package :linacs.core)

(defun execute-symlink (action &key mode)
  (let* ((fs (context-filesystem))
         (target (expand-home (action-target action)))
         (to (getf action :to))
         (current (fs-read-link fs target))
         (changed (not (equal current to))))
    (case mode
      (:check (report (if changed :would-change :unchanged) :target target))
      (:apply
       (when changed (fs-symlink fs to target))
       (report (if changed :changed :unchanged) :target target))
      (:remove
       (when (fs-exists-p fs target) (fs-delete fs target))
       (report :removed :target target)))))

(register-action-type :symlink #'execute-symlink
  :description "Apply ln -sf semantics for a symlink")
