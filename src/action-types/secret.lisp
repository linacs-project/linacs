;;;; src/action-types/secret.lisp
;;;;
;;;; The :secret executor. Resolves a secret value (via secrets.lisp) and
;;;; writes it to TARGET with restrictive permissions, only when the
;;;; resolved value actually differs from what's on disk.
;;;;
;;;; Usage:
;;;;     (:action :secret :target "~/.ssh/id_ed25519" :from :pass :path "ssh/id_ed25519" :mode #o600)

(in-package :linacs.core)

(defun execute-secret (action &key mode)
  (let* ((fs (context-filesystem))
         (target (expand-home (action-target action))))
    (case mode
      (:check
       ;; Do not resolve the secret source just to check -- report presence only.
       (report (if (fs-exists-p fs target) :unchanged :would-change) :target target))
      (:apply
       (let* ((value (if (or (getf action :template) (getf action :renderer))
                          (render-template action)
                          (resolve-secret (list :from (getf action :from)
                                                 :path (getf action :path)
                                                 :message (getf action :message))
                                           :target target)))
              (current (fs-read-file fs target))
              (changed (not (equal value current))))
         (when changed
           (fs-write-file fs target value)
           (fs-apply-ownership fs target action)
           (fs-set-mode fs target (or (getf action :mode) #o600)))
         (report (if changed :changed :unchanged) :target target)))
      (:remove
       (when (fs-exists-p fs target)
         (fs-delete fs target))
       (report :removed :target target)))))

(register-action-type :secret #'execute-secret
  :description "Write a secret value (from pass/vault/file/prompt) to a target file")
