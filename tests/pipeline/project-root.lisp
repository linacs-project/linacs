;;;; tests/pipeline/project-root.lisp
;;;;
;;;; Tests for TODO 2.2 -- providers locating the project's files/ dir.
;;;;
;;;; Two halves of the same bug, both fixed by threading the project root
;;;; through the pipeline:
;;;;
;;;;   * *project-root* is bound while providers run, so provider-call-time
;;;;     probing (does files/<name>/ exist?) works even when linacs is
;;;;     invoked with -C from a different cwd.
;;;;
;;;;   * provider actions are stamped with :project-root, so the
;;;;     file-related executors (:copy-file, :stow) resolve their sources
;;;;     under the real project root instead of falling back to the
;;;;     invocation cwd.
;;;;
;;;; The executor tests rely on a discriminating detail: with the WRONG
;;;; root the source file/dir doesn't exist, so a :copy-file/:stow check
;;;; reports :unchanged; with the right root it reports :would-change.

(in-package #:linacs-tests)

(def-suite pipeline-project-root
  :in linacs-tests
  :description "Tests for *project-root* binding and :project-root injection on provider actions (TODO 2.2)")
(in-suite pipeline-project-root)

(defun make-temp-dir (name)
  "A fresh, existing temp directory named linacs-pr-NAME-<unixtime>/."
  (let* ((base (uiop:temporary-directory))
         (dir (merge-pathnames (format nil "linacs-pr-~a-~d/" name (get-universal-time)) base)))
    (ensure-directories-exist dir)
    dir))

(defun write-fixture-file (path content)
  (ensure-directories-exist path)
  (with-open-file (s path :direction :output :if-exists :supersede :if-does-not-exist :create)
    (write-string content s)))

(defun run-pr-project (root provider-fn)
  "Register a :pr-feature/:pr-provider pair plus a minimal home thunk that
uses it, run the pipeline in :plan-only mode against ROOT, and return the
ordered action list."
  (reset-project-registries)
  (linacs.core:define-feature :pr-feature
    :description "project-root test feature")
  (linacs.core:define-provider :pr-provider :for :pr-feature provider-fn)
  (let ((*current-home-thunk* (lambda ()
                                (setf *current-home-name* :pr-test)
                                (setf *current-home-actions* nil)
                                (list :name :pr-test
                                      :traits nil
                                      :use-features (list (list :feature :pr-feature))
                                      :actions nil))))
    (multiple-value-bind (ordered home)
        (linacs.core:run-pipeline :project-root root :execute-mode :plan-only)
      (declare (ignore home))
      ordered)))

(def-test provider-action-carries-project-root ()
  "A provider action resolved with a non-cwd project root carries that root
in its :project-root slot, so executors can resolve files/ under it."
  (let ((root (make-temp-dir "carries")))
    (unwind-protect
         (let ((ordered (run-pr-project root
                          (lambda (facts)
                            (declare (ignore facts))
                            (list (list :action :copy-file :from "f.txt" :to "~/.pr-f.txt"))))))
           (is (= 1 (length ordered)))
           (is (equal root (getf (first ordered) :project-root))))
      (uiop:delete-directory-tree root :validate t))))

(def-test project-root-bound-during-provider-execution ()
  "*project-root* is dynamically bound to the project root while the
provider function runs, so provider-call-time files/ probing works."
  (let ((root (make-temp-dir "bound"))
        (seen nil))
    (unwind-protect
         (progn
           (run-pr-project root
             (lambda (facts)
               (declare (ignore facts))
               (setf seen linacs.core:*project-root*)
               nil))
           (is (equal root seen)))
      (uiop:delete-directory-tree root :validate t))))

(def-test copy-file-executor-resolves-files-under-project-root ()
  "A provider-originated :copy-file action reads its :from source from the
project root's files/ directory at execution time -- not the invocation
cwd. :check reports :would-change only when the source resolves correctly."
  (let* ((root (make-temp-dir "copy"))
         (target (format nil "~a/out.txt" (namestring (uiop:temporary-directory)))))
    (unwind-protect
         (let ((ordered
                 (progn
                   (write-fixture-file (merge-pathnames "files/pkg/in.txt" root) "hello from files/")
                   (run-pr-project root
                     (lambda (facts)
                       (declare (ignore facts))
                       (list (list :action :copy-file :from "pkg/in.txt" :to target)))))))
           (is (= 1 (length ordered)))
           (multiple-value-bind (result status)
               (linacs.core:execute-action (first ordered) :mode :check)
             (declare (ignore status))
             (is (eq :would-change (getf result :status)))))
      (ignore-errors (delete-file target))
      (uiop:delete-directory-tree root :validate t))))

(def-test stow-executor-resolves-files-under-project-root ()
  "A provider-originated :stow action resolves its package directory under
the project root's files/ at execution time, not the invocation cwd."
  (let ((root (make-temp-dir "stow"))
        (target-root (make-temp-dir "stow-target")))
    (unwind-protect
         (let ((ordered
                 (progn
                   (write-fixture-file (merge-pathnames "files/prpkg/.config/demo/x.conf" root) "x")
                   (run-pr-project root
                     (lambda (facts)
                       (declare (ignore facts))
                        (list (list :action :stow :target "prpkg" :to (namestring target-root))))))))
           (is (= 1 (length ordered)))
           (multiple-value-bind (result status)
               (linacs.core:execute-action (first ordered) :mode :check)
             (declare (ignore status))
             (is (eq :would-change (getf result :status)))))
      (uiop:delete-directory-tree target-root :validate t)
      (uiop:delete-directory-tree root :validate t))))
