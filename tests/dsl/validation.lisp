(in-package #:linacs-tests)

(def-suite dsl-validation
  :description "Tests for DSL validation and error handling")

(def-test valid-file-path ()
  "Valid file paths are accepted"
  (it.bese.fiveam:is (typep (linacs.core:file "~/.config/app/config" :from "config") 'linacs.core:action-plist)))

(def-test valid-directory-path ()
  "Valid directory paths are accepted"
  (it.bese.fiveam:is (typep (linacs.core:directory "~/.config/app/" :mode #o755) 'linacs.core:action-plist)))