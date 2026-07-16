;;;; src/log.lisp
;;;;
;;;; A small leveled-logging facility used throughout the core and available
;;;; to project-authored providers and executors. Verbosity is controlled by
;;;; the CLI's -v/-vv/--quiet flags (src/cli.lisp sets *VERBOSITY* from them).
;;;;
;;;; Usage:
;;;;     (linacs.log:info "Installing package ~a" name)   ; level 1, default and up
;;;;     (linacs.log:debug* "Catalog lookup: ~a -> ~a" a b) ; level 3, -vv only
;;;;     (linacs.log:warn* "Falling back to ~a" x)          ; level 1, default and up
;;;;     (linacs.log:error* "~a" condition)                 ; always shown

(in-package :linacs.log)

(defparameter *verbosity* 1
  "Current logging verbosity. 0=quiet 1=default 2=verbose 3=debug.")

(defun set-verbosity (n)
  (setf *verbosity* n))

(defun info (fmt &rest args)
  "Progress-level message, shown at default verbosity and above."
  (when (>= *verbosity* 1)
    (format t "~&[info] ~a~%" (apply #'format nil fmt args))))

(defun debug* (fmt &rest args)
  "Debug-level message, shown only at -vv."
  (when (>= *verbosity* 3)
    (format t "~&[debug] ~a~%" (apply #'format nil fmt args))))

(defun warn* (fmt &rest args)
  "Warning-level message, shown at default verbosity and above."
  (when (>= *verbosity* 1)
    (format t "~&[warn] ~a~%" (apply #'format nil fmt args))))

(defun error* (fmt &rest args)
  "Error-level message, always shown, even under --quiet."
  (format *error-output* "~&[error] ~a~%" (apply #'format nil fmt args)))
