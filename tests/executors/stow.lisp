;;;; tests/executors/stow.lisp
;;;;
;;;; Tests for the :stow executor: the fold/merge/unfold algorithm, its
;;;; conflict detection (an existing real file or an unrelated symlink
;;;; blocking a path), and the :force t override (GNU stow --override
;;;; semantics) plus the interactive FORCE restart.
;;;;
;;;; These run entirely against a hermetic MEMORY-FILESYSTEM (REFACTOR.org
;;;; Action 8) -- zero host writes: source trees and target roots live in
;;;; memory, built with the same FS-* generics the executor uses.

(in-package #:linacs-tests)

(def-suite executor-stow
  :in linacs-tests
  :description "Tests for the stow executor (memory-filesystem backed), including :force t conflict override and the FORCE restart")
(in-suite executor-stow)

(defun make-mem-stow-fixture (name &key package-file)
  "A memory project with NAME/<PACKAGE-FILE> (a real file) and a fresh,
empty but existing target root (like a real home directory), so folding
happens at the package's directory level, not at the whole target root.
Returns (values fs project-root target-root)."
  (let ((fs (linacs.core:make-memory-filesystem))
        (root "/tmp/memstow")
        (target "/memstow-target"))
    (when package-file
      (linacs.core:fs-write-file fs (format nil "~a/~a/~a" root name package-file)
                                 "package content"))
    (linacs.core:fs-make-directory fs target)
    (values fs root target)))

(defun run-mem-stow (action fs &key (mode :apply))
  "Execute ACTION against MEMORY-FILESYSTEM FS with a fresh execution
context, so the executor's CONTEXT-FILESYSTEM resolves to FS."
  (linacs.core:execute-action action :mode mode
                              :context (linacs.core:make-execution-context
                                        :filesystem fs)))

(def-test stow-identity ()
  "Stow action has correct identity"
  (it.bese.fiveam:is (equal (linacs.core:action-identity '(:action :stow :target "fish"))
                             '(:stow . "fish"))))

(def-test stow-macro ()
  "Stow DSL macro expands to an action plist"
  (it.bese.fiveam:is (typep (linacs.core:stow "fish") 'linacs.core:action-plist)))

(def-test stow-conflict-real-file-signals ()
  "An existing real file blocking a path is a conflict, reported even in :check mode"
  (multiple-value-bind (fs root target)
      (make-mem-stow-fixture "conf-real" :package-file ".config/demo/x.conf")
    (linacs.core:fs-write-file fs (format nil "~a/.config/demo/x.conf" target) "blocking")
    (it.bese.fiveam:signals linacs.core:execution-failure
      (run-mem-stow `(:action :stow :target "conf-real" :project-root ,root :to ,target)
                    fs :mode :check))))

(def-test stow-conflict-unrelated-symlink-signals ()
  "An unrelated symlink blocking a path is a conflict, reported even in :check mode"
  (multiple-value-bind (fs root target)
      (make-mem-stow-fixture "conf-link" :package-file ".config/demo/x.conf")
    (linacs.core:fs-symlink fs "/nonexistent/elsewhere"
                            (format nil "~a/.config/demo/x.conf" target))
    (it.bese.fiveam:signals linacs.core:execution-failure
      (run-mem-stow `(:action :stow :target "conf-link" :project-root ,root :to ,target)
                    fs :mode :check))))

(def-test stow-force-real-file-check ()
  "With :force t, a blocking real file is reported as :would-change in :check mode"
  (multiple-value-bind (fs root target)
      (make-mem-stow-fixture "force-check" :package-file ".config/demo/x.conf")
    (linacs.core:fs-write-file fs (format nil "~a/.config/demo/x.conf" target) "blocking")
    (let* ((result (run-mem-stow `(:action :stow :target "force-check"
                                           :project-root ,root :to ,target :force t)
                                 fs :mode :check))
           (status (getf result :status)))
      (it.bese.fiveam:is (eq :would-change status)))))

(def-test stow-force-real-file-apply ()
  "With :force t, :apply replaces the blocking real file with a symlink to the package source"
  (multiple-value-bind (fs root target)
      (make-mem-stow-fixture "force-apply" :package-file ".config/demo/x.conf")
    (let ((blocker (format nil "~a/.config/demo/x.conf" target))
          (leaf-source (format nil "/tmp/memstow/force-apply/.config/demo/x.conf")))
      (linacs.core:fs-write-file fs blocker "blocking")
      (let* ((result (run-mem-stow `(:action :stow :target "force-apply"
                                             :project-root ,root :to ,target :force t)
                                   fs :mode :apply))
             (status (getf result :status)))
        (it.bese.fiveam:is (eq :changed status))
        (it.bese.fiveam:is (linacs.core:fs-symlink-p fs blocker))
        (it.bese.fiveam:is (string= "package content" (linacs.core:fs-read-file fs blocker)))
        (it.bese.fiveam:is (equal leaf-source (linacs.core:fs-read-link fs blocker)))))))

(def-test stow-force-unrelated-symlink-apply ()
  "With :force t, :apply replaces an unrelated blocking symlink"
  (multiple-value-bind (fs root target)
      (make-mem-stow-fixture "force-link" :package-file ".config/demo/x.conf")
    (let ((blocker (format nil "~a/.config/demo/x.conf" target)))
      (linacs.core:fs-symlink fs "/nonexistent/elsewhere" blocker)
      (run-mem-stow `(:action :stow :target "force-link" :project-root ,root :to ,target :force t)
                    fs :mode :apply)
      (it.bese.fiveam:is (linacs.core:fs-symlink-p fs blocker))
      (it.bese.fiveam:is (equal (format nil "/tmp/memstow/force-link/.config/demo/x.conf")
                                (linacs.core:fs-read-link fs blocker))))))

(def-test stow-force-restart-resolves ()
  "The FORCE restart, offered on a conflict, re-runs the merge with force semantics"
  (multiple-value-bind (fs root target)
      (make-mem-stow-fixture "force-restart" :package-file ".config/demo/x.conf")
    (let ((blocker (format nil "~a/.config/demo/x.conf" target)))
      (linacs.core:fs-write-file fs blocker "blocking")
      (handler-bind ((linacs.core:execution-failure
                       (lambda (c) (declare (ignore c)) (invoke-restart 'linacs.core:force))))
        (let* ((result (run-mem-stow `(:action :stow :target "force-restart"
                                               :project-root ,root :to ,target)
                                     fs :mode :apply))
               (status (getf result :status)))
          (it.bese.fiveam:is (eq :changed status))
          (it.bese.fiveam:is (linacs.core:fs-symlink-p fs blocker))
          (it.bese.fiveam:is (string= "package content" (linacs.core:fs-read-file fs blocker))))))))

(def-test stow-force-does-not-destroy-shared-fold ()
  "Two packages overlapping a shared directory still merge cooperatively even with :force t -- the other package's fold is not destroyed"
  (multiple-value-bind (fs root target)
      (make-mem-stow-fixture "fold-a" :package-file ".config/demo/a.conf")
    (declare (ignore root))
    (linacs.core:fs-write-file fs "/tmp/memstow/fold-b/.config/demo/b.conf" "b content")
    (let ((config-dir (format nil "~a/.config" target))
          (a-leaf (format nil "~a/.config/demo/a.conf" target))
          (b-leaf (format nil "~a/.config/demo/b.conf" target)))
      (run-mem-stow `(:action :stow :target "fold-a" :project-root "/tmp/memstow" :to ,target)
                    fs :mode :apply)
      (it.bese.fiveam:is (linacs.core:fs-symlink-p fs config-dir)
                         "first package folds ~~/.config to a symlink")
      (run-mem-stow `(:action :stow :target "fold-b" :project-root "/tmp/memstow" :to ,target :force t)
                    fs :mode :apply)
      (it.bese.fiveam:is (not (linacs.core:fs-symlink-p fs config-dir))
                         "second package unfolds the shared dir into a real directory")
      (it.bese.fiveam:is (string= "package content" (linacs.core:fs-read-file fs a-leaf)))
      (it.bese.fiveam:is (string= "b content" (linacs.core:fs-read-file fs b-leaf))))))

(def-test stow-resolves-under-custom-asset-root ()
  "A :stow action carrying an explicit :asset-root resolves its package
directory under that root (e.g. a dotfiles repo root above the config
subfolder), not the project root or any files/ directory."
  (let ((fs (linacs.core:make-memory-filesystem))
        (root "/tmp/asset-stow/proj")
        (assets "/tmp/asset-stow/pkgs")
        (target "/memic-asset-target"))
    (linacs.core:fs-write-file fs (format nil "~a/assetpkg/.config/demo/x.conf" assets)
                               "asset content")
    (let* ((result (run-mem-stow `(:action :stow :target "assetpkg"
                                           :project-root ,root
                                           :asset-root ,assets
                                           :to ,target)
                                 fs :mode :apply))
           (leaf (format nil "~a/.config/demo/x.conf" target)))
      (it.bese.fiveam:is (eq :changed (getf result :status)))
      (it.bese.fiveam:is (string= "asset content" (linacs.core:fs-read-file fs leaf))))))