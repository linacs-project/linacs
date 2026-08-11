;;;; src/discovery.lisp
;;;;
;;;; Execution Model step 0. Loads a home project's own .lisp files by
;;;; directory convention (profiles/, features/, providers/, catalogs/,
;;;; templates/, hooks/, then home.lisp last), and third-party linacs-* ASDF
;;;; plugins by naming convention. Both run before facts are probed, so a
;;;; DEFINE-HOME body can react to facts even though its file was loaded
;;;; before any fact existed -- see src/dsl.lisp for why that's safe.
;;;;
;;;; Usage:
;;;;   Called automatically by src/cli.lisp's BOOTSTRAP on every command; not
;;;;   normally called directly. To drive it by hand (e.g. from a REPL):
;;;;
;;;;     (discover-plugins)
;;;;     (discover-project "/path/to/some/home-project")

(in-package :linacs.core)

(defparameter *conventional-directories*
  '("profiles" "features" "providers" "catalogs" "templates" "hooks")
  "Fixed set of conventional subdirectories under the project root that are
auto-loaded, in this order, before home.lisp.")

(defun %load-lisp-file (path)
  (handler-case (load path)
    (linacs-error (e) (error e))
    (error (e)
      (with-linacs-restarts
          (:on-retry (lambda () (%load-lisp-file path))
           :on-skip (lambda () (linacs.log:warn* "Skipping ~a" path) nil)
           :on-abort (lambda () (throw 'linacs-abort nil)))
        (error 'file-discovery-load-error :path path :underlying e)))))

(defun collect-lisp-files-recursively (dir)
  "Recursively collect all .lisp files under DIR, alphabetically by full
path, so authors get a predictable, low-ceremony way to sequence
registrations via filename."
  (let ((files (copy-list (uiop:directory-files dir "*.lisp"))))
    (dolist (sub (uiop:subdirectories dir))
      (setf files (append files (collect-lisp-files-recursively sub))))
    (sort files #'string< :key #'namestring)))

(defun discover-project (&optional (root "."))
  "Load every .lisp file found (recursively, alphabetically) under each of
the six conventional subdirectories of ROOT, then load ROOT/home.lisp last."
  (let ((root (uiop:ensure-directory-pathname root)))
    (catch 'linacs-abort
      (dolist (dir-name *conventional-directories*)
        (let ((dir (merge-pathnames (make-pathname :directory (list :relative dir-name)) root)))
          (when (uiop:directory-exists-p dir)
            (dolist (f (collect-lisp-files-recursively dir))
              (linacs.log:debug* "Loading ~a" f)
              (%load-lisp-file f)))))
      (let ((home-file (merge-pathnames "home.lisp" root)))
        (if (probe-file home-file)
            (%load-lisp-file home-file)
            (linacs.log:warn* "No home.lisp found under ~a" root))))))

(defun discover-plugins ()
  "Locate and load third-party ASDF systems named linacs-*, per the ASDF /
Quicklisp convention. Best-effort: scans ASDF's known source registry for
matching system names, skipping linacs and linacs/tests themselves."
  (let ((candidates '()))
    (ignore-errors
      (dolist (name (asdf:registered-systems))
      (when (and (>= (length name) 7)
                  (string= name "linacs-" :end1 7)
                  (not (string= name "linacs-tests")))
          (pushnew name candidates :test #'string=))))
    (dolist (name candidates)
      (linacs.log:info "Loading plugin system ~a" name)
      (handler-case (asdf:load-system name)
        (error (e) (linacs.log:warn* "Failed to load plugin ~a: ~a" name e))))
    candidates))

(defun discover-project-plugins (root)
  "Discover plugin ASDF systems under ROOT/plugins/*/ that match the
linacs-* naming convention, and load them.  This bridges the gap between
a user checking a plugin into their project (as a git submodule or a
plain checkout) and the ASDF discovery mechanism that expects systems
to be registered in the source registry.

Third-party plugins that are installed via Quicklisp or registered in
ASDF's source registry are handled separately by DISCOVER-PLUGINS and
don't need this path."
  (let ((plugins-dir (merge-pathnames "plugins/" (uiop:ensure-directory-pathname root))))
    (when (uiop:directory-exists-p plugins-dir)
      (dolist (sub (sort (uiop:subdirectories plugins-dir) #'string< :key #'namestring))
        (dolist (asd (uiop:directory-files sub "*.asd"))
          (let ((system-name (string-downcase (pathname-name asd))))
            (when (and (>= (length system-name) 7)
                       (string= system-name "linacs-" :end1 7))
              (linacs.log:debug* "Loading project-local plugin ~a from ~a" system-name asd)
              (handler-case
                  (progn
                    ;; Load the .asd in ASDF's package so defsystem is available,
                    ;; then load the system so its register-* forms take effect.
                    (let ((*package* (find-package :asdf-user)))
                      (load asd :verbose nil))
                    (asdf:load-system system-name))
                (error (e)
                  (linacs.log:warn* "Failed to load project-local plugin ~a: ~a"
                                    system-name e))))))))))
