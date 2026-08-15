;;;; src/backends/packages/backends.lisp
;;;;
;;;; Built-in package backends (REFACTOR.org Action 15). Each registers a
;;;; PACKAGE-BACKEND wrapping one of the executor functions from
;;;; action-types/package-action.lisp, so :package :via dispatch now runs
;;;; through the object protocol while producing results identical to the
;;;; historic via-handler table.
;;;;
;;;; Registered vias: :system, :pip, :npm, :flatpak, :toolbox, :podman,
;;;; :appimage. Plugins add further ecosystems (e.g. :rpm-ostree) with the
;;;; same REGISTER-PACKAGE-BACKEND call from their own source files.

(in-package :linacs.core)

(register-package-backend
 (make-package-backend :via :system
                       :executor #'execute-system-package
                       :privileged-p t
                       :description "System package manager (dnf/pacman/apt/... via the :packages catalog)"))

(register-package-backend
 (make-package-backend :via :pip
                       :executor #'execute-pip-package
                       :privileged-p t
                       :description "Python packages via pip"))

(register-package-backend
 (make-package-backend :via :npm
                       :executor #'execute-npm-package
                       :privileged-p t
                       :description "Global Node packages via npm"))

(register-package-backend
 (make-package-backend :via :flatpak
                       :executor #'execute-flatpak-package
                       :privileged-p (lambda (action)
                                       (not (eq (getf action :scope :user) :user)))
                       :description "Flatpak applications (flathub default; :scope :user never escalates)"))

(register-package-backend
 (make-package-backend :via :toolbox
                       :executor #'execute-toolbox-package
                       :privileged-p t
                       :description "Containerised CLI tools via toolbox (wrapper scripts in ~/.local/bin)"))

(register-package-backend
 (make-package-backend :via :podman
                       :executor #'execute-toolbox-package
                       :privileged-p t
                       :description "Containerised CLI tools via podman (toolbox backend)"))

(register-package-backend
 (make-package-backend :via :appimage
                       :executor #'execute-appimage-package
                       :privileged-p nil
                       :description "AppImage binaries (user-space; download is manual)"))
