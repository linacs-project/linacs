;;;; tests/backends/filesystem/memory.lisp
;;;;
;;;; Semantics tests for the hermetic MEMORY-FILESYSTEM backend. These
;;;; never touch the host filesystem -- construction and fixtures use the
;;;; same FS-* generics the executors use, all on virtual absolute paths.

(in-package #:linacs-tests)

(def-suite backend-filesystem-memory
  :in linacs-tests
  :description "Semantics tests for the in-memory filesystem backend")
(in-suite backend-filesystem-memory)

(defun mem (path &key (root "/tmp/memfs"))
  (format nil "~a~a" root path))

(def-test mem-canonical-path ()
  "fs-canonical-path collapses slashes, dots, and .. segments"
  (is (string= "/a/b/c" (linacs.core:fs-canonical-path "/a//b/./c")))
  (is (string= "/b" (linacs.core:fs-canonical-path "/a/../b")))
  (is (string= "/a/b" (linacs.core:fs-canonical-path "/a/b/")))
  (is (string= "/" (linacs.core:fs-canonical-path "/"))))

(def-test mem-mkdir-recursive ()
  "fs-make-directory creates the whole ancestor chain"
  (let ((fs (linacs.core:make-memory-filesystem)))
    (linacs.core:fs-make-directory fs (mem "/a/b/c"))
    (is (linacs.core:fs-directory-p fs (mem "/a/b/c")))
    (is (linacs.core:fs-directory-p fs (mem "/a/b")))
    (is (linacs.core:fs-directory-p fs (mem "/a")))
    (is (not (linacs.core:fs-file-p fs (mem "/a/b/c"))))))

(def-test mem-write-file-creates-parents ()
  "fs-write-file creates its parent directories"
  (let ((fs (linacs.core:make-memory-filesystem)))
    (linacs.core:fs-write-file fs (mem "/pkg/.config/demo/x.conf") "content")
    (is (string= "content" (linacs.core:fs-read-file fs (mem "/pkg/.config/demo/x.conf"))))
    (is (linacs.core:fs-directory-p fs (mem "/pkg/.config/demo")))
    (is (linacs.core:fs-file-p fs (mem "/pkg/.config/demo/x.conf")))))

(def-test mem-write-file-overwrites ()
  "fs-write-file supersedes existing content"
  (let ((fs (linacs.core:make-memory-filesystem)))
    (linacs.core:fs-write-file fs (mem "/a") "one")
    (linacs.core:fs-write-file fs (mem "/a") "two")
    (is (string= "two" (linacs.core:fs-read-file fs (mem "/a"))))))

(def-test mem-missing-file-reads-nil ()
  "fs-read-file returns NIL for a missing path"
  (let ((fs (linacs.core:make-memory-filesystem)))
    (is (null (linacs.core:fs-read-file fs (mem "/nope"))))
    (is (not (linacs.core:fs-exists-p fs (mem "/nope"))))))

(def-test mem-symlink-and-follow ()
  "fs-symlink creates a resolvable link; predicates follow it"
  (let ((fs (linacs.core:make-memory-filesystem)))
    (linacs.core:fs-write-file fs (mem "/real/target.txt") "hello")
    (linacs.core:fs-symlink fs (mem "/real/target.txt") (mem "/link"))
    (is (linacs.core:fs-symlink-p fs (mem "/link")))
    (is (string= (mem "/real/target.txt") (linacs.core:fs-read-link fs (mem "/link"))))
    (is (linacs.core:fs-file-p fs (mem "/link")))
    (is (null (linacs.core:fs-directory-p fs (mem "/link"))))
    (is (string= "hello" (linacs.core:fs-read-file fs (mem "/link"))))
    (is (string= (mem "/real/target.txt") (linacs.core:fs-truename fs (mem "/link"))))))

(def-test mem-broken-symlink-exists ()
  "A dangling symlink still counts as existing"
  (let ((fs (linacs.core:make-memory-filesystem)))
    (linacs.core:fs-symlink fs "/gone/away" (mem "/broken"))
    (is (linacs.core:fs-exists-p fs (mem "/broken")))
    (is (linacs.core:fs-symlink-p fs (mem "/broken")))
    (is (null (linacs.core:fs-file-p fs (mem "/broken"))))
    (is (null (linacs.core:fs-read-file fs (mem "/broken"))))))

(def-test mem-directory-entries-sorted ()
  "fs-directory-entries lists immediate children, sorted"
  (let ((fs (linacs.core:make-memory-filesystem)))
    (linacs.core:fs-write-file fs (mem "/d/b") "b")
    (linacs.core:fs-write-file fs (mem "/d/a") "a")
    (linacs.core:fs-write-file fs (mem "/d/sub/c") "c")
    (linacs.core:fs-make-directory fs (mem "/d/empty"))
    (is (equal '("a" "b" "empty" "sub")
               (linacs.core:fs-directory-entries fs (mem "/d"))))
    (is (null (linacs.core:fs-directory-entries fs (mem "/d/empty"))))
    (is (null (linacs.core:fs-directory-entries fs (mem "/missing"))))))

(def-test mem-delete-file ()
  "fs-delete removes a file"
  (let ((fs (linacs.core:make-memory-filesystem)))
    (linacs.core:fs-write-file fs (mem "/f") "x")
    (is (linacs.core:fs-delete fs (mem "/f")))
    (is (not (linacs.core:fs-exists-p fs (mem "/f"))))
    (is (linacs.core:fs-delete fs (mem "/f")) "deleting an absent file is a no-op")))

(def-test mem-rmdir-only-empty ()
  "fs-rmdir succeeds only on empty directories"
  (let ((fs (linacs.core:make-memory-filesystem)))
    (linacs.core:fs-make-directory fs (mem "/empty"))
    (linacs.core:fs-write-file fs (mem "/nonempty/file") "x")
    (is (null (linacs.core:fs-rmdir fs (mem "/nonempty"))))
    (is (linacs.core:fs-rmdir fs (mem "/empty")))
    (is (not (linacs.core:fs-exists-p fs (mem "/empty"))))))

(def-test mem-delete-directory-tree ()
  "fs-delete-directory-tree removes a whole subtree"
  (let ((fs (linacs.core:make-memory-filesystem)))
    (linacs.core:fs-write-file fs (mem "/t/a/b") "b")
    (linacs.core:fs-write-file fs (mem "/t/c") "c")
    (linacs.core:fs-delete-directory-tree fs (mem "/t"))
    (is (not (linacs.core:fs-exists-p fs (mem "/t"))))
    (is (not (linacs.core:fs-exists-p fs (mem "/t/a"))))
    (linacs.core:fs-write-file fs (mem "/keep") "k")
    (is (string= "k" (linacs.core:fs-read-file fs (mem "/keep"))))))

(def-test mem-mode-and-owner ()
  "fs-set-mode / fs-set-owner record metadata"
  (let ((fs (linacs.core:make-memory-filesystem)))
    (linacs.core:fs-write-file fs (mem "/f") "x")
    (linacs.core:fs-set-mode fs (mem "/f") #o600)
    (is (= #o600 (linacs.core:fs-file-mode fs (mem "/f"))))
    (linacs.core:fs-set-owner fs (mem "/f") "user" "group")
    (linacs.core:fs-set-mode fs (mem "/missing") #o644)
    (is (null (linacs.core:fs-file-mode fs (mem "/missing"))))))