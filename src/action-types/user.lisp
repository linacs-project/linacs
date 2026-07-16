;;;; src/action-types/user.lisp
;;;;
;;;; The :user executor. Idempotently ensures a system user exists with the
;;;; given attributes (creating or modifying only whatever's actually wrong),
;;;; locks/unlocks it, or removes it.
;;;;
;;;; Usage:
;;;;     (:action :user :target "deploy" :shell "/bin/bash" :create-home t)

(in-package :linacs.core)

(defun user-exists-p (name)
  (zerop (nth-value 2 (uiop:run-program (list "id" name) :ignore-error-status t))))

(defun user-info (name)
  "Plist of :uid :gid :home :shell for NAME via getent, or nil if absent."
  (let ((line (ignore-errors
               (string-trim '(#\Newline)
                (uiop:run-program (list "getent" "passwd" name) :output '(:string :stripped t))))))
    (when (and line (plusp (length line)))
      (let ((fields (uiop:split-string line :separator '(#\:))))
        (list :uid (parse-integer (nth 2 fields) :junk-allowed t)
              :gid (parse-integer (nth 3 fields) :junk-allowed t)
              :home (nth 5 fields)
              :shell (nth 6 fields))))))

(defun user-locked-p (name)
  (let ((out (ignore-errors (uiop:run-program (list "passwd" "-S" name) :output '(:string :stripped t)))))
    (and out (search " L " (concatenate 'string " " out " ")) t)))

(defun user-attrs-differ-p (name action)
  (let ((info (user-info name)))
    (and info
         (or (and (getf action :uid) (/= (getf action :uid) (getf info :uid)))
             (and (getf action :gid) (/= (getf action :gid) (getf info :gid)))
             (and (getf action :shell) (not (equal (getf action :shell) (getf info :shell))))
             (and (getf action :home) (not (equal (getf action :home) (getf info :home))))))))

(defun execute-user (action &key mode)
  (let* ((name (action-target action))
         (exists (user-exists-p name))
         (differs (and exists (user-attrs-differ-p name action)))
         (want-locked (getf action :locked))
         (locked (and exists (user-locked-p name)))
         (lock-differs (and exists (not (eq (not (not want-locked)) locked))))
         (changed (or (not exists) differs lock-differs)))
    (case mode
      (:check (report (if changed :would-change :unchanged) :target name))
      (:apply
       (cond
         ((not exists)
          (run-privileged
           (append (list "useradd")
                   (when (getf action :uid) (list "-u" (write-to-string (getf action :uid))))
                   (when (getf action :gid) (list "-g" (write-to-string (getf action :gid))))
                   (when (getf action :shell) (list "-s" (getf action :shell)))
                   (when (getf action :home) (list "-d" (getf action :home)))
                   (list (if (getf action :create-home t) "-m" "-M"))
                   (when (getf action :system) (list "-r"))
                   (list name))))
         (differs
          (run-privileged
           (append (list "usermod")
                   (when (getf action :uid) (list "-u" (write-to-string (getf action :uid))))
                   (when (getf action :gid) (list "-g" (write-to-string (getf action :gid))))
                   (when (getf action :shell) (list "-s" (getf action :shell)))
                   (when (getf action :home) (list "-d" (getf action :home)))
                   (list name)))))
       (when lock-differs
         (run-privileged (list "usermod" (if want-locked "-L" "-U") name)))
       (report (if changed :changed :unchanged) :target name))
      (:remove
       (when exists
         (run-privileged (append (list "userdel") (when (getf action :remove-home) (list "-r")) (list name))))
       (report :removed :target name)))))

(register-action-type :user #'execute-user
  :description "Create, modify, lock, or remove a system user")
