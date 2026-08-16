;;;; src/action-types/copy-file.lisp
;;;;
;;;; The :copy-file executor. Compares intended content (plain, with
;;;; :content string, or with :template t rendered) against what's on
;;;; disk, and writes only if different. :from resolves under the asset
;;;; root (default: the project root itself).
;;;;
;;;; :content takes precedence over :from / :template / :renderer when
;;;; present -- use it for generated config files that aren't backed by
;;;; a static file or a template renderer.
;;;;
;;;; Usage:
;;;;     (:action :copy-file :to "~/.gitconfig" :from "gitconfig" :mode #o644)
;;;;     (:action :copy-file :to "~/.emacs.d/init.el" :content "(message \"hello\")")

(in-package :linacs.core)

(defun copy-file-intended-content (action fs)
  (let ((inline (getf action :content)))
    (if inline
        inline
        (let* ((from (getf action :from))
               (asset-root (action-asset-root action))
               (src-path (namestring (merge-pathnames from (uiop:ensure-directory-pathname asset-root)))))
          (if (or (getf action :template) (getf action :renderer))
              (render-template action)
              (or (fs-read-file fs src-path)
                  (error 'execution-failure :action-type :copy-file
                         :target (getf action :target (getf action :to))
                         :underlying (format nil "Source file ~a does not exist or is unreadable" src-path))))))))

(defun execute-copy-file (action &key mode)
  (let* ((fs (context-filesystem))
         (to (expand-home (getf action :target (getf action :to)))))
    (case mode
      (:remove
       (when (fs-exists-p fs to)
         (fs-delete fs to))
       (report :removed :target to))
      (t
       (let* ((intended (copy-file-intended-content action fs))
              (current (fs-read-file fs to))
              (changed (not (equal intended current))))
         (case mode
           (:check (report (if changed :would-change :unchanged)
                           :target to :current current :expected intended))
           (:apply
            (when changed
              (fs-write-file fs to intended)
              (fs-apply-ownership fs to action))
            (report (if changed :changed :unchanged) :target to))))))))

(register-action-type :copy-file #'execute-copy-file
  :description "Copy or render a file to a target path")
