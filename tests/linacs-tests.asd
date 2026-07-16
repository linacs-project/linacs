(defsystem "linacs-tests"
    :description "Test suite for LINACS core"
    :author "LINACS Contributors"
    :license "MIT"
    :depends-on ("linacs" "fiveam")
    :serial t
    :components
    ((:file "package")
     (:file "helpers")
     (:module "actions"
              :serial t
              :components
              ((:file "identity")
               (:file "dedup")
               (:file "ordering")))
     (:module "dsl"
              :serial t
              :components
              ((:file "macros")
               (:file "validation")))
     (:module "features"
              :serial t
              :components
              ((:file "graph")))
     (:module "pipeline"
              :serial t
              :components
              ((:file "execution")))
     (:module "executors"
              :serial t
              :components
              ((:file "copy-file")
               (:file "ensure-dir")
               (:file "symlink")
               (:file "service")
               (:file "config-lines")
               (:file "package-action")))))