;;;; src/action-types/config-ini.lisp
;;;;
;;;; The :config-ini executor. Sets/unsets keys within a named [section] of
;;;; an INI-style file via a small built-in parser, leaving unrelated
;;;; sections and keys untouched.
;;;;
;;;; Usage:
;;;;     (:action :config-ini :target "~/.config/fontconfig/fonts.conf"
;;;;              :section "antialias" :set (("enable" . "true")) :unset ("rgba"))

(in-package :linacs.core)

(defun parse-ini (content)
  "Very small INI parser: returns list of (section . (key . value)*) blocks
preserving order, as an alist mapping section-name -> alist of key/value."
  (let ((sections (list (cons nil '())))
        (current nil))
    (dolist (line (uiop:split-string (or content "") :separator '(#\Newline)))
      (let ((trimmed (string-trim '(#\Space #\Tab) line)))
        (cond
          ((zerop (length trimmed)))
          ((and (char= (char trimmed 0) #\[) (char= (char trimmed (1- (length trimmed))) #\]))
           (setf current (subseq trimmed 1 (1- (length trimmed))))
           (push (cons current '()) sections))
          ((find #\= trimmed)
           (let* ((pos (position #\= trimmed))
                  (k (string-trim '(#\Space) (subseq trimmed 0 pos)))
                  (v (string-trim '(#\Space) (subseq trimmed (1+ pos)))))
             (push (cons k v) (cdr (assoc current sections :test #'equal))))))))
    (nreverse sections)))

(defun render-ini (sections)
  (with-output-to-string (s)
    (dolist (sec (reverse sections))
      (when (car sec) (format s "[~a]~%" (car sec)))
      (dolist (kv (reverse (cdr sec)))
        (format s "~a = ~a~%" (car kv) (cdr kv)))
      (format s "~%"))))

(defun apply-ini-ops (sections section set-alist unset-list)
  (let* ((sec-entry (or (assoc section sections :test #'equal)
                         (car (push (cons section '()) sections))))
         (kvs (cdr sec-entry)))
    (dolist (u unset-list) (setf kvs (remove u kvs :key #'car :test #'equal)))
    (dolist (s set-alist)
      (let ((existing (assoc (car s) kvs :test #'equal)))
        (if existing (setf (cdr existing) (cdr s)) (push s kvs))))
    (setf (cdr sec-entry) kvs)
    sections))

(defun execute-config-ini (action &key mode)
  (let* ((fs (context-filesystem))
         (target (expand-home (action-target action)))
         (section (getf action :section))
         (set-alist (getf action :set))
         (unset-list (getf action :unset))
         (current (or (fs-read-file fs target) ""))
         (sections (parse-ini current))
         (intended (render-ini (apply-ini-ops sections section set-alist unset-list)))
         (changed (not (equal (string-trim '(#\Newline) intended) (string-trim '(#\Newline) current)))))
    (case mode
      (:check (report (if changed :would-change :unchanged) :target target))
      (:apply (when changed (fs-write-file fs target intended))
              (report (if changed :changed :unchanged) :target target))
      (:remove
       (let ((reverted (render-ini (apply-ini-ops (parse-ini current) section nil (mapcar #'car set-alist)))))
         (fs-write-file fs target reverted)
         (report :removed :target target))))))

(register-action-type :config-ini #'execute-config-ini
  :description "Set/unset keys within a section of an INI-style file")
