;;;; src/action-types/package-action.lisp
;;;;
;;;; The :package executor. :via :system resolves the target through the
;;;; :packages catalog for the current distro and uses dnf/pacman/apt; :via
;;;; :pip / :npm / :flatpak use the target as-is, since none of those need
;;;; distro translation. Flatpak gets its own remote-handling and
;;;; privilege-scoping logic -- see the comment at the top of this file's
;;;; Flatpak section for why :scope :user must never run under sudo.
;;;;
;;;; Usage:
;;;;     (:action :package :target :emacs :via :system)
;;;;     (:action :package :target "black" :via :pip)
;;;;     (:action :package :target "org.videolan.VLC" :via :flatpak :scope :user)

(in-package :linacs.core)

(defun distro-package-manager ()
  "Which system package manager to drive :via :system through. Delegates
to the :package-manager fact -- detected from the actual binary present
on PATH (see src/facts.lisp), rather than mapping from :os, so a distro
:os doesn't recognize by name still resolves correctly as long as it
ships one of the package managers below."
  (fact :package-manager))

(defun package-installed-p (via name)
  (case via
    (:pip (zerop (nth-value 2 (uiop:run-program (list "pip" "show" name) :ignore-error-status t))))
    (:npm (zerop (nth-value 2 (uiop:run-program (list "npm" "list" "-g" name) :ignore-error-status t))))
    (t
     (case (distro-package-manager)
       ((:dnf :yum :zypper) (zerop (nth-value 2 (uiop:run-program (list "rpm" "-q" name) :ignore-error-status t))))
       (:pacman (zerop (nth-value 2 (uiop:run-program (list "pacman" "-Q" name) :ignore-error-status t))))
       (:apt (zerop (nth-value 2 (uiop:run-program (list "dpkg" "-s" name) :ignore-error-status t))))
       (t nil)))))

(defun install-command (via name)
  (case via
    (:pip (list "pip" "install" name))
    (:npm (list "npm" "install" "-g" name))
    (t
     (case (distro-package-manager)
       (:dnf (list "dnf" "install" "-y" name))
       (:yum (list "yum" "install" "-y" name))
       (:zypper (list "zypper" "--non-interactive" "install" name))
       (:pacman (list "pacman" "-S" "--noconfirm" name))
       (:apt (list "apt-get" "install" "-y" name))
       (t (error 'execution-failure :action-type :package :target name
                 :underlying "Unknown or unsupported distribution package manager."))))))

(defun uninstall-command (via name)
  (case via
    (:pip (list "pip" "uninstall" "-y" name))
    (:npm (list "npm" "uninstall" "-g" name))
    (t
     (case (distro-package-manager)
       (:dnf (list "dnf" "remove" "-y" name))
       (:yum (list "yum" "remove" "-y" name))
       (:zypper (list "zypper" "--non-interactive" "remove" name))
       (:pacman (list "pacman" "-R" "--noconfirm" name))
       (:apt (list "apt-get" "remove" "-y" name))
       (t (error 'execution-failure :action-type :package :target name
                 :underlying "Unknown or unsupported distribution package manager."))))))

