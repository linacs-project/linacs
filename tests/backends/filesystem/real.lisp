;;;; tests/backends/filesystem/real.lisp
;;;;
;;;; Thin tests for the REAL-FILESYSTEM backend. Unlike the memory and
;;;; executor suites (which are hermetic), these legitimately touch the host
;;;; -- they exercise the real backend against a throwaway scratch directory
;;;; under the system temp dir.

(in-package #:linacs-tests)

(def-suite backend-filesystem-real
  :in linacs-tests
  :description "Tests for the real (host) filesystem backend")
(in-suite backend-filesystem-real)

(def-test real-write-read-roundtrip ()
  "fs-write-file / fs-read-file round-trip on the host"
  (with-scratch-dir (dir)
    (let ((path (namestring (merge-pathnames "f.txt" dir)))
          (fs (linacs.core:make-real-filesystem)))
      (linacs.core:fs-write-file fs path "hello")
      (is (string= "hello" (linacs.core:fs-read-file fs path))))))

(def-test real-mkdir-and-entries ()
  "fs-make-directory + fs-directory-entries on the host"
  (with-scratch-dir (dir)
    (let ((sub (namestring (uiop:ensure-directory-pathname
                            (merge-pathnames "a/b/" dir))))
          (fs (linacs.core:make-real-filesystem)))
      (linacs.core:fs-make-directory fs sub)
      (is (linacs.core:fs-directory-p fs sub))
      (is (member "a" (linacs.core:fs-directory-entries fs (namestring dir))
                  :test #'string=)))))

(def-test real-symlink-lifecycle ()
  "fs-symlink creates a link; predicates/read-link see it; fs-delete removes it"
  (with-scratch-dir (dir)
    (let* ((target (namestring (merge-pathnames "real.txt" dir)))
           (link (namestring (merge-pathnames "link.txt" dir)))
           (fs (linacs.core:make-real-filesystem)))
      (linacs.core:fs-write-file fs target "x")
      (linacs.core:fs-symlink fs target link)
      (is (linacs.core:fs-symlink-p fs link))
      (is (not (linacs.core:fs-symlink-p fs target)))
      (is (string= "x" (linacs.core:fs-read-file fs link)))
      (is (linacs.core:fs-delete fs link))
      (is (not (linacs.core:fs-exists-p fs link))))))

(def-test real-rmdir-and-tree ()
  "fs-rmdir refuses non-empty; fs-delete-directory-tree removes a subtree"
  (with-scratch-dir (dir)
    (let* ((tree (namestring (uiop:ensure-directory-pathname (merge-pathnames "tree/" dir))))
           (leaf (namestring (merge-pathnames "tree/x.conf" dir)))
           (fs (linacs.core:make-real-filesystem)))
      (linacs.core:fs-write-file fs leaf "x")
      (is (null (linacs.core:fs-rmdir fs tree)) "rmdir of a non-empty dir must fail")
      (linacs.core:fs-delete-directory-tree fs tree)
      (is (not (linacs.core:fs-directory-p fs tree))))))