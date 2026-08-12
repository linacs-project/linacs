;;;; tests/executors/stow.lisp
;;;;
;;;; Tests for the :stow executor: the fold/merge/unfold algorithm, its
;;;; conflict detection (an existing real file or an unrelated symlink
;;;; blocking a path), and the :force t override (GNU stow --override
;;;; semantics) plus the interactive FORCE restart.

(in-package #:linacs-tests)

(def-suite executor-stow
  :in linacs-tests
  :description "Tests for the stow executor, including :force t conflict override and the FORCE restart")
(in-suite executor-stow)

(defun make-stow-fixture (name &key package-file)
  "A temp project with files/NAME/<PACKAGE-FILE> (a real file) and a fresh,
empty target root. Returns (values project-root target-root package-path)."
  (let* ((root (make-temp-dir (format nil "stow-~a" name)))
         (target (make-temp-dir (format nil "stow-target-~a" name)))
         (pkg-root (uiop:ensure-directory-pathname
                    (format nil "~afiles/~a/" (namestring root) name))))
    (ensure-directories-exist pkg-root)
    (if package-file
        (let ((path (merge-pathnames package-file pkg-root)))
          (write-fixture-file path "package content")
          (values (namestring root) (namestring target) (namestring path)))
        (values (namestring root) (namestring target) nil))))

(defun symlink-p (path)
  (zerop (nth-value 2 (uiop:run-program (list "test" "-L" (namestring (pathname path)))
                                        :ignore-error-status t))))

(defun readlink (path)
  (string-trim '(#\Newline) (uiop:run-program (list "readlink" (namestring (pathname path)))
                                              :output '(:string :stripped t))))

(defun read-file (path)
  (with-open-file (s path :direction :input)
    (let ((str (make-string (file-length s))))
      (read-sequence str s)
      str)))

(def-test stow-identity ()
  "Stow action has correct identity"
  (it.bese.fiveam:is (equal (linacs.core:action-identity '(:action :stow :target "fish"))
                             '(:stow . "fish"))))

(def-test stow-macro ()
  "Stow DSL macro expands to an action plist"
  (it.bese.fiveam:is (typep (linacs.core:stow "fish") 'linacs.core:action-plist)))

(def-test stow-conflict-real-file-signals ()
  "An existing real file blocking a path is a conflict, reported even in :check mode"
  (multiple-value-bind (root target pkg)
      (make-stow-fixture "conf-real" :package-file ".config/demo/x.conf")
    (declare (ignore pkg))
    (write-fixture-file (merge-pathnames ".config/demo/x.conf" (uiop:ensure-directory-pathname target))
                        "blocking")
    (let ((action `(:action :stow :target "conf-real" :project-root ,root :to ,target)))
      (it.bese.fiveam:signals linacs.core:execution-failure
        (linacs.core:execute-action action :mode :check)))))

(def-test stow-conflict-unrelated-symlink-signals ()
  "An unrelated symlink blocking a path is a conflict, reported even in :check mode"
  (multiple-value-bind (root target pkg)
      (make-stow-fixture "conf-link" :package-file ".config/demo/x.conf")
    (declare (ignore pkg))
    (let ((blocker (merge-pathnames ".config/demo/x.conf" (uiop:ensure-directory-pathname target))))
      (ensure-directories-exist blocker)
      (uiop:run-program (list "ln" "-s" "/nonexistent/elsewhere" (namestring blocker)))
      (let ((action `(:action :stow :target "conf-link" :project-root ,root :to ,target)))
        (it.bese.fiveam:signals linacs.core:execution-failure
          (linacs.core:execute-action action :mode :check))))))

(def-test stow-force-real-file-check ()
  "With :force t, a blocking real file is reported as :would-change in :check mode"
  (multiple-value-bind (root target pkg)
      (make-stow-fixture "force-check" :package-file ".config/demo/x.conf")
    (declare (ignore pkg))
    (write-fixture-file (merge-pathnames ".config/demo/x.conf" (uiop:ensure-directory-pathname target))
                        "blocking")
    (let ((action `(:action :stow :target "force-check" :project-root ,root :to ,target :force t)))
      (let ((result (linacs.core:execute-action action :mode :check)))
        (it.bese.fiveam:is (eq :would-change (getf result :status)))))))

(def-test stow-force-real-file-apply ()
  "With :force t, :apply replaces the blocking real file with a symlink to the package source"
  (multiple-value-bind (root target pkg)
      (make-stow-fixture "force-apply" :package-file ".config/demo/x.conf")
    (declare (ignore pkg))
    (let ((blocker (merge-pathnames ".config/demo/x.conf" (uiop:ensure-directory-pathname target))))
      (write-fixture-file blocker "blocking")
      (let ((action `(:action :stow :target "force-apply" :project-root ,root :to ,target :force t)))
        (let ((result (linacs.core:execute-action action :mode :apply)))
          (it.bese.fiveam:is (eq :changed (getf result :status)))
          (it.bese.fiveam:is (symlink-p blocker))
          (it.bese.fiveam:is (string= "package content" (read-file blocker))))))))

(def-test stow-force-unrelated-symlink-apply ()
  "With :force t, :apply replaces an unrelated blocking symlink"
  (multiple-value-bind (root target pkg)
      (make-stow-fixture "force-link" :package-file ".config/demo/x.conf")
    (let ((blocker (merge-pathnames ".config/demo/x.conf" (uiop:ensure-directory-pathname target))))
      (ensure-directories-exist blocker)
      (uiop:run-program (list "ln" "-s" "/nonexistent/elsewhere" (namestring blocker)))
      (let ((action `(:action :stow :target "force-link" :project-root ,root :to ,target :force t)))
        (linacs.core:execute-action action :mode :apply)
        (it.bese.fiveam:is (symlink-p blocker))
        (it.bese.fiveam:is (string= (namestring (truename pkg)) (namestring (truename blocker))))))))

(def-test stow-force-restart-resolves ()
  "The FORCE restart, offered on a conflict, re-runs the merge with force semantics"
  (multiple-value-bind (root target pkg)
      (make-stow-fixture "force-restart" :package-file ".config/demo/x.conf")
    (declare (ignore pkg))
    (let ((blocker (merge-pathnames ".config/demo/x.conf" (uiop:ensure-directory-pathname target))))
      (write-fixture-file blocker "blocking")
      (let ((action `(:action :stow :target "force-restart" :project-root ,root :to ,target)))
        (handler-bind ((linacs.core:execution-failure
                         (lambda (c) (declare (ignore c)) (invoke-restart 'linacs.core:force))))
          (let ((result (linacs.core:execute-action action :mode :apply)))
            (it.bese.fiveam:is (eq :changed (getf result :status)))
            (it.bese.fiveam:is (symlink-p blocker))
            (it.bese.fiveam:is (string= "package content" (read-file blocker)))))))))

(def-test stow-force-does-not-destroy-shared-fold ()
  "Two packages overlapping a shared directory still merge cooperatively even with :force t -- the other package's fold is not destroyed"
  (multiple-value-bind (root target pkg-a)
      (make-stow-fixture "fold-a" :package-file ".config/demo/a.conf")
    (declare (ignore pkg-a))
    (let* ((pkg-b (format nil "~afiles/fold-b/" (namestring root)))
           (b-path (merge-pathnames ".config/demo/b.conf" (uiop:ensure-directory-pathname pkg-b))))
      (write-fixture-file b-path "b content")
      (let ((action-a `(:action :stow :target "fold-a" :project-root ,root :to ,target))
            (action-b `(:action :stow :target "fold-b" :project-root ,root :to ,target :force t)))
        (linacs.core:execute-action action-a :mode :apply)
        (let ((config-dir (merge-pathnames ".config" (uiop:ensure-directory-pathname target))))
          (it.bese.fiveam:is (symlink-p config-dir)))
        (linacs.core:execute-action action-b :mode :apply)
        (let ((config-dir (merge-pathnames ".config" (uiop:ensure-directory-pathname target)))
              (a-leaf (merge-pathnames ".config/demo/a.conf" (uiop:ensure-directory-pathname target)))
              (b-leaf (merge-pathnames ".config/demo/b.conf" (uiop:ensure-directory-pathname target))))
          (it.bese.fiveam:is (not (symlink-p config-dir)))
          (it.bese.fiveam:is (string= "package content" (read-file a-leaf)))
          (it.bese.fiveam:is (string= "b content" (read-file b-leaf))))))))
