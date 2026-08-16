;;;; linacs-cli.asd
;;;;
;;;; ASDF system definition for the LINACS command-line interface
;;;; (REFACTOR.org Action 11 -- thought 33): the CLI is a separate system
;;;; that depends on and loads the :linacs library, so the library itself
;;;; loads in a fresh image without the CLI. The CLI also lives in the
;;;; :linacs.core package (its symbols are exported there, deliberately
;;;; not through :linacs.api); this system is purely a load-unit boundary,
;;;; not a new package.
;;;;
;;;; Usage:
;;;;   Register this directory and load the CLI from any Lisp image:
;;;;
;;;;     (push #P"/path/to/linacs/" asdf:*central-registry*)
;;;;     (asdf:load-system :linacs-cli)
;;;;
;;;;   The --toplevel of the saved executable (see build.sh) funcalls
;;;;   (linacs.core:main ...).

(defsystem "linacs-cli"
    :description "Command-line interface for LINACS"
    :version "0.1.0"
    :depends-on ("linacs")
    :serial t
    :components
    ((:module "src"
              :serial t
              :components
              ((:file "cli")
               (:file "report")))))