;;;; linacs.asd
;;;;
;;;; ASDF system definition for the LINACS core: an explicit :components list,
;;;; not the directory-convention auto-discovery LINACS itself implements for a
;;;; user's home project. The core can't bootstrap via its own Discovery
;;;; mechanism, so its own file layout is ordinary, hand-listed ASDF.
;;;;
;;;; Usage:
;;;;   Register this directory and load the system from any Lisp image:
;;;;
;;;;     (push #P"/path/to/linacs/" asdf:*central-registry*)
;;;;     (asdf:load-system :linacs)
;;;;
;;;;   Force a full rebuild after pulling changes or editing files outside
;;;;   the running image (see docs/user-manual.md §5.27):
;;;;
;;;;     (asdf:load-system :linacs :force t)

(defsystem "linacs"
    :description "Declarative Linux home environment management"
    :version "0.1.0"
    :depends-on ("asdf" "uiop")
    :serial t
    :components
    ((:module "src"
              :serial t
              :components
               ((:file "package")
                (:file "conditions")
                (:file "log")
                (:module "fact-model"
                         :pathname "domain"
                         :serial t
                         :components
                         ((:file "fact")))
                (:file "discovery")
                (:file "facts")
               (:file "profiles")
               (:file "catalogs")
               (:file "features")
               (:module "provider-model"
                        :pathname "domain"
                        :serial t
                        :components
                        ((:file "provider")))
               (:file "providers")
               (:module "backends"
                         :pathname "backends/filesystem"
                         :serial t
                         :components
                         ((:file "filesystem")
                          (:file "memory")
                          (:file "recording")))
               ;; The backend protocols load here, before action-types, so
               ;; helpers.lisp and the executors can reference
               ;; FIND-PACKAGE-BACKEND / FIND-SERVICE-BACKEND /
               ;; FIND-REPOSITORY-BACKEND. These protocol files funcall the
               ;; functions stored on their backends -- no dependency on the
               ;; action model or the REPORT helper.
               (:module "package-backend"
                         :pathname "backends/packages"
                         :serial t
                         :components
                         ((:file "package-backend")))
               (:module "service-backend"
                         :pathname "backends/services"
                         :serial t
                         :components
                         ((:file "service-backend")))
               (:module "repository-backend"
                         :pathname "backends/repositories"
                         :serial t
                         :components
                         ((:file "repository-backend")))
               (:module "execution"
                        :pathname "domain/execution"
                        :serial t
                        :components
((:file "context")
                          (:file "result")
                          (:file "provenance")
                          (:file "events")))
               (:file "actions")
               (:module "domain"
                         :serial t
                         :components
                         ((:module "action"
                                  :serial t
                                  :components
                                   ((:file "action")
                                    (:file "protocol")
                                    (:file "state")))))
               (:module "planning"
                        :serial t
                        :components
                        ((:file "plan")))
               (:file "secrets")
               (:file "templates")
               (:module "action-types"
                        :serial t
                        :components
                        ((:file "package")
                         (:file "helpers")
                         (:file "copy-file")
                         (:file "ensure-dir")
                         (:file "symlink")
                         (:file "service")
                         (:file "timer")
                         (:file "env-var")
                         (:file "config-lines")
                         (:file "config-ini")
                         (:file "config-env")
                         (:file "package-action")
                         (:file "secret")
                         (:file "user")
                         (:file "group")
                         (:file "authorized-key")
                         (:file "permissions")
                         (:file "mount")
                         (:file "sysctl")
                         (:file "kernel-module")
                         (:file "hostname")
                         (:file "locale")
                         (:file "firewall")
                         (:file "cron")
                         (:file "command")
                         (:file "clone")
                          (:file "repository")
                          (:file "stow")))
               ;; The real filesystem backend loads after action-types/helpers
               ;; so its methods can use the escalate-on-demand helpers.
               (:module "backends-real"
                         :pathname "backends/filesystem"
                         :serial t
                         :components
                         ((:file "real")))
               ;; The built-in package backend registrations wrap the
               ;; execute-*-package functions from action-types/package-action.lisp,
               ;; so they load after the action-types module.
               (:module "package-backends"
                         :pathname "backends/packages"
                         :serial t
                         :components
                         ((:file "backends")))
               ;; The built-in service backends (systemd / systemd-user) load
               ;; here too, after action-types/helpers.lisp, so their
               ;; primitives can reference RUN-PRIVILEGED.
               (:module "service-backends"
                         :pathname "backends/services"
                         :serial t
                         :components
                         ((:file "systemd")))
               (:file "pipeline")
               (:file "privilege")
               (:file "dsl")
               (:file "json")))))
