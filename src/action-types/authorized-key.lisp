;;;; src/action-types/authorized-key.lisp
;;;;
;;;; The :authorized-key executor. Manages one entry in a user's
;;;; ~/.ssh/authorized_keys without disturbing any other key already there --
;;;; identity is qualified by the key material itself, so re-declaring the
;;;; same key with a different comment updates it in place rather than
;;;; duplicating it, and the required 700/600 permissions are enforced.
;;;;
;;;; Usage:
;;;;     (:action :authorized-key :target "deploy" :key "ssh-ed25519 AAAA..." :comment "ci-bot")

(in-package :linacs.core)

(defun authorized-key-user-home (user)
  (let ((info (user-info user)))
    (or (and info (getf info :home)) (format nil "/home/~a" user))))

(defun authorized-keys-path (user)
  (format nil "~a/.ssh/authorized_keys" (authorized-key-user-home user)))

(defun akey-material (line)
  "The key-type+key-data portion of an authorized_keys line, ignoring any
leading options and trailing comment -- this is what identifies a key
regardless of comment changes."
  (let ((fields (remove "" (uiop:split-string (string-trim '(#\Space) line) :separator '(#\Space)) :test #'string=)))
    (cond
      ((null fields) "")
      ((member (first fields) '("ssh-rsa" "ssh-ed25519" "ssh-ecdsa" "ecdsa-sha2-nistp256"
                                 "ecdsa-sha2-nistp384" "ecdsa-sha2-nistp521" "ssh-dss")
                :test #'string=)
       (format nil "~a ~a" (first fields) (second fields)))
      ;; leading options field before the key type
      ((>= (length fields) 3) (format nil "~a ~a" (second fields) (third fields)))
      (t line))))

(defun execute-authorized-key (action &key mode)
  (let* ((user (action-target action))
         (key (getf action :key))
         (comment (getf action :comment))
         (path (authorized-keys-path user))
         (intended (string-trim '(#\Space) (format nil "~a~@[ ~a~]" key comment)))
         (want-material (akey-material intended))
         (content (or (read-file-string path) ""))
         (lines (if (zerop (length content)) '()
                    (uiop:split-string (string-right-trim '(#\Newline) content) :separator '(#\Newline))))
         (existing (find want-material lines :key #'akey-material :test #'string=))
         (up-to-date (equal existing intended)))
    (case mode
      (:check (report (if up-to-date :unchanged :would-change) :target path))
      (:apply
       (unless up-to-date
         (let* ((without (remove-if (lambda (l) (string= (akey-material l) want-material)) lines))
                (new-lines (append without (list intended)))
                (ssh-dir (format nil "~a/.ssh" (authorized-key-user-home user))))
           (ensure-directories-with-escalation (format nil "~a/" ssh-dir))
           (write-file-with-escalation path (format nil "~{~a~%~}" new-lines))
           (set-file-owner ssh-dir user user)
           (set-file-mode ssh-dir #o700)
           (set-file-owner path user user)
           (set-file-mode path #o600)))
       (report (if up-to-date :unchanged :changed) :target path))
      (:remove
       (when existing
         (write-file-with-escalation path
           (format nil "~{~a~%~}" (remove-if (lambda (l) (string= (akey-material l) want-material)) lines))))
       (report :removed :target path)))))

(register-action-type :authorized-key #'execute-authorized-key
  :description "Manage one entry in a user's ~/.ssh/authorized_keys"
  :identity (lambda (a) (list :authorized-key (action-target a) (getf a :key))))
