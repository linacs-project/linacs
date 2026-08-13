(in-package #:linacs-tests)

(def-suite cli-init
  :in linacs-tests
  :description "Tests for `linacs init` scaffolding")
(in-suite cli-init)

(defun file-contents (path)
  "Contents of PATH as a string, or NIL when absent."
  (and (probe-file path) (uiop:read-file-string path)))

(defun init-opts (root &key example)
  (linacs.core:make-cli-opts :root root :example example))

(def-test init-plain-creates-conventional-dirs ()
  "Plain init creates the six conventional directories."
  (with-scratch-dir (root)
    (linacs.core:cmd-init (init-opts root))
    (dolist (d '("profiles" "features" "providers" "catalogs" "templates" "hooks"))
      (is (uiop:directory-exists-p (merge-pathnames d root))
          "expected conventional dir ~a under ~a" d root))))

(def-test init-plain-writes-home-lisp ()
  "Plain init writes a minimal home.lisp."
  (with-scratch-dir (root)
    (linacs.core:cmd-init (init-opts root))
    (let* ((home (merge-pathnames "home.lisp" root))
           (content (file-contents home)))
      (is (probe-file home) "home.lisp should be written")
      (is (and content (search "define-home" content))
          "home.lisp should contain define-home, got ~s" content))))

(def-test init-does-not-clobber-existing-home-lisp ()
  "Plain init keeps an existing home.lisp untouched."
  (with-scratch-dir (root)
    (let ((home (merge-pathnames "home.lisp" root)))
      (ensure-directories-exist (merge-pathnames "profiles/" root))
      (with-open-file (s home :direction :output :if-exists :supersede)
        (write-string "(define-home my-home)" s))
      (linacs.core:cmd-init (init-opts root))
      (is (string= "(define-home my-home)" (file-contents home))
          "existing home.lisp must not be clobbered"))))

(def-test init-example-seeds-shell-feature ()
  "--example seeds the user-manual §2 :shell example project."
  (with-scratch-dir (root)
    (linacs.core:cmd-init (init-opts root :example t))
(dolist (f '("features/shell.lisp" "providers/shell.lisp"
                 "catalogs/packages.lisp" "bashrc" "home.lisp"))
      (is (probe-file (merge-pathnames f root)) "missing seeded file ~a" f))
    (let ((home (file-contents (merge-pathnames "home.lisp" root)))
          (prov (file-contents (merge-pathnames "providers/shell.lisp" root))))
      (is (and home (search "(use-feature :shell)" home))
          "example home.lisp should pull in the shell feature")
      (is (and prov (search "define-provider :bash :for :shell" prov))
          "example provider should define :bash for :shell"))))

(def-test init-example-is-idempotent ()
  "Re-running init --example keeps the already-seeded files."
  (with-scratch-dir (root)
    (linacs.core:cmd-init (init-opts root :example t))
    (let ((bashrc (merge-pathnames "bashrc" root)))
      (with-open-file (s bashrc :direction :output :if-exists :supersede)
        (write-line "## user customised" s))
      (linacs.core:cmd-init (init-opts root :example t))
      (let ((content (file-contents bashrc)))
        (is (and content (search "user customised" content))
            "re-running init must not overwrite an existing bashrc")))))

(def-test init-example-project-loads-under-linacs-api ()
  "A bare home.lisp (no in-package) produced by init loads as a project:
discovery reads project files in :linacs.api, so define-home resolves."
  (reset-project-registries)
  (with-scratch-dir (root)
    (linacs.core:cmd-init (init-opts root :example t))
    (linacs.core:discover-project root)
    (let ((thunk (symbol-value (find-symbol "*CURRENT-HOME-THUNK*" :linacs.core))))
      (is (not (null thunk))
          "discovery should capture the define-home thunk from a bare home.lisp")
      (let ((home (funcall thunk)))
        (is (string= (symbol-name (getf home :name)) "MY-HOME")
            "home name should be my-home")
        (is (= 1 (length (getf home :use-features)))
            "example home should use the :shell feature")))))