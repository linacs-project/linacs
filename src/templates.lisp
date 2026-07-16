;;;; src/templates.lisp
;;;;
;;;; Template rendering for `:template t` files. A template renderer is a
;;;; plain function in the :linacs-templates package, found by convention from
;;;; the source filename ("gitconfig.tmpl" -> RENDER-GITCONFIG), receiving
;;;; facts and any :secrets as keyword arguments, returning a string.
;;;;
;;;; Usage:
;;;;     ;; in templates/renderers.lisp
;;;;     (defun linacs-templates:render-gitconfig (facts &key signing-key)
;;;;       (format nil "[user]~%  name = ~a" (getf facts :user-name)))
;;;;
;;;;     ;; in home.lisp
;;;;     (file "~/.gitconfig" :from "gitconfig.tmpl" :template t
;;;;           :secrets ((:signing-key :from :pass :path "git/signing-key")))

(in-package :linacs.core)

(defun template-renderer-symbol-name (filename)
  "Convert e.g. \"gitconfig.tmpl\" -> \"RENDER-GITCONFIG\"."
  (let* ((base (pathname-name filename)))
    (format nil "RENDER-~a" (string-upcase base))))

(defun find-template-renderer (filename)
  (find-symbol (template-renderer-symbol-name filename) :linacs-templates))

(defun render-template (action)
  "Render the template named by ACTION's :from, per the :template t /
 :renderer conventions. Resolves ACTION's :secrets first, then calls the
 renderer with FACTS and the resolved secrets as keyword arguments."
  (let* ((from (getf action :from))
         (renderer (or (getf action :renderer)
                        (let ((sym (find-template-renderer from)))
                          (unless (and sym (fboundp sym))
                            (error 'missing-template-renderer
                                   :template from
                                   :expected-symbol (template-renderer-symbol-name from)))
                          (symbol-function sym))))
         (secret-specs (getf action :secrets))
         ;; Each entry looks like (:token :from :pass :path "github/token") --
         ;; the leading element is the keyword-argument name, the rest is the
         ;; secret spec plist passed to RESOLVE-SECRET.
         (secret-kwargs
           (loop for entry in secret-specs
                 append (list (car entry)
                               (resolve-secret (cdr entry) :target (action-target action))))))
    (apply renderer *facts* secret-kwargs)))
