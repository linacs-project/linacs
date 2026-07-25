(in-package #:linacs-tests)

(def-suite dsl-validation
  :description "Tests for DSL validation and error handling")

(in-suite dsl-validation)

(def-test valid-file-path ()
  "Valid file paths produce a :copy-file action"
  (let ((linacs.core:*current-home-actions* nil))
    (linacs.core:file "~/.config/app/config" :from "config")
    (is (= 1 (length linacs.core:*current-home-actions*)))
    (is (eq :copy-file (getf (first linacs.core:*current-home-actions*) :action)))
    (is (equal "~/.config/app/config" (getf (first linacs.core:*current-home-actions*) :target)))))

(def-test valid-directory-path ()
  "Valid directory paths produce an :ensure-dir action"
  (let ((linacs.core:*current-home-actions* nil))
    (linacs.core:directory "~/.config/app/" :mode #o755)
    (is (= 1 (length linacs.core:*current-home-actions*)))
    (is (eq :ensure-dir (getf (first linacs.core:*current-home-actions*) :action)))))