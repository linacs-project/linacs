;;;; src/action-types/sysctl.lisp
;;;;
;;;; The :sysctl executor. Persists a kernel parameter under
;;;; /etc/sysctl.d/ AND applies it to the running kernel immediately via
;;;; `sysctl -w`, so no reboot is needed to see the effect.
;;;;
;;;; Usage:
;;;;     (:action :sysctl :target "net.ipv4.ip_forward" :value 1)

(in-package :linacs.core)

(defun sysctl-runtime-value (key)
  (ignore-errors
   (string-trim '(#\Newline #\Space)
    (uiop:run-program (list "sysctl" "-n" key) :output '(:string :stripped t)))))

(defun sysctl-line-key (line)
  (let ((pos (position #\= line)))
    (and pos (string-trim '(#\Space) (subseq line 0 pos)))))

(defun execute-sysctl (action &key mode)
  (let* ((key (action-target action))
         (value (princ-to-string (getf action :value)))
         (file (or (getf action :file) "/etc/sysctl.d/99-linacs.conf"))
         (line (format nil "~a = ~a" key value))
         (file-lines (let ((c (read-file-string file)))
                       (if (or (null c) (zerop (length c))) '()
                           (uiop:split-string (string-right-trim '(#\Newline) c) :separator '(#\Newline)))))
         (file-has-line (member line file-lines :test #'string=))
         (runtime-ok (equal (sysctl-runtime-value key) value))
         (changed (or (not file-has-line) (not runtime-ok))))
    (case mode
      (:check (report (if changed :would-change :unchanged) :target key))
      (:apply
       (unless file-has-line
         (let ((without (remove-if (lambda (l) (equal (sysctl-line-key l) key)) file-lines)))
           (write-privileged-file file (format nil "~{~a~%~}~a~%" without line))))
       (unless runtime-ok (run-privileged (list "sysctl" "-w" (format nil "~a=~a" key value))))
       (report (if changed :changed :unchanged) :target key))
      (:remove
       (write-privileged-file file (format nil "~{~a~%~}" (remove line file-lines :test #'string=)))
       (report :removed :target key)))))

(register-action-type :sysctl #'execute-sysctl
  :description "Set a kernel parameter, persisted and applied immediately")
