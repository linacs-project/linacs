(defsystem "linacs-tests"
    :description "Test suite for LINACS core"
    :author "LINACS Contributors"
    :license "MIT"
    :depends-on ("linacs" "fiveam")
    :serial t
    :components
    ((:file "package")
     (:file "helpers")
     (:file "restart-menu")
     (:module "actions"
               :serial t
               :components
((:file "identity")
                  (:file "dedup")
                  (:file "ordering")
                  (:file "object-model")
                  (:file "protocol")))
     (:module "dsl"
               :serial t
               :components
               ((:file "macros")
                (:file "validation")
                (:file "dsl-form-registration")))
     (:module "api"
               :serial t
               :components
               ((:file "surface")))
     (:module "features"
               :serial t
               :components
               ((:file "graph")))
     (:module "providers"
               :serial t
               :components
               ((:file "macros")))
(:module "pipeline"
                :serial t
                :components
                ((:file "execution")
                 (:file "disabled-actions")
                 (:file "hooks")
                 (:file "project-root")
                 (:file "repository-prerequisites")
                 (:file "execution-context")))
      (:module "cli"
               :serial t
               :components
               ((:file "flag-parsing")
                (:file "init")))
      (:module "facts"
               :serial t
               :components
               ((:file "schema")))
      (:module "privilege"
               :serial t
               :components
               ((:file "basics")))
      (:module "profiles"
               :serial t
               :components
               ((:file "metadata")))
(:module "executors"
                :serial t
                :components
                ((:file "copy-file")
                 (:file "ensure-dir")
                 (:file "symlink")
                 (:file "stow")
                 (:file "service")
                 (:file "config-lines")
                 (:file "package-action")
                 (:file "repository")))))