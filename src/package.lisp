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
   #:use-first #:use-second
   #:specify-provider #:skip-feature
   #:retry-with-sudo
   #:supply-value
   #:specify-renderer #:treat-as-static

   ;; facts / profiles
    #:register-fact-prober
    #:probe-all-facts
    #:fact
    #:fact-known-p
    #:*facts*
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
    #:*feature-registry*
    #:register-provider
    #:find-provider
    #:find-providers-for
    #:resolve-feature-graph
    #:select-provider

   ;; actions
   #:make-action
   #:action-type
   #:action-target
   #:action-plist
   #:action-identity
   #:register-action-type
   #:find-executor
   #:execute-action
   #:dedup-actions
   #:order-actions
   #:register-package-via-handler

   ;; secrets / templates
   #:resolve-secret
   #:render-template

   ;; pipeline
   #:register-pipeline-hook
   #:run-pipeline
   #:*pipeline-hooks*

   ;; privilege
    #:privileged-p
    #:run-privileged
    #:preflight-notice
    #:action-needs-privilege-p
    #:sudo-n-or-a-prefix
    #:*sudo-askpass*
    #:apply-sudo-password-stdin
    #:sudo-reset-after-run

   ;; helpers
   #:read-sudo-password
   #:shell-ok-p
   #:which
   #:report

   ;; discovery
   #:discover-project
   #:discover-plugins

   ;; dsl
   #:define-home
   #:use-feature
   #:file
   #:directory
   #:symlink
   #:package
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
   #:*current-home-actions*
   #:*current-home-name*
   #:*current-home-traits*

   ;; cli
   #:main
   #:parse-args
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
   #:cli-opts-help))

(defpackage :linacs-templates
  (:use :cl)
  (:export))
