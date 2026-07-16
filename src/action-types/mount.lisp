;;;; src/action-types/mount.lisp
;;;;
;;;; The :mount executor. Ensures a persistent /etc/fstab entry exists AND
;;;; that the filesystem is actually mounted right now, not just on next
;;;; boot; unmounts and removes the entry on :remove.
;;;;
;;;; Usage:
;;;;     (:action :mount :target "/mnt/data" :device "/dev/sdb1" :fstype "ext4")

(in-package :linacs.core)

(defparameter +fstab-path+ "/etc/fstab")

(defun fstab-lines ()
  (let ((content (read-file-string +fstab-path+)))
    (if (or (null content) (zerop (length content)))
        '()
        (uiop:split-string (string-right-trim '(#\Newline) content) :separator '(#\Newline)))))

(defun fstab-line-mountpoint (line)
  (let ((fields (remove "" (uiop:split-string (string-trim '(#\Space #\Tab) line) :separator '(#\Space #\Tab))
                        :test #'string=)))
    (and (>= (length fields) 2) (not (eql (char (first fields) 0) #\#)) (second fields))))

(defun fstab-entry-for (target)
  (find target (fstab-lines) :key #'fstab-line-mountpoint :test #'equal))

(defun fstab-line-for (action)
  (format nil "~a ~a ~a ~a ~a ~a"
          (getf action :device) (action-target action) (or (getf action :fstype) "auto")
          (or (getf action :options) "defaults") (or (getf action :dump) 0) (or (getf action :pass) 2)))

(defun mounted-p (target)
  (zerop (nth-value 2 (uiop:run-program (list "mountpoint" "-q" target) :ignore-error-status t))))

(defun execute-mount (action &key mode)
  (let* ((target (action-target action))
         (intended (fstab-line-for action))
         (current (fstab-entry-for target))
         (fstab-ok (equal current intended))
         (is-mounted (mounted-p target))
         (changed (or (not fstab-ok) (not is-mounted))))
    (case mode
      (:check (report (if changed :would-change :unchanged) :target target))
      (:apply
       (unless fstab-ok
         (ensure-directories-exist (uiop:ensure-directory-pathname target))
         (write-privileged-file +fstab-path+
           (format nil "~{~a~%~}~a~%" (remove current (fstab-lines) :test #'equal) intended)))
       (unless is-mounted (run-privileged (list "mount" target)))
       (report (if changed :changed :unchanged) :target target))
      (:remove
       (when is-mounted (run-privileged (list "umount" target)))
       (when current
         (write-privileged-file +fstab-path+
           (format nil "~{~a~%~}" (remove current (fstab-lines) :test #'equal))))
       (report :removed :target target)))))

(register-action-type :mount #'execute-mount
  :description "Ensure a persistent /etc/fstab entry exists and the filesystem is mounted")
