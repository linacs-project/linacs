;;;; src/backends/filesystem/recording.lisp
;;;;
;;;; A transparent filesystem wrapper that records every operation it
;;;; forwards, in order. Used in tests to prove that a memory-backed run
;;;; never reached the real host filesystem -- RECORDING-FILESYSTEM-LOG on a
;;;; wrap of REAL-FILESYSTEM will be empty after a fully hermetic run.

(in-package :linacs.core)

(defun record-op (fs op args)
  (push (cons op args) (recording-filesystem-log fs)))

(defmethod fs-exists-p ((fs recording-filesystem) path)
  (record-op fs :fs-exists-p path)
  (fs-exists-p (recording-filesystem-wrapped fs) path))

(defmethod fs-directory-p ((fs recording-filesystem) path)
  (record-op fs :fs-directory-p path)
  (fs-directory-p (recording-filesystem-wrapped fs) path))

(defmethod fs-file-p ((fs recording-filesystem) path)
  (record-op fs :fs-file-p path)
  (fs-file-p (recording-filesystem-wrapped fs) path))

(defmethod fs-symlink-p ((fs recording-filesystem) path)
  (record-op fs :fs-symlink-p path)
  (fs-symlink-p (recording-filesystem-wrapped fs) path))

(defmethod fs-read-link ((fs recording-filesystem) path)
  (record-op fs :fs-read-link path)
  (fs-read-link (recording-filesystem-wrapped fs) path))

(defmethod fs-directory-entries ((fs recording-filesystem) path)
  (record-op fs :fs-directory-entries path)
  (fs-directory-entries (recording-filesystem-wrapped fs) path))

(defmethod fs-read-file ((fs recording-filesystem) path)
  (record-op fs :fs-read-file path)
  (fs-read-file (recording-filesystem-wrapped fs) path))

(defmethod fs-truename ((fs recording-filesystem) path)
  (record-op fs :fs-truename path)
  (fs-truename (recording-filesystem-wrapped fs) path))

(defmethod fs-file-mode ((fs recording-filesystem) path)
  (record-op fs :fs-file-mode path)
  (fs-file-mode (recording-filesystem-wrapped fs) path))

(defmethod fs-make-directory ((fs recording-filesystem) path)
  (record-op fs :fs-make-directory path)
  (fs-make-directory (recording-filesystem-wrapped fs) path))

(defmethod fs-write-file ((fs recording-filesystem) path content)
  (record-op fs :fs-write-file path)
  (fs-write-file (recording-filesystem-wrapped fs) path content))

(defmethod fs-symlink ((fs recording-filesystem) source target)
  (record-op fs :fs-symlink (list source target))
  (fs-symlink (recording-filesystem-wrapped fs) source target))

(defmethod fs-delete ((fs recording-filesystem) path)
  (record-op fs :fs-delete path)
  (fs-delete (recording-filesystem-wrapped fs) path))

(defmethod fs-rmdir ((fs recording-filesystem) path)
  (record-op fs :fs-rmdir path)
  (fs-rmdir (recording-filesystem-wrapped fs) path))

(defmethod fs-delete-directory-tree ((fs recording-filesystem) path)
  (record-op fs :fs-delete-directory-tree path)
  (fs-delete-directory-tree (recording-filesystem-wrapped fs) path))

(defmethod fs-set-mode ((fs recording-filesystem) path mode)
  (record-op fs :fs-set-mode (list path mode))
  (fs-set-mode (recording-filesystem-wrapped fs) path mode))

(defmethod fs-set-owner ((fs recording-filesystem) path owner group)
  (record-op fs :fs-set-owner (list path owner group))
  (fs-set-owner (recording-filesystem-wrapped fs) path owner group))