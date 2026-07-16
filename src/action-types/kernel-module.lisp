;;;; src/action-types/kernel-module.lisp
;;;;
;;;; The :kernel-module executor. Loads a module now and persists that via
;;;; /etc/modules-load.d/ (:state :loaded), or blacklists one via
;;;; /etc/modprobe.d/ (:state :blacklisted).
;;;;
;;;; Usage:
;;;;     (:action :kernel-module :target "usb-storage" :state :blacklisted)

(in-package :linacs.core)

(defun kernel-module-loaded-p (name)
  (shell-ok-p (format nil "lsmod | grep -qw ~a" name)))

(defun execute-kernel-module (action &key mode)
  (let* ((name (action-target action))
         (state (getf action :state :loaded))
         (loaded (kernel-module-loaded-p name)))
    (ecase state
      (:loaded
       (let* ((file (format nil "/etc/modules-load.d/~a.conf" name))
              (persisted (equal (string-trim '(#\Newline) (or (read-file-string file) "")) name))
              (changed (or (not loaded) (not persisted))))
         (case mode
           (:check (report (if changed :would-change :unchanged) :target name))
           (:apply
            (unless loaded (run-privileged (list "modprobe" name)))
            (unless persisted (write-privileged-file file (format nil "~a~%" name)))
            (report (if changed :changed :unchanged) :target name))
           (:remove
            (when loaded (run-privileged (list "modprobe" "-r" name)))
            (when (probe-file file) (run-privileged (list "rm" "-f" file)))
            (report :removed :target name)))))
      (:blacklisted
       (let* ((file (format nil "/etc/modprobe.d/blacklist-~a.conf" name))
              (line (format nil "blacklist ~a" name))
              (persisted (equal (string-trim '(#\Newline) (or (read-file-string file) "")) line))
              (changed (or loaded (not persisted))))
         (case mode
           (:check (report (if changed :would-change :unchanged) :target name))
           (:apply
            (unless persisted (write-privileged-file file (format nil "~a~%" line)))
            (when loaded (run-privileged (list "modprobe" "-r" name)))
            (report (if changed :changed :unchanged) :target name))
           (:remove
            (when (probe-file file) (run-privileged (list "rm" "-f" file)))
            (report :removed :target name))))))))

(register-action-type :kernel-module #'execute-kernel-module
  :description "Load or blacklist a kernel module, persisted across reboots")
