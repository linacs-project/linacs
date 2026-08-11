;;;; tests/api/surface.lisp
;;;;
;;;; Tests for the :linacs.api public API package.
;;;;
;;;; :linacs.api is the stable, documented surface plugins and home
;;;; projects use -- (:use :cl :linacs.api) -- while :linacs.core holds
;;;; the implementation.  These tests pin down the contract:
;;;;
;;;;   1. Every core DSL/registration/authoring symbol a consumer needs is
;;;;      exported from :linacs.api.
;;;;   2. A (:use :cl :linacs.api) consumer package sees the whole DSL
;;;;      without conflict (PACKAGE / DIRECTORY are intentionally NOT
;;;;      exported, only shadowing-imported and accessible).
;;;;   3. The DSL macros work when read from such a consumer package.

(in-package #:linacs-tests)

(def-suite api-surface
  :in linacs-tests
  :description "Tests for the :linacs.api public API package")
(in-suite api-surface)

(defun api-exports-resolve ()
  "Every DSL and registration macro used by linacs-home's project files
must be exportable from :linacs.api (i.e. findable there as EXTERNAL)."
  (let ((api (find-package :linacs.api))
        (need '("DEFINE-HOME" "DEFINE-PROFILE" "USE-FEATURE" "PACKAGE-PREFERENCE"
                "DIRECT-ACTION" "DEFINE-ACTION-MACRO" "DEFINE-DSL-FORM"
                "REGISTER-DSL-FORM" "*CURRENT-HOME-ACTIONS*"
                "FILE" "SYMLINK" "SECRET" "ENV-VAR" "CONFIG-LINES" "CONFIG-INI"
                "CONFIG-ENV" "USER" "GROUP" "AUTHORIZED-KEY" "PERMISSIONS"
                "MOUNT" "SYSCTL" "KERNEL-MODULE" "HOSTNAME" "LOCALE" "FIREWALL"
                "CRON" "COMMAND" "CLONE" "STOW"
                "DEFINE-FEATURE" "REGISTER-FEATURE" "DEFINE-PROVIDER"
                "REGISTER-PROVIDER" "DEFINE-CATALOG" "REGISTER-CATALOG"
                "REGISTER-FACT-PROBER" "DECLARE-FACT" "REGISTER-ACTION-TYPE"
                "REGISTER-PACKAGE-VIA-HANDLER" "REGISTER-PIPELINE-HOOK"
                "REGISTER-SUDO-REQUIRING-ACTION-TYPE"
                "REGISTER-NON-PRIVILEGED-PACKAGE-VIA"
                "FACT" "FACT*" "FACT-KNOWN-P" "FEATURE-CUSTOM" "CATALOG-LOOKUP"
                "ACTION-TYPE" "ACTION-TARGET" "ACTION-SOURCE-LABEL"
                "ACTION-IDENTITY" "REPORT" "WHICH" "SHELL-OK-P"
                "RUN-PRIVILEGED" "EXPAND-HOME"
                "MISSING-PROVIDER" "ACTION-CONFLICT" "DSL-FORM-CONFLICT"
                "EXECUTION-FAILURE"
                "RETRY" "SKIP" "ABORT-PROCESSING")))
    (every (lambda (name)
             (multiple-value-bind (sym status)
                 (find-symbol name api)
               (declare (ignore sym))
               (eq status :external)))
           need)))

(def-test api-exports-all-dsl-symbols ()
  (is (api-exports-resolve)
      "all DSL/registration/authoring symbols must be external in :linacs.api"))

(defun consumer-package-finds-everything ()
  "A (:use :cl :linacs.api) consumer must see every exported symbol."
  (let ((consumer (find-package :linacs.api-consumer-test)))
    (and consumer
         (every (lambda (name)
                  (multiple-value-bind (sym status)
                      (find-symbol name consumer)
                    (declare (ignore sym))
                    (eq status :inherited)))
                '("DEFINE-FEATURE" "DEFINE-PROVIDER" "REGISTER-CATALOG"
                  "USE-FEATURE" "FILE" "SECRET" "FACT" "REGISTER-PIPELINE-HOOK"
                  "REGISTER-FACT-PROBER" "RUN-PRIVILEGED"
                  "DEFINE-DSL-FORM" "REGISTER-DSL-FORM")))))

(def-test api-consumer-package-sees-surface ()
  (is (consumer-package-finds-everything)
      "(:use :cl :linacs.api) must inherit the public API"))

(def-test api-does-not-export-package-or-directory ()
  "PACKAGE and DIRECTORY must NOT be exported from :linacs.api, so a
plugin's (:use :cl :linacs.api) never collides with CL:PACKAGE/CL:DIRECTORY.
They ARE shadowing-imported (thus accessible) -- that part is tested by
the DSL-macro tests below, not here."
  (let ((api (find-package :linacs.api)))
    (is (eq (nth-value 1 (find-symbol "PACKAGE" api)) :internal))
    (is (eq (nth-value 1 (find-symbol "DIRECTORY" api)) :internal))))

(def-test api-dsl-works-from-consumer-package ()
  "The DSL macros expand when read in a :linacs.api consumer package --
the actual linacs-home usage pattern."
  (reset-project-registries)
  (let ((consumer (find-package :linacs.api-consumer-test)))
    (let ((*package* consumer))
      ;; Read-and-eval inside the consumer package so DEFINE-FEATURE /
      ;; DEFINE-PROVIDER resolve to :linacs.api's re-exports, the way a
      ;; plugin's source file would see them.
      (eval (read-from-string
             "(define-feature :api-consumer-feature
                :description \"Registered from a :linacs.api consumer\"
                :provides :api-consumer)"))
      (eval (read-from-string
             "(define-provider :api-consumer-provider
                :for :api-consumer-feature
                (lambda (facts) (declare (ignore facts)) nil))")))
    (is (gethash :api-consumer-feature linacs.core:*feature-registry*))
    (is (linacs.core:find-providers-for :api-consumer-feature)))
  (reset-project-registries))
