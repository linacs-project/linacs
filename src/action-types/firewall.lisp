;;;; src/action-types/firewall.lisp
;;;;
;;;; The :firewall executor. Opens or closes a port through whichever of
;;;; firewalld/ufw is actually installed, so a home config doesn't have to
;;;; hard-code one; identity is qualified by :protocol, so tcp and udp rules
;;;; on the same port number are independent.
;;;;
;;;; Usage:
;;;;     (:action :firewall :target 80 :protocol "tcp" :allow t)

(in-package :linacs.core)

(defun firewall-backend ()
  (cond
    ((which "firewall-cmd") :firewalld)
    ((which "ufw") :ufw)
    (t :unknown)))

(defun firewall-rule-active-p (backend port protocol)
  (case backend
    (:firewalld (zerop (nth-value 2 (uiop:run-program
                                      (list "firewall-cmd" "--query-port" (format nil "~a/~a" port protocol))
                                      :ignore-error-status t))))
    (:ufw (let ((status (or (ignore-errors (uiop:run-program '("ufw" "status") :output '(:string :stripped t))) "")))
            (and (search (format nil "~a/~a" port protocol) status) t)))
    (t nil)))

(defun execute-firewall (action &key mode)
  (let* ((port (action-target action))
         (protocol (getf action :protocol "tcp"))
         (want-allow (getf action :allow t))
         (backend (firewall-backend))
         (active (firewall-rule-active-p backend port protocol))
         (ok (eq (not (not active)) (not (not want-allow)))))
    (case mode
      (:check (report (if ok :unchanged :would-change) :target port))
      (:apply
       (unless ok
         (case backend
           (:firewalld
            (run-privileged (list "firewall-cmd" (if want-allow "--add-port" "--remove-port")
                                  (format nil "~a/~a" port protocol) "--permanent"))
            (run-privileged (list "firewall-cmd" "--reload")))
           (:ufw
            (run-privileged (list "ufw" (if want-allow "allow" "deny") (format nil "~a/~a" port protocol))))
           (t
            (linacs.log:warn* "No supported firewall backend (firewalld/ufw) found; :firewall for ~a/~a not applied."
                              port protocol))))
       (report (if ok :unchanged :changed) :target port))
      (:remove
       (case backend
         (:firewalld
          (run-privileged (list "firewall-cmd" "--remove-port" (format nil "~a/~a" port protocol) "--permanent"))
          (run-privileged (list "firewall-cmd" "--reload")))
         (:ufw (run-privileged (list "ufw" "delete" "allow" (format nil "~a/~a" port protocol))))
         (t nil))
       (report :removed :target port)))))

(register-action-type :firewall #'execute-firewall
  :description "Open/close a port via firewalld or ufw, whichever is installed"
  :identity (lambda (a) (list* :firewall (getf a :protocol "tcp") (action-target a))))
