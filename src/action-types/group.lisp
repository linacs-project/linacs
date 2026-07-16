;;;; src/action-types/group.lisp
;;;;
;;;; The :group executor. Idempotently ensures a system group exists with
;;;; the given GID, or is removed.
;;;;
;;;; Usage:
;;;;     (:action :group :target "docker" :gid 999)

(in-package :linacs.core)

(defun group-exists-p (name)
  (zerop (nth-value 2 (uiop:run-program (list "getent" "group" name) :ignore-error-status t))))

(defun group-gid (name)
  (let ((line (ignore-errors
               (string-trim '(#\Newline)
                (uiop:run-program (list "getent" "group" name) :output '(:string :stripped t))))))
    (when line (parse-integer (nth 2 (uiop:split-string line :separator '(#\:))) :junk-allowed t))))

(defun execute-group (action &key mode)
  (let* ((name (action-target action))
         (exists (group-exists-p name))
         (want-gid (getf action :gid))
         (differs (and exists want-gid (/= want-gid (or (group-gid name) -1))))
         (changed (or (not exists) differs)))
    (case mode
      (:check (report (if changed :would-change :unchanged) :target name))
      (:apply
       (cond
         ((not exists)
          (run-privileged (append (list "groupadd")
                                   (when want-gid (list "-g" (write-to-string want-gid)))
                                   (list name))))
         (differs (run-privileged (list "groupmod" "-g" (write-to-string want-gid) name))))
       (report (if changed :changed :unchanged) :target name))
      (:remove
       (when exists (run-privileged (list "groupdel" name)))
       (report :removed :target name)))))

(register-action-type :group #'execute-group
  :description "Ensure a system group exists with the given GID")
