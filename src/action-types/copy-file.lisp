;;;; src/action-types/copy-file.lisp
;;;;
;;;; The :copy-file executor. Compares intended content (plain or, with
;;;; :template t, rendered) against what's on disk, and writes only if
;;;; different. :from resolves under the project's files/ directory.
;;;;
;;;; Usage:
;;;;     (:action :copy-file :to "~/.gitconfig" :from "gitconfig" :mode #o644)

(in-package :linacs.core)

(defun copy-file-intended-content (action)
  (let* ((from (getf action :from))
         (root (or (getf action :project-root) "."))
         (files-dir (merge-pathnames (make-pathname :directory '(:relative "files"))
                                      (uiop:ensure-directory-pathname root)))
         (src-path (merge-pathnames from files-dir)))
    (if (or (getf action :template) (getf action :renderer))
        (render-template action)
        (uiop:read-file-string src-path))))

(defun execute-copy-file (action &key mode)
  (let ((to (expand-home (getf action :target (getf action :to)))))
    (case mode
      (:remove
       (when (probe-file to)
         (handler-case (delete-file to)
           (error () (run-privileged (list "rm" "-f" (namestring to))))))
       (report :removed :target to))
      (t
       (let* ((intended (copy-file-intended-content action))
              (current (read-file-string to))
              (changed (not (equal intended current))))
         (case mode
           (:check (report (if changed :would-change :unchanged) :target to))
           (:apply
            (when changed
              (write-file-with-escalation to intended)
              (apply-file-ownership to action))
            (report (if changed :changed :unchanged) :target to))))))))

(register-action-type :copy-file #'execute-copy-file
  :description "Copy or render a file to a target path")
