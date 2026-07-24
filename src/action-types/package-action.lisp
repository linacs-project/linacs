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

(defun resolved-package-name (action)
  (let ((via (getf action :via :system))
        (target (action-target action)))
    (if (eq via :system)
        (catalog-lookup :packages target (fact :os))
        (if (stringp target) target (string-downcase (symbol-name target))))))

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
      (:check (report (if installed :unchanged :would-change) :target name))
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

;;; --- Via-handler registry ------------------------------------------------
;;;
;;; Plugins register custom dispatch logic for new :via values (e.g.
;;; :toolbox, :rpm-ostree) without modifying core.  A handler receives
;;; (ACTION NAME &KEY MODE) where NAME is already resolved to a string.

(defvar *package-via-handlers* (make-hash-table :test 'eq)
  "Maps via keyword → handler function.  Handler: (action name &key mode)")

(defun register-package-via-handler (via handler)
  "Register HANDLER for :via VIA."
  (setf (gethash via *package-via-handlers*) handler))

(defun find-package-via-handler (via)
  "Look up a handler for :via VIA.  Returns the handler or NIL."
  (gethash via *package-via-handlers*))

;;; --- Dispatch ------------------------------------------------------------

(defun execute-package (action &key mode)
  (let* ((via (getf action :via :system))
         (name (resolved-package-name action))
         (handler (find-package-via-handler via)))
    (cond
      ((eq via :flatpak)
       (execute-flatpak-package action name :mode mode))
      (handler
       (funcall handler action name :mode mode))
      (t
       (let ((installed (package-installed-p via name)))
         (case mode
           (:check (report (if installed :unchanged :would-change) :target name))
           (:apply
            (unless installed
              (run-privileged (install-command via name)))
            (report (if installed :unchanged :changed) :target name))
           (:remove
            (when installed (run-privileged (uninstall-command via name)))
            (report :removed :target name))))))))

(register-action-type :package #'execute-package
                      :description "Install a package via the system package manager, pip, npm, or Flatpak")
