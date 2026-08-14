;;;; src/action-types/config-env.lisp
;;;;
;;;; The :config-env executor. Sets KEY=value pairs in a systemd
;;;; environment.d-style file (one KEY=value per line, no section headers).
;;;;
;;;; Usage:
;;;;     (:action :config-env :target "~/.config/environment.d/wayland.conf"
;;;;              :set (("MOZ_ENABLE_WAYLAND" . "1")))

(in-package :linacs.core)

(defun parse-env-file (content)
  (let ((result '()))
    (dolist (line (uiop:split-string (or content "") :separator '(#\Newline)))
      (let ((pos (position #\= line)))
        (when (and pos (> pos 0))
          (push (cons (subseq line 0 pos) (subseq line (1+ pos))) result))))
    (nreverse result)))

(defun render-env-file (alist)
  (format nil "~{~a=~a~%~}" (loop for (k . v) in alist append (list k v))))

(defun execute-config-env (action &key mode)
  (let* ((fs (context-filesystem))
         (target (expand-home (action-target action)))
         (set-alist (getf action :set))
         (current (or (fs-read-file fs target) ""))
         (parsed (parse-env-file current))
         (merged (dolist (kv set-alist parsed)
                   (let ((existing (assoc (car kv) parsed :test #'equal)))
                     (if existing (setf (cdr existing) (cdr kv)) (setf parsed (append parsed (list kv)))))))
         (intended (render-env-file merged))
         (changed (not (equal intended current))))
    (case mode
      (:check (report (if changed :would-change :unchanged) :target target))
      (:apply (when changed (fs-write-file fs target intended))
              (report (if changed :changed :unchanged) :target target))
      (:remove
       (let ((kept (remove-if (lambda (kv) (assoc (car kv) set-alist :test #'equal)) parsed)))
         (fs-write-file fs target (render-env-file kept))
         (report :removed :target target))))))

(register-action-type :config-env #'execute-config-env
  :description "Set KEY=value pairs in a systemd environment.d-style file")
