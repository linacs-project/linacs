;;;; src/action-types/env-var.lisp
;;;;
;;;; The :env-var executor. Ensures a single `export KEY="value"` line
;;;; exists in a target shell-init file, leaving everything else in it
;;;; untouched.
;;;;
;;;; Usage:
;;;;     (:action :env-var :target "EDITOR" :value "emacs" :file "~/.profile")

(in-package :linacs.core)

(defun env-var-line (key value) (format nil "export ~a=\"~a\"" key value))

(defun ensure-line-in-file (path line)
  "Return new content with LINE present exactly once, appended if absent."
  (let* ((content (or (read-file-string path) ""))
         (lines (uiop:split-string content :separator '(#\Newline))))
    (if (member line lines :test #'string=)
        content
        (concatenate 'string (string-right-trim '(#\Newline) content)
                      (if (zerop (length content)) "" (string #\Newline))
                      line (string #\Newline)))))

(defun remove-line-from-file (path line)
  (let* ((content (or (read-file-string path) ""))
         (lines (uiop:split-string content :separator '(#\Newline))))
    (format nil "~{~a~%~}" (remove line lines :test #'string=))))

(defun execute-env-var (action &key mode)
  (let* ((file (expand-home (getf action :file)))
         (line (env-var-line (action-target action) (getf action :value)))
         (current (or (read-file-string file) ""))
         (present (search line current)))
    (case mode
      (:check (report (if present :unchanged :would-change) :target file))
      (:apply
       (unless present (write-file-string file (ensure-line-in-file file line)))
       (report (if present :unchanged :changed) :target file))
      (:remove
       (when present (write-file-string file (remove-line-from-file file line)))
       (report :removed :target file)))))

(register-action-type :env-var #'execute-env-var
  :description "Ensure one export KEY=\"value\" line exists in a file")
