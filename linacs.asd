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
    :version "1.1.0"
    :depends-on ("asdf" "uiop")
    :serial t
    :components
    ((:module "src"
              :serial t
              :components
              ((:file "package")
               (:file "conditions")
               (:file "log")
               (:file "discovery")
               (:file "facts")
               (:file "profiles")
               (:file "catalogs")
               (:file "features")
               (:file "providers")
               (:file "actions")
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
                         (:file "stow")))
               (:file "pipeline")
               (:file "privilege")
               (:file "dsl")
               (:file "cli")))))
