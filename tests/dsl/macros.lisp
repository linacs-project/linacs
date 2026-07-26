(in-package #:linacs-tests)

(def-suite dsl-macros
  :in linacs-tests
  :description "Tests for DSL macro syntax and validation")

(in-suite dsl-macros)

(defmacro with-clean-actions (&body body)
  "Run BODY with *CURRENT-HOME-ACTIONS* bound to nil, restoring afterward."
  `(let ((linacs.core:*current-home-actions* nil))
     ,@body))

(def-test simple-file-definition ()
  "Basic file definition pushes a :copy-file action"
  (with-clean-actions
    (linacs.core:file "~/.gitconfig" :from "gitconfig")
    (is (= 1 (length linacs.core:*current-home-actions*)))
    (is (eq :copy-file (getf (first linacs.core:*current-home-actions*) :action)))
    (is (equal "~/.gitconfig" (getf (first linacs.core:*current-home-actions*) :target)))))

(def-test simple-directory-definition ()
  "Basic directory definition pushes an :ensure-dir action"
  (with-clean-actions
    (linacs.core:directory "~/.config/emacs/" :mode #o755)
    (is (= 1 (length linacs.core:*current-home-actions*)))
    (is (eq :ensure-dir (getf (first linacs.core:*current-home-actions*) :action)))))

(def-test simple-symlink-definition ()
  "Basic symlink definition pushes a :symlink action"
  (with-clean-actions
    (linacs.core:symlink "~/.emacs.d" :to "~/.config/emacs")
    (is (= 1 (length linacs.core:*current-home-actions*)))
    (is (eq :symlink (getf (first linacs.core:*current-home-actions*) :action)))))

(def-test simple-package-definition ()
  "Basic package definition pushes a :package action"
  (with-clean-actions
    (linacs.core:package :emacs :via :system)
    (is (= 1 (length linacs.core:*current-home-actions*)))
    (is (eq :package (getf (first linacs.core:*current-home-actions*) :action)))))