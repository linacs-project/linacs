;;;; src/action-types/permissions.lisp
;;;;
;;;; The :permissions executor. Fixes owner/group/mode on a path that
;;;; already exists, without creating it and without touching its content --
;;;; the tool for paths a package created, since :copy-file/:ensure-dir only
;;;; apply ownership at creation time.
;;;;
;;;; Usage:
;;;;     (:action :permissions :target "/var/lib/mysql" :owner "mysql" :group "mysql" :mode #o750)

(in-package :linacs.core)

(defun path-owner-group (path)
  (let ((out (ignore-errors
              (string-trim '(#\Newline)
               (uiop:run-program (list "stat" "-c" "%U:%G" (namestring path)) :output '(:string :stripped t))))))
    (when out (uiop:split-string out :separator '(#\:)))))

(defun chmod-with-escalation (target mode recursive)
  (let ((args (append (list "chmod") (when recursive (list "-R")) (list (format nil "~o" mode) (namestring target)))))
    (unless (zerop (nth-value 2 (uiop:run-program args :ignore-error-status t)))
      (run-privileged args))))

(defun chown-with-escalation (target owner group recursive)
  (let ((args (append (list "chown") (when recursive (list "-R"))
                       (list (format nil "~a:~a" (or owner "") (or group "")) (namestring target)))))
    (unless (zerop (nth-value 2 (uiop:run-program args :ignore-error-status t)))
      (run-privileged args))))

(defun execute-permissions (action &key mode)
  (let* ((target (expand-home (action-target action)))
         (want-mode (getf action :mode))
         (want-owner (getf action :owner))
         (want-group (getf action :group))
         (recursive (getf action :recursive))
         (exists (probe-file target))
         (current-og (and exists (path-owner-group target)))
         (mode-changed (and exists want-mode (/= want-mode (or (file-mode target) -1))))
         (owner-changed (and exists want-owner (not (equal want-owner (first current-og)))))
         (group-changed (and exists want-group (not (equal want-group (second current-og)))))
         (changed (or mode-changed owner-changed group-changed)))
    (case mode
      (:check (report (cond ((not exists) :missing) (changed :would-change) (t :unchanged)) :target target))
      (:apply
       (when exists
         (when mode-changed (chmod-with-escalation target want-mode recursive))
         (when (or owner-changed group-changed) (chown-with-escalation target want-owner want-group recursive)))
       (report (cond ((not exists) :missing) (changed :changed) (t :unchanged)) :target target))
      (:remove
       ;; Nothing meaningful to "remove" for a metadata-only action.
       (report :unchanged :target target)))))

(register-action-type :permissions #'execute-permissions
  :description "Fix owner/group/mode on an existing path, without touching its content")
