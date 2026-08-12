;;;; tests/pipeline/project-root.lisp
;;;;
;;;; Tests for TODO 2.2 -- providers locating the project's assets -- plus
;;;; the asset-root mechanism (TODO: linacs on top of dotfiles).
;;;;
;;;; Two halves of the same fix, both threaded through the pipeline:
;;;;
;;;;   * *project-root* / *asset-root* are bound while providers run, so
;;;;     provider-call-time probing (does <name>/ exist under the asset
;;;;     root?) works even when linacs is invoked with -C from a different
;;;;     cwd.
;;;;
;;;;   * provider actions are stamped with :project-root / :asset-root, so
;;;;     the file-related executors (:copy-file, :stow) resolve their
;;;;     sources under the real roots instead of falling back to the
;;;;     invocation cwd.
;;;;
;;;; The executor tests rely on a discriminating detail: with the WRONG
;;;; root the source file/dir doesn't exist, so a :copy-file/:stow check
;;;; reports :unchanged; with the right root it reports :would-change.

(in-package #:linacs-tests)

(def-suite pipeline-project-root
  :in linacs-tests
  :description "Tests for *project-root*/:project-root and *asset-root*/:asset-root threading through the pipeline (TODO 2.2 + asset-root)")
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

(defun run-pr-project (root provider-fn &key asset-root)
  "Register a :pr-feature/:pr-provider pair plus a minimal home thunk that
uses it, run the pipeline in :plan-only mode against ROOT, and return the
ordered action list. ASSET-ROOT, when given, is set on the home definition
as :asset-root."
  (reset-project-registries)
  (linacs.core:define-feature :pr-feature
    :description "project-root test feature")
  (linacs.core:define-provider :pr-provider :for :pr-feature provider-fn)
  (let ((*current-home-thunk* (lambda ()
                                (setf *current-home-name* :pr-test)
                                (setf *current-home-traits* nil)
                                (setf *current-home-use-features* nil)
                                (setf *current-home-actions* nil)
                                (list :name :pr-test
                                      :traits nil
                                      :asset-root asset-root
                                      :use-features (list (list :feature :pr-feature))
                                      :actions nil))))
    (multiple-value-bind (ordered home)
        (linacs.core:run-pipeline :project-root root :execute-mode :plan-only)
      (declare (ignore home))
      ordered)))

(def-test provider-action-carries-project-root ()
  "A provider action resolved with a non-cwd project root carries that root
in its :project-root slot (and the asset root in :asset-root), so executors
can resolve sources under them."
  (let ((root (make-temp-dir "carries")))
    (unwind-protect
         (let ((ordered (run-pr-project root
                           (lambda (facts)
                             (declare (ignore facts))
                             (list (list :action :copy-file :from "f.txt" :to "~/.pr-f.txt"))))))
           (is (= 1 (length ordered)))
           (is (equal root (getf (first ordered) :project-root)))
           (is (equal (uiop:ensure-directory-pathname root)
                      (pathname (getf (first ordered) :asset-root)))))
      (uiop:delete-directory-tree root :validate t))))

(def-test project-root-bound-during-provider-execution ()
  "*project-root* is dynamically bound to the project root while the
provider function runs, so provider-call-time asset probing works."
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

(def-test asset-root-bound-during-provider-execution ()
  "*asset-root* is dynamically bound to the absolute asset root (project
root by default) while the provider function runs."
  (let ((root (make-temp-dir "asset-bound"))
        (seen nil))
    (unwind-protect
         (progn
           (run-pr-project
            root
            (lambda (facts)
              (declare (ignore facts))
              (setf seen linacs.core:*asset-root*)
              nil))
           (is (equal (uiop:ensure-directory-pathname root)
                      (pathname seen))))
      (uiop:delete-directory-tree root :validate t))))

(def-test asset-root-resolves-parent ()
  "A home :asset-root of \"..\" lifts the asset root to the parent of the
config root -- the dotfiles-repo case where packages sit one level above a
linacs/ config subfolder."
  (let* ((base (make-temp-dir "asset-parent"))
         (config (merge-pathnames "linacs/" base)))
    (ensure-directories-exist config)
    (unwind-protect
         (let* ((seen nil)
                (ordered (run-pr-project config
                            (lambda (facts)
                              (declare (ignore facts))
                              (setf seen linacs.core:*asset-root*)
                              nil)
                            :asset-root "..")))
           (is (null ordered))
           (is (equal (truename base) (pathname seen))))
      (uiop:delete-directory-tree base :validate t))))

(def-test copy-file-executor-resolves-source-under-project-root ()
  "A provider-originated :copy-file action reads its :from source from the
project root at execution time -- not the invocation cwd. :check reports
:would-change only when the source resolves correctly."
  (let* ((root (make-temp-dir "copy"))
         (target (format nil "~a/out.txt" (namestring (uiop:temporary-directory)))))
    (unwind-protect
         (let ((ordered
                 (progn
                   (write-fixture-file (merge-pathnames "pkg/in.txt" root) "hello from root")
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

(def-test copy-file-executor-resolves-under-custom-asset-root ()
  "A provider-originated :copy-file with a home :asset-root \"..\" reads its
:from source from the parent directory at execution time."
  (let* ((base (make-temp-dir "asset-copy"))
         (config (merge-pathnames "linacs/" base))
         (target (format nil "~a/out.txt" (namestring (uiop:temporary-directory)))))
    (ensure-directories-exist config)
    (write-fixture-file (merge-pathnames "pkg/in.txt" base) "hello from parent")
    (unwind-protect
         (let ((ordered
                 (run-pr-project config
                   (lambda (facts)
                     (declare (ignore facts))
                     (list (list :action :copy-file :from "pkg/in.txt" :to target)))
                   :asset-root "..")))
           (is (= 1 (length ordered)))
           (multiple-value-bind (result status)
               (linacs.core:execute-action (first ordered) :mode :check)
             (declare (ignore status))
             (is (eq :would-change (getf result :status)))))
      (ignore-errors (delete-file target))
      (uiop:delete-directory-tree base :validate t))))

(def-test stow-executor-resolves-source-under-project-root ()
  "A provider-originated :stow action resolves its package directory under
the project root at execution time, not the invocation cwd."
  (let ((root (make-temp-dir "stow"))
        (target-root (make-temp-dir "stow-target")))
    (unwind-protect
         (let ((ordered
                 (progn
                   (write-fixture-file (merge-pathnames "prpkg/.config/demo/x.conf" root) "x")
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
