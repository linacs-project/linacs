;;;; src/dsl.lisp
;;;;
;;;; The user-facing home-definition language: DEFINE-HOME and every
;;;; convenience form usable inside it (USE-FEATURE, FILE, DIRECTORY,
;;;; SYMLINK, PACKAGE, SECRET, ENV-VAR, CONFIG-LINES, CONFIG-INI, CONFIG-ENV,
;;;; the system-administration forms USER/GROUP/AUTHORIZED-KEY/PERMISSIONS/
;;;; MOUNT/SYSCTL/KERNEL-MODULE/HOSTNAME/LOCALE/FIREWALL/CRON/COMMAND, and
;;;; DIRECT-ACTION).
;;;;
;;;; DEFINE-HOME's body is *not* evaluated at load time. It is captured as a
;;;; closure and invoked later by the pipeline, after facts have been probed
;;;; and the selected profile merged in (Execution Model step 2) -- so that
;;;; standard Lisp conditionals like (when (fact :laptop-p) ...) see real
;;;; fact values. This is why home.lisp can be *loaded* during Discovery
;;;; (step 0) yet still react correctly to facts resolved in step 1.
;;;;
;;;; Every convenience form's arguments are taken as literal data at
;;;; macroexpansion time and never themselves evaluated as code -- this is
;;;; what lets `:depends-on ((:package :system . "emacs"))` work without
;;;; `:package` being misread as a function call. The one exception is
;;;; USE-FEATURE's :via, which is deliberately evaluated at thunk-run time,
;;;; so `(if (fact :work-p) :emacs :vim)` works there.
;;;;
;;;; Usage:
;;;;     (define-home my-home
;;;;       :traits (:prune-explicitly-disabled)
;;;;       (use-feature :editor :via (if (fact :work-p) :emacs :vim))
;;;;       (use-feature :version-control
;;;;         :custom (:username "bob" :useremail "bob@mail.com"))
;;;;       (file "~/.gitconfig" :from "gitconfig")
;;;;       (package "nano" :disabled t))

(in-package :linacs.core)

(defvar *current-home-name* nil)
(defvar *current-home-traits* nil)
(defvar *current-home-thunk* nil
  "The captured, not-yet-run body of the most recently loaded DEFINE-HOME.")
(defvar *current-home-use-features* nil)
(defvar *current-home-actions* nil)
(defvar *current-home-package-preference* nil
  "Set by the PACKAGE-PREFERENCE form inside DEFINE-HOME.")

