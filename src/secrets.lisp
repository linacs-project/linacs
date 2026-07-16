;;;; src/secrets.lisp
;;;;
;;;; Secret source resolution for :pass, :vault, :file, and :prompt. Values
;;;; are resolved fresh, immediately before the action that needs them runs,
;;;; and are never written to any intermediate plan file in plaintext.
;;;;
;;;; Usage:
;;;;   Called by the :secret and :copy-file (templated) executors, not normally
;;;;   invoked directly:
;;;;
;;;;     (resolve-secret '(:from :pass :path "ssh/id_ed25519") :target "~/.ssh/id_ed25519")

(in-package :linacs.core)

(defun interactive-terminal-p ()
  (and (uiop:getenv "TERM")
       (not (uiop:getenv "CI"))
       (ignore-errors (uiop:file-stream-p *terminal-io*))
       t))

(defun resolve-secret-pass (path)
  (string-trim '(#\Newline)
               (uiop:run-program (list "pass" "show" path) :output '(:string :stripped t))))

(defun resolve-secret-vault (path)
  ;; Best-effort integration point for HashiCorp Vault via its CLI.
  (string-trim '(#\Newline)
               (uiop:run-program (list "vault" "kv" "get" "-field=value" path)
                                  :output '(:string :stripped t))))

(defun resolve-secret-file (path)
  (string-trim '(#\Newline) (read-file-string (expand-home path))))

(defun resolve-secret-prompt (target &key message)
  (unless (interactive-terminal-p)
    (error 'non-interactive-prompt :target target))
  (format *query-io* "~a" (or message (format nil "Enter value for ~a: " target)))
  (force-output *query-io*)
  (read-line *query-io*))

(defun resolve-secret (spec &key target)
  "SPEC is a plist like (:from :pass :path \"ssh/id_ed25519\") or
 (:from :prompt :message \"...\"). Returns the resolved secret string."
  (let ((from (getf spec :from)))
    (with-linacs-restarts ()
      (case from
        (:pass (resolve-secret-pass (getf spec :path)))
        (:vault (resolve-secret-vault (getf spec :path)))
        (:file (resolve-secret-file (getf spec :path)))
        (:prompt (resolve-secret-prompt target :message (getf spec :message)))
        (t (error "Unknown secret source: ~a" from))))))
