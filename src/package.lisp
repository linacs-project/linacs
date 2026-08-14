;;;; src/package.lisp
;;;;
;;;; Package definitions for the three packages LINACS's core is split across:
;;;;
;;;;   :linacs.core       -- the engine, DSL, and CLI (everything else in src/)
;;;;   :linacs.log        -- the small leveled-logging facility
;;;;   :linacs-templates  -- where a project's own RENDER-* template functions live
;;;;
;;;; This is the first file loaded (see linacs.asd), so every other file in the
;;;; system can assume these packages, and everything :linacs.core exports,
;;;; already exist.

(defpackage :linacs.log
  (:use :cl)
  (:export #:info #:debug* #:warn* #:error* #:set-verbosity #:*verbosity*))

(defpackage :linacs.core
  (:use :cl)
  (:shadow #:package #:directory)
  (:export
   ;; conditions
   #:linacs-error
   #:missing-provider
   #:action-conflict
   #:dsl-form-conflict
   #:insufficient-privileges
   #:permission-denied-mid-run
   #:non-interactive-prompt
   #:fact-prober-conflict
   #:missing-template-renderer
   #:execution-failure
   #:file-discovery-load-error
   #:pipeline-aborted-by-hook
   #:dependency-cycle
    #:retry #:skip #:abort-processing
    #:force
    #:use-first #:use-second
   #:specify-provider #:skip-feature
   #:retry-with-sudo
   #:supply-value
   #:specify-renderer #:treat-as-static
   ;; interactive restart menu (compiled CLI)
   #:with-linacs-restarts
   #:handle-linacs-error-interactively
   #:compute-linacs-restarts
   #:*restart-menu-p*
   #:*linacs-abort-function*

    ;; facts / profiles
    #:register-fact-prober
    #:declare-fact
    #:probe-all-facts
    #:fact
    #:fact*
    #:fact-known-p
    #:*facts*
    #:*facts-read*
    #:reset-facts-read
    #:snapshot-facts-read
    #:*fact-probers*
    #:*fact-metadata*
    #:default-fact-probers
    #:define-profile
    #:*profiles*
    #:apply-profile

   ;; catalogs
   #:define-catalog
   #:register-catalog
   #:catalog-lookup

    ;; features / providers
     #:define-feature
     #:register-feature
     #:*feature-registry*
     #:define-provider
     #:register-provider
     #:feature-custom
     #:register-feature-customs
     #:clear-feature-customs
    #:find-provider
    #:find-providers-for
    #:resolve-feature-graph
    #:select-provider

   ;; actions
   #:make-action
   #:plist->action
   #:action->plist
   #:action-priority
   #:action-force
   #:action-disabled
   #:action-depends-on
   #:action-source
   #:action-location
   #:action-project-root
   #:action-mode
   #:action-owner
   #:action-group
    #:same-action-content-p
    #:action-p
    #:action-type
    #:action-target
    #:action-source-label
    #:action-plist
    #:action-identity
    #:action-description
    #:action-dedup-behavior
    #:*action-statuses*
    #:executor-status
    #:current-state
    #:desired-state
    #:diff-state
    #:apply-state
    #:remove-state
    #:*action-identity-functions*
   #:register-action-type
   #:find-executor
   #:execute-action
   #:dedup-actions
   #:order-actions
   #:register-package-via-handler
   #:register-repository-method
   #:find-repository-method
   #:*repository-methods*
   #:resolve-repository-prerequisites
   #:*provenance*
   #:register-provenance
   #:action-provenance
   #:*action-results*
   #:action-result-status

   ;; secrets / templates
   #:resolve-secret
   #:render-template

   ;; pipeline
   #:register-pipeline-hook
   #:resolve-plan
   #:execute-plan
   #:run-pipeline
   #:*pipeline-hooks*
   #:*project-root*
   #:*asset-root*
   #:resolve-asset-root
   #:action-asset-root

    ;; privilege
     #:privileged-p
     #:run-privileged
     #:preflight-notice
     #:*sudo-askpass*
     #:apply-sudo-password-stdin
     #:sudo-reset-after-run

    ;; helpers
    #:read-sudo-password
    #:*sudo-password*
    #:sudo-n-or-a-prefix
    #:expand-home
    #:register-sudo-requiring-action-type
    #:register-non-privileged-package-via
    #:action-needs-privilege-p
    #:preflight-sudo-prompt
    #:shell-ok-p
    #:which
    #:report

   ;; discovery
   #:discover-project
   #:discover-plugins

   ;; dsl
   #:define-home
   #:use-feature
   #:define-action-macro
   #:define-dsl-form
   #:register-dsl-form
   #:file
   #:directory
   #:symlink
    #:package
    #:package-preference
    #:secret
   #:env-var
   #:config-lines
   #:config-ini
   #:config-env
   #:direct-action
   #:user
   #:group
   #:authorized-key
   #:permissions
   #:mount
   #:sysctl
   #:kernel-module
   #:hostname
   #:locale
   #:firewall
   #:cron
#:command
    #:clone
    #:stow
    #:repository
   #:*current-home-actions*
   #:*current-home-name*
   #:*current-home-traits*

   ;; cli
   #:main
   #:parse-args
   #:cmd-init
   #:cli-opts
   #:make-cli-opts
   #:cli-opts-root
   #:cli-opts-platform
   #:cli-opts-profile
   #:cli-opts-provider-overrides
   #:cli-opts-dry-run
   #:cli-opts-continue-on-error
   #:cli-opts-output
   #:cli-opts-verbosity
   #:cli-opts-quiet
   #:cli-opts-sudo-password-stdin
   #:cli-opts-sudo-reset
   #:cli-opts-example
   #:cli-opts-help))

(defpackage :linacs.api
  (:use :cl)
  (:shadowing-import-from :linacs.core
    ;; The two DSL macros that collide with CL. Kept ACCESSIBLE here (so a
    ;; home.lisp `(in-package :linacs.api)` sees them unqualified) but
    ;; deliberately NOT exported -- an exported PACKAGE/DIRECTORY would
    ;; make every plugin's (:use :cl :linacs.api) signal a name conflict.
    #:package
    #:directory)
  (:import-from :linacs.core
    ;; DSL
    #:define-home #:define-profile #:use-feature #:package-preference
    #:direct-action #:define-action-macro #:define-dsl-form #:register-dsl-form
    #:*current-home-actions*
    #:file #:symlink #:secret #:env-var #:config-lines #:config-ini #:config-env
    #:user #:group #:authorized-key #:permissions #:mount #:sysctl
    #:kernel-module #:hostname #:locale #:firewall #:cron #:command #:clone #:stow #:repository
    ;; registration
    #:define-feature #:register-feature #:define-provider #:register-provider
    #:define-catalog #:register-catalog #:register-fact-prober #:declare-fact
    #:register-action-type #:register-package-via-handler #:register-pipeline-hook
    #:register-repository-method
    #:register-sudo-requiring-action-type #:register-non-privileged-package-via
    ;; authoring helpers
    #:fact #:fact* #:fact-known-p #:feature-custom #:catalog-lookup
    #:action-type #:action-target #:action-source-label #:action-identity
    #:make-action #:plist->action #:action->plist #:same-action-content-p
    #:action-priority #:action-force #:action-disabled #:action-depends-on
    #:action-source #:action-location #:action-project-root #:action-mode
    #:action-owner #:action-group #:action-p
    #:action-description #:action-dedup-behavior
    #:*action-statuses* #:executor-status
    #:current-state #:desired-state #:diff-state #:apply-state #:remove-state
    #:report #:which #:shell-ok-p #:run-privileged #:expand-home
    #:*project-root* #:*asset-root* #:action-asset-root
    ;; conditions
    #:linacs-error #:missing-provider #:action-conflict #:dsl-form-conflict
    #:execution-failure
    #:insufficient-privileges #:permission-denied-mid-run #:non-interactive-prompt
    #:fact-prober-conflict #:missing-template-renderer #:file-discovery-load-error
    #:pipeline-aborted-by-hook #:dependency-cycle
    ;; restarts
    #:retry #:skip #:abort-processing #:force #:use-first #:use-second #:specify-provider
    #:skip-feature #:retry-with-sudo #:supply-value #:specify-renderer
    #:treat-as-static
    ;; interactive restart menu
    #:with-linacs-restarts
    #:handle-linacs-error-interactively
    #:compute-linacs-restarts
    #:*restart-menu-p*
    #:*linacs-abort-function*)
  (:import-from :linacs.log
    #:info #:debug* #:warn* #:error* #:set-verbosity #:*verbosity*)
  (:export
    ;; DSL
    #:define-home #:define-profile #:use-feature #:package-preference
    #:direct-action #:define-action-macro #:define-dsl-form #:register-dsl-form
    #:*current-home-actions*
    #:file #:symlink #:secret #:env-var #:config-lines #:config-ini #:config-env
    #:user #:group #:authorized-key #:permissions #:mount #:sysctl
    #:kernel-module #:hostname #:locale #:firewall #:cron #:command #:clone #:stow #:repository
    ;; registration
    #:define-feature #:register-feature #:define-provider #:register-provider
    #:define-catalog #:register-catalog #:register-fact-prober #:declare-fact
    #:register-action-type #:register-package-via-handler #:register-pipeline-hook
    #:register-repository-method
    #:register-sudo-requiring-action-type #:register-non-privileged-package-via
    ;; authoring helpers
    #:fact #:fact* #:fact-known-p #:feature-custom #:catalog-lookup
    #:action-type #:action-target #:action-source-label #:action-identity
    #:make-action #:plist->action #:action->plist #:same-action-content-p
    #:action-priority #:action-force #:action-disabled #:action-depends-on
    #:action-source #:action-location #:action-project-root #:action-mode
    #:action-owner #:action-group #:action-p
    #:action-description #:action-dedup-behavior
    #:*action-statuses* #:executor-status
    #:current-state #:desired-state #:diff-state #:apply-state #:remove-state
    #:report #:which #:shell-ok-p #:run-privileged #:expand-home
    #:*project-root* #:*asset-root* #:action-asset-root
    ;; conditions
    #:linacs-error #:missing-provider #:action-conflict #:dsl-form-conflict
    #:execution-failure
    #:insufficient-privileges #:permission-denied-mid-run #:non-interactive-prompt
    #:fact-prober-conflict #:missing-template-renderer #:file-discovery-load-error
    #:pipeline-aborted-by-hook #:dependency-cycle
    ;; restarts
    #:retry #:skip #:abort-processing #:force #:use-first #:use-second #:specify-provider
    #:skip-feature #:retry-with-sudo #:supply-value #:specify-renderer
    #:treat-as-static
    ;; interactive restart menu
    #:with-linacs-restarts
    #:handle-linacs-error-interactively
    #:compute-linacs-restarts
    #:*restart-menu-p*
    #:*linacs-abort-function*
    ;; logging (re-exported so plugin authors need no separate :linacs.log import)
    #:info #:debug* #:warn* #:error* #:set-verbosity #:*verbosity*))

(defpackage :linacs-templates
  (:use :cl)
  (:export))