(defvar *dsl-forms* (make-hash-table :test 'equal)
  "Maps DSL form name (uppercase string) -> plist (:source <label>) describing
where the form was defined. Populated by REGISTER-DSL-FORM and, for core's own
built-in convenience forms, by DEFAULT-DSL-FORMS at bootstrap. Purely
documentation for `linacs list`; never consulted by resolution or execution.")

(defvar *core-built-in-dsl-forms*
  '("FILE" "DIRECTORY" "SYMLINK" "SECRET" "ENV-VAR" "CONFIG-LINES" "CONFIG-INI"
    "CONFIG-ENV" "USER" "GROUP" "AUTHORIZED-KEY" "PERMISSIONS" "MOUNT" "SYSCTL"
    "KERNEL-MODULE" "HOSTNAME" "LOCALE" "FIREWALL" "CRON" "COMMAND" "CLONE"
    "STOW" "PACKAGE")
  "The home-level convenience forms LINACS itself defines and re-exports
through :linacs.api. Re-registered into *DSL-FORMS* at bootstrap, after
RESET-PROJECT-REGISTRIES clears the registry.")

(defun location-from-load-pathname ()
  "Capture the file being loaded at macroexpansion time."
  (list :file (or (ignore-errors (namestring *load-pathname*))
                  (ignore-errors (namestring *compile-file-pathname*))
                  "<unknown>")))

(defun current-dsl-form-source ()
  "Best-effort label for the file currently being loaded, for DSL-form metadata."
  (or (getf (location-from-load-pathname) :file) "<unknown>"))

(defun register-dsl-form (name &key (source (current-dsl-form-source)))
  "Make the macro NAME usable unqualified in :linacs.api -- and therefore in
home.lisp and every discovered project file, which are all read in :linacs.api.

If the file loading this form is itself read in :linacs.core (core's own
built-in convenience forms), this is a metadata-only no-op: they are declared
statically in :linacs.api's defpackage and never need a runtime import. That is
a deliberate strong check on *PACKAGE* rather than on NAME's home package:
SBCL's :import-from shares symbol identity across packages, so
LINACS.API:FILE and LINACS.CORE:FILE are the same symbol and a plugin package
that inherits FILE would otherwise be indistinguishable from core itself.

Otherwise the name must not already exist in :linacs.api: if it does, signal
DSL-FORM-CONFLICT (abort-only, no silent winner) rather than shadow an
existing home-level form -- the same no-clobber rule as fact probers. If the
name is free, NAME is imported into :linacs.api.

Programmatic twin of DEFINE-DSL-FORM (which DEFMACROs and registers). Returns
NAME."
  (let* ((key (symbol-name name))
         (api (find-package :linacs.api))
         (existing (and api (nth-value 1 (find-symbol key api))))
         (registering-in-core (eq *package* (find-package :linacs.core))))
    (when (and existing (not registering-in-core))
      (error 'dsl-form-conflict
             :name key
             :existing (or (getf (gethash key *dsl-forms*) :source) "<unknown>")))
    (setf (gethash key *dsl-forms*) (list :source source))
    (when (and api (not registering-in-core))
      (import (list name) api))
    name))

(defun default-dsl-forms ()
  "Re-register core's built-in home-level convenience forms into *DSL-FORMS*,
so `linacs list` reports them alongside plugin-defined forms even after
RESET-PROJECT-REGISTRIES clears the registry."
  (dolist (name *core-built-in-dsl-forms*)
    (setf (gethash name *dsl-forms*) (list :source "core built-in"))))

(defmacro define-dsl-form (name lambda-list &body body)
  "Define NAME as a home-level DSL macro usable unqualified in :linacs.api
(home.lisp, features/, providers/, ...). Expands to REGISTER-DSL-FORM -- which
conflict-checks and aborts on a duplicate name before anything is clobbered --
followed by an ordinary DEFMACRO in the current package.

    (define-dsl-form kde-config (file group key value &rest opts)
      ...body...)

This is the general, plugin-facing form; DEFINE-ACTION-MACRO covers the common
'(target &rest opts)' shape and registers the same way."
  `(progn
     (register-dsl-form ',name)
     (defmacro ,name ,lambda-list ,@body)))

(defmacro define-action-macro (name action-type source &key extra-plist)
  "Define NAME as a home-level DSL macro, for the common '(target &rest opts)'
shape, that pushes a :ACTION-TYPE action into *CURRENT-HOME-ACTIONS*. The
result is registered via REGISTER-DSL-FORM, so it is usable unqualified in
:linacs.api (home.lisp and every discovered project file) automatically --
plugin authors need no manual import. Conflicts with an already-registered
form of the same name signal DSL-FORM-CONFLICT before the macro is redefined."
  `(progn
     (register-dsl-form ',name)
     (defmacro ,name (target &rest opts)
       (let* ((loc (location-from-load-pathname))
              (action (list* :action ,action-type :target target
                             ,@extra-plist
                             (append opts
                                     (list :priority :user :source ,source :location loc)))))
         `(progn (push ',action *current-home-actions*) ',action)))))

(defmacro package-preference (&rest chain)
  "Declare the ordered list of :via methods to try for (package ...) forms
that don't specify :via explicitly.  E.g. (package-preference :flatpak :system).
Only usable inside DEFINE-HOME."
  `(setf *current-home-package-preference* ',chain))

(defmacro define-home (name &rest body)
  "Capture NAME, an optional :traits (...), and the remaining forms as a
thunk to be invoked later. Exactly one DEFINE-HOME form is allowed per
project; loading a second one simply replaces the captured thunk."
  (let (traits forms)
    (if (eq (car body) :traits)
        (setf traits (cadr body) forms (cddr body))
        (setf forms body))
    `(setf *current-home-thunk*
            (lambda ()
              (setf *current-home-name* ',name)
              (setf *current-home-traits* ',traits)
              (setf *current-home-use-features* nil)
              (setf *current-home-actions* nil)
              (setf *current-home-package-preference* nil)
              ,@forms
              (list :name ',name
                    :traits ',traits
                    :use-features (reverse *current-home-use-features*)
                    :actions (reverse *current-home-actions*)
                    :package-preference *current-home-package-preference*)))))

(defun run-current-home-thunk ()
  (unless *current-home-thunk*
    (error "No define-home form was loaded; nothing to resolve."))
  (funcall *current-home-thunk*))

(defmacro use-feature (feature-name &rest opts)
  "(use-feature :editor :via (if (fact :work-p) :emacs :vim)
                :custom (:username \"bob\" :useremail \"bob@mail.com\")
                :depends-on (...))
FEATURE-NAME and the :via form are evaluated at thunk-run time (after facts
are known); :custom and all other options are taken as literal data."
  (let* ((via-pos (position :via opts))
         (via-form (and via-pos (nth (1+ via-pos) opts)))
         ;; Strip :via from opts
         (opts-no-via (if via-pos
                          (append (subseq opts 0 via-pos)
                                  (subseq opts (+ via-pos 2)))
                          opts))
         ;; Extract and strip :custom
         (custom-pos (position :custom opts-no-via))
         (custom-plist (and custom-pos (nth (1+ custom-pos) opts-no-via)))
         (rest-opts (if custom-pos
                        (append (subseq opts-no-via 0 custom-pos)
                                (subseq opts-no-via (+ custom-pos 2)))
                        opts-no-via)))
    `(push (list* :feature ,feature-name
                  ,@(when via-form `(:via ,via-form))
                  ,@(when custom-plist `(:custom ',custom-plist))
                  ',rest-opts)
           *current-home-use-features*)))

(define-action-macro file :copy-file "user:file"
  :extra-plist (:to target))

(defmacro package (target &rest opts)
  "(package \"vim\" :disabled t) -> :package action, defaulting :via :system."
  (let* ((via (or (getf opts :via) :system))
         (opts (list* :via via opts))
         (loc (location-from-load-pathname)))
    (let ((action (list* :action :package :target target
                          (append opts (list :priority :user :source "user:package" :location loc)))))
      `(progn (push ',action *current-home-actions*) ',action))))

(defmacro direct-action (&rest args)
  "(direct-action :reason \"...\" (:action :package :target \"x\" ...) ...)
Each trailing form is already a literal action plist; :force is implied
since a user reached for the escape hatch deliberately."
  (let* ((reason-pos (position :reason args))
         (reason (and reason-pos (nth (1+ reason-pos) args)))
         (action-forms (if reason-pos (nthcdr (+ reason-pos 2) args) args))
         (loc (location-from-load-pathname)))
    `(dolist (a ',action-forms)
       (push (append (copy-list a)
                     (list :priority :user :force t
                           :source ,(format nil "direct-action: ~a" reason)
                           :location ',loc))
             *current-home-actions*))))

(define-action-macro directory      :ensure-dir    "user:directory")
(define-action-macro symlink        :symlink       "user:symlink")
(define-action-macro secret         :secret        "user:secret")
(define-action-macro env-var        :env-var       "user:env-var")
(define-action-macro config-lines   :config-lines  "user:config-lines")
(define-action-macro config-ini     :config-ini    "user:config-ini")
(define-action-macro config-env     :config-env    "user:config-env")

(define-action-macro user           :user          "user:user")
(define-action-macro group          :group         "user:group")
(define-action-macro authorized-key :authorized-key "user:authorized-key")
(define-action-macro permissions    :permissions   "user:permissions")
(define-action-macro mount          :mount         "user:mount")
(define-action-macro sysctl         :sysctl        "user:sysctl")
(define-action-macro kernel-module  :kernel-module "user:kernel-module")
(define-action-macro hostname       :hostname      "user:hostname")
(define-action-macro locale         :locale        "user:locale")
(define-action-macro firewall       :firewall      "user:firewall")
(define-action-macro cron           :cron          "user:cron")
(define-action-macro command        :command       "user:command")
(define-action-macro clone          :clone         "user:clone")
(define-action-macro stow           :stow          "user:stow")