(defun resolved-package-name (action via)
  "Resolve the action's target to a concrete package name string for VIA.
String targets (e.g. \"black\" for pip, \"org.gnu.emacs\" for flatpak) are
returned as-is.  Keyword targets are looked up through the :packages catalog
with :via, falling back to string-downcase of the keyword name."
  (let ((target (action-target action)))
    (if (stringp target)
        target
        (catalog-lookup :packages target (fact :os) :via via))))

;;; --- Flatpak -----------------------------------------------------------

(defun flatpak-scope (action) (getf action :scope :system))
(defun flatpak-scope-flag (action) (if (eq (flatpak-scope action) :user) "--user" "--system"))
(defun flatpak-remote (action) (or (getf action :remote) "flathub"))
(defun flatpak-available-p () (which "flatpak"))

(defun flatpak-run (action args)
  "--user installs/removals run as the invoking user, never under sudo;
--system ones are privilege-escalated like every other :package via."
  (if (eq (flatpak-scope action) :user)
      (uiop:run-program args :output t :error-output t :ignore-error-status t)
      (run-privileged args)))

(defun flatpak-remote-present-p (action)
  (shell-ok-p (format nil "flatpak remote-list ~a --columns=name 2>/dev/null | grep -qx ~a"
                      (flatpak-scope-flag action) (flatpak-remote action))))

(defun ensure-flatpak-remote (action)
  "Adds the remote if it's missing. For the default 'flathub' remote, the
well-known repo URL is used automatically. For any other remote name, a
:remote-url must be supplied -- LINACS has no way to guess a third-party
remote's URL, and silently failing later at install time would be worse
than asking for it up front."
  (unless (flatpak-remote-present-p action)
    (let ((remote (flatpak-remote action)) (url (getf action :remote-url)))
      (cond
        ((string= remote "flathub")
         (flatpak-run action (list "flatpak" "remote-add" "--if-not-exists" (flatpak-scope-flag action)
                                   "flathub" (or url "https://flathub.org/repo/flathub.flatpakrepo"))))
        (url
         (flatpak-run action (list "flatpak" "remote-add" "--if-not-exists" (flatpak-scope-flag action) remote url)))
        (t
         (error 'execution-failure :action-type :package :target remote
                :underlying (format nil "Flatpak remote ~s is not configured, and no :remote-url was given to add it."
                                    remote)))))))

(defun flatpak-installed-p (name action)
  (shell-ok-p (format nil "flatpak list --app --columns=application ~a 2>/dev/null | grep -qx ~a"
                      (flatpak-scope-flag action) name)))

(defun execute-flatpak-package (action name &key mode)
  (let ((installed (flatpak-installed-p name action)))
    (case mode
      (:check (report (if installed :unchanged :would-change)
                      :target name :current (list :installed installed) :expected (list :installed t)))
      (:apply
       (unless installed
         (unless (flatpak-available-p)
           (error 'execution-failure :action-type :package :target name
                  :underlying "flatpak is not installed. Add (package \"flatpak\" :via :system) first."))
         (ensure-flatpak-remote action)
         (flatpak-run action (list "flatpak" "install" "-y" (flatpak-scope-flag action) (flatpak-remote action) name)))
       (report (if installed :unchanged :changed) :target name))
      (:remove
       (when installed
         (flatpak-run action (list "flatpak" "uninstall" "-y" (flatpak-scope-flag action) name)))
       (report :removed :target name)))))

;;; --- Toolbox & Podman ----------------------------------------------------
;;;
;;; Containerised CLI tool installation via toolbox or podman. The :podman
;;; via delegates to the same implementation since toolbox is a podman
;;; wrapper; a dedicated :podman handler is registered for users who prefer
;;; the lower-level name.

(defun container-name (action)
  (or (getf action :container-name) "linacs"))

(defun toolbox-container-exists-p (container)
  (shell-ok-p (format nil "toolbox list --containers 2>/dev/null | grep -Fq '~a'" container)))

(defun create-toolbox-container (container)
  (unless (toolbox-container-exists-p container)
    (linacs.log:info "Creating toolbox container '~a' …" container)
    (unless (zerop (nth-value 2
                    (uiop:run-program (list "toolbox" "create" "--assumeyes" "--container" container)
                                      :output t :error-output t :ignore-error-status t)))
      (error 'execution-failure :action-type :package :target container
             :underlying "toolbox create failed"))))

(defun toolbox-package-installed-p (container package)
  (shell-ok-p (format nil "toolbox run --container '~a' rpm -q '~a' 2>/dev/null"
                       container package)))

(defun wrapper-command (action name)
  (or (getf action :as) name))

(defun ensure-wrapper-script (cmd container)
  (let* ((dir (uiop:ensure-directory-pathname
               (format nil "~a/.local/bin/" (uiop:getenv "HOME"))))
         (path (make-pathname :name cmd :directory (pathname-directory dir))))
    (ensure-directories-exist dir)
    (unless (uiop:file-exists-p path)
      (with-open-file (f path :direction :output :if-exists :supersede)
        (format f "#!/bin/sh
exec toolbox run --container '~a' ~a \"$@\"~%"
                container cmd))
      (uiop:run-program (list "chmod" "+x" (namestring path)))
      (linacs.log:info "Created wrapper: ~a" (namestring path)))))

(defun remove-wrapper-script (cmd)
  (let ((path (format nil "~a/.local/bin/~a" (uiop:getenv "HOME") cmd)))
    (when (uiop:file-exists-p path)
      (delete-file path)
      (linacs.log:info "Removed wrapper: ~a" path))))

(defun toolbox-sudo-run (container args)
  "Run ARGS with sudo inside toolbox CONTAINER.
Tries sudo -n first (cached credentials inside the container).
Falls back to prompting for a password and using sudo -S with piped
stdin, so the password is forwarded through toolbox to the container's
sudo without needing direct terminal access."
  (let* ((cmd (list* "toolbox" "run" "--container" container "sudo" "-n" args))
         (exit (nth-value 2
                 (uiop:run-program cmd :output t :error-output t
                                   :ignore-error-status t))))
    (if (zerop exit)
        exit
        (let ((password (read-sudo-password)))
          (nth-value 2
            (uiop:run-program
              (list* "toolbox" "run" "--container" container "sudo" "-S" args)
              :input (make-string-input-stream (format nil "~a~%" password))
              :output t :error-output t
              :ignore-error-status t))))))

(defun execute-toolbox-package (action name &key mode)
  (let* ((container (container-name action))
         (cmd       (wrapper-command action name))
         (pkg       (resolved-package-name action :system)))
    (case mode
      (:check
       (let ((installed (and (toolbox-container-exists-p container)
                             (toolbox-package-installed-p container pkg))))
         (report (if installed :unchanged :would-change)
                 :target name :current (list :installed installed) :expected (list :installed t))))
      (:apply
       (create-toolbox-container container)
       (if (toolbox-package-installed-p container pkg)
           (report :unchanged :target name)
           (progn
             (linacs.log:info "Installing ~a in toolbox container '~a' …" pkg container)
             (unless (zerop (toolbox-sudo-run container (list "dnf" "install" "-y" pkg)))
               (error 'execution-failure :action-type :package :target pkg
                      :underlying "dnf install inside the toolbox container failed"))
             (ensure-wrapper-script cmd container)
             (report :changed :target name))))
      (:remove
       (when (and (toolbox-container-exists-p container)
                  (toolbox-package-installed-p container pkg))
         (linacs.log:info "Removing ~a from toolbox container '~a' …" pkg container)
         (unless (zerop (toolbox-sudo-run container (list "dnf" "remove" "-y" pkg)))
           (error 'execution-failure :action-type :package :target pkg
                  :underlying "dnf remove inside the toolbox container failed")))
       (remove-wrapper-script cmd)
       (report :removed :target name)))))

;;; --- AppImage ------------------------------------------------------------

(defun file-executable-p (path)
  "Check if the file at PATH exists and is executable."
  (and (uiop:file-exists-p path)
       (shell-ok-p (format nil "test -x ~a" path))))

(defun appimage-default-path (target)
  (let ((home (uiop:getenv "HOME")))
    (format nil "~a/.local/bin/~a" home (string-downcase (string target)))))

(defun execute-appimage-package (action name &key mode)
  "Minimal AppImage handler.  Ensures the target path exists and is
executable.  Download or build logic (e.g. from GitHub releases) is
expected to be provided by an external plugin."
  (let* ((target (action-target action))
         (path   (if (stringp target) target (appimage-default-path target)))
         (exists (uiop:file-exists-p path)))
    (case mode
      (:check
       (report (if (file-executable-p path)
                   :unchanged :would-change)
               :target name
               :current (list :installed (file-executable-p path))
               :expected (list :installed t)))
      (:apply
       (if (file-executable-p path)
           (report :unchanged :target name)
           (linacs.log:warn* "AppImage ~a not found at ~a; download or place it there manually."
                            name path)))
      (:remove
       (when exists
         (delete-file path)
         (linacs.log:info "Removed AppImage: ~a" path))
       (report :removed :target name)))))

;;; --- pip & npm ------------------------------------------------------------

(defun execute-pip-package (action name &key mode)
  (let ((installed (package-installed-p :pip name)))
    (case mode
      (:check (report (if installed :unchanged :would-change)
                      :target name :current (list :installed installed) :expected (list :installed t)))
      (:apply
       (unless installed
         (uiop:run-program (install-command :pip name) :output t :error-output t
                           :ignore-error-status t))
       (report (if installed :unchanged :changed) :target name))
      (:remove
       (when installed
         (uiop:run-program (uninstall-command :pip name) :output t :error-output t
                           :ignore-error-status t))
       (report :removed :target name)))))

(defun execute-npm-package (action name &key mode)
  (let ((installed (package-installed-p :npm name)))
    (case mode
      (:check (report (if installed :unchanged :would-change)
                      :target name :current (list :installed installed) :expected (list :installed t)))
      (:apply
       (unless installed
         (uiop:run-program (install-command :npm name) :output t :error-output t
                           :ignore-error-status t))
       (report (if installed :unchanged :changed) :target name))
      (:remove
       (when installed
         (uiop:run-program (uninstall-command :npm name) :output t :error-output t
                           :ignore-error-status t))
       (report :removed :target name)))))

;;; --- System package manager (:via :system) --------------------------------

(defun execute-system-package (action name &key mode)
  (let ((installed (package-installed-p :system name)))
    (case mode
      (:check (report (if installed :unchanged :would-change)
                      :target name :current (list :installed installed) :expected (list :installed t)))
      (:apply
       (unless installed
         (run-privileged (install-command :system name)))
       (report (if installed :unchanged :changed) :target name))
      (:remove
       (when installed (run-privileged (uninstall-command :system name)))
       (report :removed :target name)))))

;;; --- Dispatch ------------------------------------------------------------
;;;
;;; :package :via dispatch goes through the package-backend protocol
;;; (src/backends/packages/). Built-in backends for :system / :pip / :npm /
;;; :flatpak / :toolbox / :podman / :appimage are registered in
;;; src/backends/packages/backends.lisp, each wrapping the executor functions
;;; above; plugins register custom :via ecosystems (e.g. :toolbox, :rpm-ostree)
;;; the same way with REGISTER-PACKAGE-BACKEND. Unknown :via values fall back
;;; to the :system backend.

(defun execute-package (action &key mode)
  (let* ((via (or (getf action :via)
                  (resolve-package-via action)))
         (name (resolved-package-name action via))
         (backend (or (find-package-backend via)
                      (find-package-backend :system))))
    (execute-package-backend backend action name :mode mode)))

(register-action-type :package #'execute-package
  :description "Install a package via the system package manager, pip, npm, Flatpak, toolbox, podman, or AppImage"
  :identity (lambda (a) (list* :package (getf a :via) (getf a :target))))
