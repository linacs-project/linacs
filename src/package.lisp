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
    #:register-fact-source
    #:declare-fact-source
    #:probe-all-facts
    #:fact
    #:fact*
    #:fact-known-p
    #:*facts*
    #:*facts-read*
    #:reset-facts-read
    #:snapshot-facts-read
    #:*fact-sources*
    #:*fact-objects*
    #:refresh-facts-plist
    #:set-fact
    #:fact-source #:make-fact-source #:fact-source-p #:fact-source-name #:fact-source-probe-fn
    #:fact-source-registrant #:fact-source-type #:fact-source-doc
    #:make-fact #:fact-p #:fact-name #:fact-value #:fact-confidence
    #:fact-source-of
    #:default-fact-sources
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
    #:select-provider-object
    ;; first-class provider object (REFACTOR.org Thought 9 / Action 9)
    #:provider
    #:make-provider
    #:provide-actions
    #:provider-name
    #:provider-feature
    #:provider-function
    #:provider-default-p
    #:provider-description

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
    ;; execution context (REFACTOR.org Action 4)
    #:execution-context
    #:make-execution-context
    #:with-execution-context
    #:*execution-context*
    #:execution-context-facts
    #:execution-context-project-root
    #:execution-context-asset-root
    #:execution-context-results
    #:execution-context-provenance
    #:execution-context-progress-reporter
    #:execution-context-capture-subprocess-output
    #:context-facts
    #:context-project-root
    #:context-asset-root
    #:context-results
    #:context-provenance
    #:context-progress-reporter
    #:context-capture-subprocess-output
    ;; execution results / provenance / plan (REFACTOR.org Action 5)
    #:action-result
    #:make-action-result
    #:result-action
    #:result-status
    #:result-error
    #:result-duration
    #:result-mode
    #:result->plist
    #:plist->result
    #:action-provenance
    #:make-action-provenance
    #:make-action-provenance-from-plist
    #:provenance-source
    #:provenance-feature
    #:provenance-provider
    #:provenance-facts-snapshot
    #:provenance-location
    #:provenance->plist
    #:action-plan
    #:make-action-plan
    #:plan-actions
    #:plan-provenance
    #:plan-results
    #:plan-conflicts
    #:add-action
    #:action-by-identity
    #:deduplicate-plan
    #:order-plan
    #:plan-result
    #:plan-status
    #:*action-identity-functions*
    ;; execution events (REFACTOR.org Thought 8)
    #:execution-event
    #:event-stage
    #:plan-started #:make-plan-started
    #:feature-resolved #:make-feature-resolved
    #:plan-completed #:make-plan-completed
    #:action-started #:make-action-started
    #:action-output #:make-action-output
    #:action-completed #:make-action-completed
    #:action-skipped #:make-action-skipped
    #:action-failed #:make-action-failed
    #:event-plan #:event-feature #:event-provider #:event-action
    #:event-result #:event-error #:event-stream #:event-line
    #:report-event
    ;; filesystem backend (REFACTOR.org Thought 11 / Action 8)
    #:filesystem #:real-filesystem #:memory-filesystem #:recording-filesystem
    #:make-real-filesystem #:make-memory-filesystem #:make-recording-filesystem
    #:*filesystem* #:context-filesystem
    #:fs-path-string #:fs-canonical-path #:fs-parent-path
    #:fs-exists-p #:fs-directory-p #:fs-file-p #:fs-symlink-p
    #:fs-read-link #:fs-directory-entries #:fs-read-file #:fs-truename
    #:fs-file-mode
    #:fs-make-directory #:fs-write-file #:fs-symlink #:fs-delete
    #:fs-rmdir #:fs-delete-directory-tree #:fs-set-mode #:fs-set-owner
    #:fs-apply-ownership
   #:register-action-type
   #:find-executor
   #:execute-action
   #:dedup-actions
   #:order-actions
   #:package-backend #:make-package-backend #:*package-backends*
   #:register-package-backend #:find-package-backend #:execute-package-backend
   #:backend-via #:backend-executor #:backend-installed-p-fn
   #:backend-install-fn #:backend-uninstall-fn
   #:backend-privileged-p #:backend-description
   #:backend-installed-p #:backend-install #:backend-uninstall
   #:backend-needs-privilege-p
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

   ;; json encoding (REFACTOR.org Action 10, thought 19)
   #:encode-json
   #:json-quote-string
   #:json-key-name

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
   #:cli-opts-format
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
    #:define-catalog #:register-catalog #:register-fact-source #:declare-fact-source
    #:register-action-type #:package-backend #:make-package-backend
    #:register-package-backend #:find-package-backend #:execute-package-backend
    #:backend-via #:backend-executor #:backend-privileged-p #:backend-description
    #:backend-installed-p #:backend-install #:backend-uninstall
    #:backend-needs-privilege-p
    #:register-pipeline-hook
    #:register-repository-method
    #:register-sudo-requiring-action-type #:register-non-privileged-package-via
    ;; provider object (REFACTOR.org Thought 9 / Action 9)
    #:provider #:make-provider #:provide-actions
    #:provider-name #:provider-feature #:provider-function
    #:provider-default-p #:provider-description
    #:select-provider-object
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
    ;; execution context (REFACTOR.org Action 4)
    #:make-execution-context
    #:with-execution-context
    #:context-facts
    #:context-project-root
    #:context-asset-root
    #:context-results
    #:context-provenance
    #:context-filesystem
    ;; filesystem backend (REFACTOR.org Thought 11 / Action 8)
    #:filesystem #:real-filesystem #:memory-filesystem #:recording-filesystem
    #:make-real-filesystem #:make-memory-filesystem #:make-recording-filesystem
    #:fs-exists-p #:fs-directory-p #:fs-file-p #:fs-symlink-p
    #:fs-read-link #:fs-directory-entries #:fs-read-file #:fs-truename
    #:fs-file-mode
    #:fs-make-directory #:fs-write-file #:fs-symlink #:fs-delete
    #:fs-rmdir #:fs-delete-directory-tree #:fs-set-mode #:fs-set-owner
    #:fs-apply-ownership
    ;; execution results / provenance / plan (REFACTOR.org Action 5)
    #:action-result #:make-action-result
    #:result-action #:result-status #:result-error
    #:action-provenance #:make-action-provenance
    #:provenance-source #:provenance-feature #:provenance-provider
    #:provenance-facts-snapshot
    #:action-plan #:make-action-plan
    #:plan-actions #:plan-provenance #:plan-results #:plan-conflicts
    #:plan-status #:plan-result
    #:add-action #:action-by-identity
    #:deduplicate-plan #:order-plan
    ;; execution events (REFACTOR.org Thought 8)
    #:execution-event #:event-stage
    #:make-plan-started #:make-feature-resolved #:make-plan-completed
    #:make-action-started #:make-action-output #:make-action-completed
    #:make-action-skipped #:make-action-failed
    #:event-plan #:event-feature #:event-provider #:event-action
    #:event-result #:event-error #:event-stream #:event-line
    #:report-event
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
    #:define-catalog #:register-catalog #:register-fact-source #:declare-fact-source
    #:register-action-type #:package-backend #:make-package-backend
    #:register-package-backend #:find-package-backend #:execute-package-backend
    #:backend-via #:backend-executor #:backend-privileged-p #:backend-description
    #:backend-installed-p #:backend-install #:backend-uninstall
    #:backend-needs-privilege-p
    #:register-pipeline-hook
    #:register-repository-method
    #:register-sudo-requiring-action-type #:register-non-privileged-package-via
    ;; provider object (REFACTOR.org Thought 9 / Action 9)
    #:provider #:make-provider #:provide-actions
    #:provider-name #:provider-feature #:provider-function
    #:provider-default-p #:provider-description
    #:select-provider-object
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
    ;; execution context (REFACTOR.org Action 4)
    #:make-execution-context
    #:with-execution-context
    #:context-facts
    #:context-project-root
    #:context-asset-root
    #:context-results
    #:context-provenance
    #:context-filesystem
    ;; filesystem backend (REFACTOR.org Thought 11 / Action 8)
    #:filesystem #:real-filesystem #:memory-filesystem #:recording-filesystem
    #:make-real-filesystem #:make-memory-filesystem #:make-recording-filesystem
    #:fs-exists-p #:fs-directory-p #:fs-file-p #:fs-symlink-p
    #:fs-read-link #:fs-directory-entries #:fs-read-file #:fs-truename
    #:fs-file-mode
    #:fs-make-directory #:fs-write-file #:fs-symlink #:fs-delete
    #:fs-rmdir #:fs-delete-directory-tree #:fs-set-mode #:fs-set-owner
    #:fs-apply-ownership
    ;; execution results / provenance / plan (REFACTOR.org Action 5)
    #:action-result #:make-action-result
    #:result-action #:result-status #:result-error
    #:action-provenance #:make-action-provenance
    #:provenance-source #:provenance-feature #:provenance-provider
    #:provenance-facts-snapshot
    #:action-plan #:make-action-plan
    #:plan-actions #:plan-provenance #:plan-results #:plan-conflicts
    #:plan-status #:plan-result
    #:add-action #:action-by-identity
    #:deduplicate-plan #:order-plan
    ;; execution events (REFACTOR.org Thought 8)
    #:execution-event #:event-stage
    #:make-plan-started #:make-feature-resolved #:make-plan-completed
    #:make-action-started #:make-action-output #:make-action-completed
    #:make-action-skipped #:make-action-failed
    #:event-plan #:event-feature #:event-provider #:event-action
    #:event-result #:event-error #:event-stream #:event-line
    #:report-event
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
