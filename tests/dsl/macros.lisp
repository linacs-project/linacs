(in-package #:linacs-tests)

(def-suite dsl-macros
  :description "Tests for DSL macro syntax and validation")

(def-test simple-file-definition ()
  "Basic file definition works correctly"
  (it.bese.fiveam:is (typep (linacs.core:file "~/.gitconfig" :from "gitconfig") 'linacs.core:action-plist)))

(def-test simple-directory-definition ()
  "Basic directory definition works correctly"
  (it.bese.fiveam:is (typep (linacs.core:directory "~/.config/emacs/" :from "emacs" :mode #o755) 'linacs.core:action-plist)))

(def-test simple-symlink-definition ()
  "Basic symlink definition works correctly"
  (it.bese.fiveam:is (typep (linacs.core:symlink "~/.emacs.d" :to "~/.config/emacs") 'linacs.core:action-plist)))

(def-test simple-package-definition ()
  "Basic package definition works correctly"
  (it.bese.fiveam:is (typep (linacs.core:package :emacs :via :system) 'linacs.core:action-plist)))