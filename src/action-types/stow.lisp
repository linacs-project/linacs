;;;; src/action-types/stow.lisp
;;;;
;;;; The :stow executor. Re-implements GNU Stow's own algorithm natively --
;;;; no dependency on the `stow` binary. Given a package directory under
;;;; the asset root (e.g. fish/.config/fish/config.fish), it
;;;; mirrors that tree onto a target root (default ~), symlinking a whole
;;;; subtree at the highest possible level when nothing exists there yet
;;;; ("folding"), and recursing to merge file-by-file when the
;;;; corresponding target directory already exists for real. If a target
;;;; path is already a whole-directory symlink from a *different* stowed
;;;; package, it "unfolds" that symlink into a real directory holding both
;;;; packages' content, exactly like real GNU Stow does when two packages'
;;;; trees overlap.
;;;;
;;;; All filesystem access goes through the FS-* protocol (REFACTOR.org
;;;; Action 8), so the fold/merge/unfold algorithm is testable against a
;;;; hermetic MEMORY-FILESYSTEM with zero host writes.
;;;;
;;;; Usage:
;;;;   (:action :stow :target "fish")
;;;;   ;; mirrors <asset-root>/fish/** onto ~, e.g.
;;;;   ;; fish/.config/fish/config.fish -> ~/.config/fish/config.fish
;;;;
;;;;   (:action :stow :target "fish" :to "/etc/skel")   ; a different target root
;;;;   (:action :stow :target "fish-work" :from "fish") ; source dir name differs from identity
;;;;
;;;;   (:action :stow :target "fish" :force t)          ; overwrite blocking files/symlinks

(in-package :linacs.core)

(defun stow-parent-dir (path)
  (let* ((trimmed (string-right-trim "/" path))
         (pos (position #\/ trimmed :from-end t)))
    (and pos (plusp pos) (subseq trimmed 0 pos))))

(defun stow-join (dir name) (format nil "~a/~a" (string-right-trim "/" dir) name))

(defun stow-prune-empty-parents (fs path boundary)
  "After removing a symlink at PATH, walk upward removing now-empty
directories, never going at or above BOUNDARY (the stow action's own
target root). Stops naturally at the first non-empty directory."
  (let ((dir (stow-parent-dir path))
        (boundary (string-right-trim "/" boundary)))
    (loop while (and dir (> (length dir) (length boundary))
                     (fs-directory-p fs dir) (fs-rmdir fs dir))
          do (setf dir (stow-parent-dir dir)))))

(defun stow-merge (fs source target mode &optional force-p)
  "Recursively fold/merge SOURCE onto TARGET using filesystem backend FS.
Returns T if something changed (or, in :check mode, would change). Signals
EXECUTION-FAILURE on an unresolvable conflict -- an existing real file, or
a symlink to something unrelated, blocking the merge -- regardless of MODE,
since that's a static fact about the filesystem, not something :check
should hide from you. When FORCE-P is true, such a conflict is instead
resolved by deleting the blocker and replacing it with the symlink (GNU
stow --override semantics). The unfold branch -- TARGET is a symlink to
another stowed package's directory -- is never affected by FORCE-P: that is
cooperative overlap, not a conflict, and forcing it would destroy the other
package's data."
  (cond
    ;; Nothing at all where TARGET should be: fold the whole subtree into
    ;; one symlink. This is the common case for a package's own leaf
    ;; directory (e.g. ~/.config/fish, brand new).
    ((not (fs-exists-p fs target))
     (case mode
       (:check t)
       (:apply
        (let ((parent (stow-parent-dir target)))
          (when parent (fs-make-directory fs parent)))
        (fs-symlink fs source target)
        t)
       (:remove nil)))

    ;; TARGET is already a symlink.
    ((fs-symlink-p fs target)
     (let ((existing-dest (fs-read-link fs target)))
       (cond
         ;; Already points exactly at our source -- correctly stowed.
         ((equal existing-dest source)
          (case mode
            (:remove (fs-delete fs target) (stow-prune-empty-parents fs target target) t)
            (t nil)))
         ;; Points at some other directory -- almost certainly a fold from
         ;; a different stowed package sharing this path. Unfold it into a
         ;; real directory holding both trees, then continue merging.
         ((fs-directory-p fs existing-dest)
          (case mode
            (:check t)
            (:apply
             (fs-delete fs target)
             (fs-make-directory fs target)
             (dolist (name (fs-directory-entries fs existing-dest))
               (stow-merge fs (stow-join existing-dest name) (stow-join target name) :apply force-p))
             (dolist (name (fs-directory-entries fs source))
               (stow-merge fs (stow-join source name) (stow-join target name) :apply force-p))
             t)
            (:remove nil)))
         (t
          (if force-p
              (case mode
                (:check t)
                (:apply
                 (fs-delete fs target)
                 (let ((parent (stow-parent-dir target)))
                   (when parent (fs-make-directory fs parent)))
                 (fs-symlink fs source target)
                 t)
                (:remove nil))
              (error 'execution-failure :action-type :stow :target target
                     :underlying (format nil "~a is a symlink to ~a, which conflicts with stowing ~a"
                                         target existing-dest source)))))))

    ;; TARGET is a real directory: recurse, merging each of SOURCE's entries.
    ((fs-directory-p fs target)
     (let ((changed nil))
       (dolist (name (fs-directory-entries fs source))
         (when (stow-merge fs (stow-join source name) (stow-join target name) mode force-p)
           (setf changed t)))
       changed))

    ;; TARGET is a real, plain file -- a conflict, resolved by deletion and
    ;; replacement only when FORCE-P is true.
    (t
     (if force-p
         (case mode
           (:check t)
           (:apply
            (fs-delete fs target)
            (let ((parent (stow-parent-dir target)))
              (when parent (fs-make-directory fs parent)))
            (fs-symlink fs source target)
            t)
           (:remove nil))
         (error 'execution-failure :action-type :stow :target target
                :underlying (format nil "~a already exists and is not a symlink or directory; refusing to overwrite it"
                                    target))))))

(defun stow-source-dir (action fs)
  "The absolute, canonicalized path to this action's package directory
under the asset root -- always absolute so the symlinks created
remain valid regardless of the working directory at a later run."
  (let* ((asset-root (action-asset-root action))
         (abs-root (if (fs-exists-p fs asset-root)
                       (fs-truename fs asset-root)
                       (string-right-trim "/" (fs-path-string asset-root))))
         (pkg (or (getf action :from) (action-target action))))
    (string-right-trim "/" (format nil "~a/~a" abs-root pkg))))

(defun stow-merge-interactive (fs source target mode force-p)
  "Run STOW-MERGE, offering a FORCE restart that re-runs the merge with
force semantics (GNU stow --override) when a conflict is signaled. This
is the seam for the interactive menu's FORCE choice: on a conflict the
user picks FORCE instead of RETRY/SKIP/ABORT, and the merge completes by
deleting the blocker and symlinking over it. Returns STOW-MERGE's value:
T if something changed (or, in :check mode, would change)."
  (restart-case (stow-merge fs source target mode force-p)
    (force ()
      :report "Force overwrite the conflicting file/symlink"
      (stow-merge fs source target mode t))))

(defun execute-stow (action &key mode)
  (let* ((fs (context-filesystem))
         (package-name (action-target action))
         (source (stow-source-dir action fs))
         (target-root (string-right-trim "/" (expand-home (getf action :to "~"))))
         (force-p (getf action :force)))
    (case mode
      (:check (report (if (stow-merge-interactive fs source target-root :check force-p)
                          :would-change :unchanged)
                      :target package-name))
      (:apply (let ((changed (stow-merge-interactive fs source target-root :apply force-p)))
                (report (if changed :changed :unchanged) :target package-name)))
      (:remove (stow-merge fs source target-root :remove)
               (report :removed :target package-name)))))

(register-action-type :stow #'execute-stow
  :description "Symlink an asset-root package onto a target root, GNU-Stow style: fold whole directories when possible, merge file-by-file when the target already exists")