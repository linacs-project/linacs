;;;; src/action-types/locale.lisp
;;;;
;;;; The :locale executor. Generates a locale if needed, sets it as the
;;;; system default, and optionally sets the timezone by re-pointing the
;;;; /etc/localtime symlink.
;;;;
;;;; Usage:
;;;;     (:action :locale :target "en_US.UTF-8" :timezone "America/New_York")

(in-package :linacs.core)

(defun locale-current-timezone ()
  (ignore-errors
   (let* ((link (string-trim '(#\Newline)
                 (uiop:run-program (list "readlink" "-f" "/etc/localtime") :output '(:string :stripped t))))
          (pos (search "/zoneinfo/" link)))
     (and pos (subseq link (+ pos (length "/zoneinfo/")))))))

(defun locale-generated-p (locale)
  (shell-ok-p (format nil "locale -a | grep -qi ~a" (substitute #\. #\Space locale))))

(defun locale-default-line-ok-p (locale)
  (let ((wanted (format nil "LANG=~a" locale)))
    (or (equal (string-trim '(#\Newline) (or (read-file-string "/etc/default/locale") "")) wanted)
        (equal (string-trim '(#\Newline) (or (read-file-string "/etc/locale.conf") "")) wanted))))

(defun execute-locale (action &key mode)
  (let* ((locale (action-target action))
         (timezone (getf action :timezone))
         (generated (locale-generated-p locale))
         (tz-ok (or (null timezone) (equal (locale-current-timezone) timezone)))
         (default-ok (locale-default-line-ok-p locale))
         (changed (or (not generated) (not tz-ok) (not default-ok))))
    (case mode
      (:check (report (if changed :would-change :unchanged) :target locale))
      (:apply
       (unless generated
         (run-privileged (list "sh" "-c" (format nil "echo ~a UTF-8 >> /etc/locale.gen 2>/dev/null; locale-gen" locale))))
       (unless default-ok
         (write-privileged-file (if (probe-file "/etc/locale.conf") "/etc/locale.conf" "/etc/default/locale")
                                 (format nil "LANG=~a~%" locale)))
       (when (and timezone (not tz-ok))
         (run-privileged (list "timedatectl" "set-timezone" timezone)))
       (report (if changed :changed :unchanged) :target locale))
      (:remove (report :unchanged :target locale)))))

(register-action-type :locale #'execute-locale
  :description "Generate and set the default system locale, and optionally the timezone")
