;;;; src/action-types/config-lines.lisp
;;;;
;;;; The :config-lines executor. Ensures a set of lines are present and a
;;;; set of lines are absent in a target file, writing only if the computed
;;;; result differs from what's on disk. Identity includes the content, so
;;;; repeated calls against the same file are additive, never conflicting.
;;;;
;;;; Usage:
;;;;     (:action :config-lines :target "~/.config/i3/config"
;;;;              :ensure ("bindsym $mod+Return exec emacs")
;;;;              :remove ("bindsym $mod+Return exec i3-sensible-terminal"))

(in-package :linacs.core)

(defun compute-config-lines (current ensure remove-list)
  (let* ((lines (if (zerop (length current))
                     '()
                     (uiop:split-string (string-right-trim '(#\Newline #\Return) current) :separator '(#\Newline))))
         (kept (remove-if (lambda (l) (member l remove-list :test #'string=)) lines))
         (missing (remove-if (lambda (l) (member l kept :test #'string=)) ensure)))
    (format nil "~{~a~%~}" (append kept missing))))

(defun execute-config-lines (action &key mode)
  (let* ((fs (context-filesystem))
         (target (expand-home (action-target action)))
         (ensure (getf action :ensure))
         (remove-list (getf action :remove))
          (current (or (fs-read-file fs target) ""))
          ;; Normalize \r\n to \n for consistent comparison
          (current (remove #\Return current))
         (intended (compute-config-lines current ensure remove-list))
         (changed (not (equal intended current))))
    (case mode
      (:check
       (let ((lines (if (zerop (length current))
                        '()
                        (uiop:split-string (string-right-trim '(#\Newline #\Return) current) :separator '(#\Newline)))))
         (report (if changed :would-change :unchanged)
                 :target target
                 :added (remove-if (lambda (l) (member l lines :test #'string=)) ensure)
                 :removed (remove-if (lambda (l) (not (member l lines :test #'string=))) remove-list))))
      (:apply
       (when changed (fs-write-file fs target intended))
       (report (if changed :changed :unchanged) :target target))
      (:remove
       ;; Remove behavior: remove the ensured lines, add back the removed lines.
       (let* ((reverted (compute-config-lines current remove-list ensure)))
         (fs-write-file fs target reverted)
         (report :removed :target target))))))

(register-action-type :config-lines #'execute-config-lines
  :description "Ensure specific lines are present/absent in a file, leaving the rest untouched"
  :dedup-behavior :additive
  :identity (lambda (a)
              (list :config-lines
                    (list (cons :ensure (getf a :ensure))
                          (cons :remove (getf a :remove)))
                    (action-target a))))
