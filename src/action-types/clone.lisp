;;;; src/action-types/clone.lisp
;;;;
;;;; The :clone executor. Ensures a git repository is checked out at
;;;; :target, cloning it if it isn't there yet. Unlike a hand-rolled
;;;; :command, this actually looks at real state on repeat runs -- not
;;;; just "does the directory exist" -- by checking the checked-out
;;;; repo's `origin` remote against the declared :url:
;;;;
;;;;   - target missing               -> clone it (:changed)
;;;;   - target exists, matching repo -> :unchanged
;;;;   - target exists, NOT a git repo -> EXECUTION-FAILURE (never silently
;;;;     clone over or delete something that isn't recognizably ours,
;;;;     same conflict-detection philosophy as :stow)
;;;;   - target exists, a git repo, but origin doesn't match :url
;;;;     -> EXECUTION-FAILURE (a real, contradictory state on disk; not
;;;;     something to silently re-point or re-clone over)
;;;;
;;;; :branch drift (repo exists, origin matches, but a different branch is
;;;; currently checked out) is reported via linacs.log:warn* only -- LINACS never
;;;; auto-switches branches, since that could discard a dirty working tree.
;;;; :depth only affects the initial clone; it's not re-verified afterward
;;;; (git doesn't cheaply expose "was this a shallow clone of depth N").
;;;;
;;;; Requires the `git` binary on PATH. Never escalates for the clone
;;;; itself (you're cloning into your own directories); :remove falls back
;;;; to a privileged `rm -rf` only if the plain delete fails, same as
;;;; every other filesystem-removing executor.
;;;;
;;;; Usage:
;;;;     (:action :clone :target "~/.dotfiles" :url "https://example.com/dotfiles.git")
;;;;     (:action :clone :target "~/.cache/linacs/krohnkite" :url "https://github.com/esjeon/krohnkite.git"
;;;;                     :branch "main" :depth 1)

(in-package :linacs.core)

(defun clone-target-path (action)
  (expand-home (action-target action)))

(defun clone-git-repo-p (path)
  "T if PATH exists and is the root of a git working tree."
  (and (uiop:directory-exists-p (uiop:ensure-directory-pathname path))
       (ignore-errors
         (zerop (nth-value 2 (uiop:run-program (list "git" "-C" path "rev-parse" "--is-inside-work-tree")
                                               :output nil :error-output nil :ignore-error-status t))))))

(defun clone-remote-url (path)
  "The 'origin' remote URL currently configured at PATH, or NIL."
  (let ((out (ignore-errors
               (string-trim '(#\Newline)
                            (uiop:run-program (list "git" "-C" path "remote" "get-url" "origin")
                                              :output '(:string :stripped t))))))
    (and out (plusp (length out)) out)))

(defun clone-current-branch (path)
  "The currently checked-out branch name at PATH, or NIL (e.g. detached HEAD)."
  (let ((out (ignore-errors
               (string-trim '(#\Newline)
                            (uiop:run-program (list "git" "-C" path "rev-parse" "--abbrev-ref" "HEAD")
                                              :output '(:string :stripped t))))))
    (and out (plusp (length out)) (not (equal out "HEAD")) out)))

(defun clone-normalize-url (url)
  "Strip a trailing slash and/or trailing .git so equivalent URL spellings
compare equal."
  (let ((u (string-right-trim "/" (or url ""))))
    (if (and (>= (length u) 4) (string= (subseq u (- (length u) 4)) ".git"))
        (subseq u 0 (- (length u) 4))
        u)))

(defun clone-check-state (action)
  "Returns (values EXISTS REPO-P URL-OK CURRENT-URL) for ACTION's target,
signalling EXECUTION-FAILURE on an unresolvable conflict: something
already at :target that isn't recognizably our clone."
  (let* ((target (clone-target-path action))
         (url (getf action :url))
         (exists (uiop:directory-exists-p (uiop:ensure-directory-pathname target)))
         (repo-p (and exists (clone-git-repo-p target))))
    (when (and exists (not repo-p))
      (error 'execution-failure :action-type :clone :target target
             :underlying (format nil "~a already exists and is not a git repository; refusing to clone over it" target)))
    (let* ((current-url (and repo-p (clone-remote-url target)))
           (url-ok (or (not repo-p) (equal (clone-normalize-url url) (clone-normalize-url current-url)))))
      (unless url-ok
        (error 'execution-failure :action-type :clone :target target
               :underlying (format nil "~a's origin remote (~a) does not match the declared :url (~a)"
                                   target current-url url)))
      (values exists repo-p url-ok current-url))))

(defun clone-warn-branch-drift (action target repo-p)
  (let ((branch (getf action :branch)))
    (when (and repo-p branch)
      (let ((current (clone-current-branch target)))
        (when (and current (not (equal current branch)))
          (linacs.log:warn* "~a is on branch ~a, not the declared ~a; not switching automatically."
                            target current branch))))))

(defun clone-run (action target)
  (let ((parent (uiop:pathname-directory-pathname (uiop:ensure-directory-pathname target))))
    (ensure-directories-with-escalation parent))
  (uiop:run-program
   (append (list "git" "clone")
           (when (getf action :depth) (list "--depth" (format nil "~d" (getf action :depth))))
           (when (getf action :branch) (list "--branch" (getf action :branch)))
           (list (getf action :url) target))
   :output t :error-output t))

(defun execute-clone (action &key mode)
  (let* ((target (clone-target-path action)))
    (multiple-value-bind (exists repo-p) (clone-check-state action)
      (let ((needed (not repo-p)))
        (case mode
          (:check
           (clone-warn-branch-drift action target repo-p)
           (report (if needed :would-change :unchanged) :target target))
          (:apply
           (clone-warn-branch-drift action target repo-p)
           (when needed (clone-run action target))
           (report (if needed :changed :unchanged) :target target))
          (:remove
           (when exists
             (handler-case (uiop:delete-directory-tree (uiop:ensure-directory-pathname target) :validate t)
               (error () (run-privileged (list "rm" "-rf" target)))))
           (report :removed :target target)))))))

(register-action-type
    :clone #'execute-clone
    :description "Ensure a git repository is cloned at :target, checking the actual origin remote on repeat runs rather than just presence")
