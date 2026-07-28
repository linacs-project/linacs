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

(defun location-from-load-pathname ()
  "Capture the file being loaded at macroexpansion time."
  (list :file (or (ignore-errors (namestring *load-pathname*))
                  (ignore-errors (namestring *compile-file-pathname*))
                  "<unknown>")))

(defmacro define-action-macro (name action-type source &key extra-plist)
  `(defmacro ,name (target &rest opts)
     (let* ((loc (location-from-load-pathname))
            (action (list* :action ,action-type :target target
                           ,@extra-plist
                           (append opts
                                   (list :priority :user :source ,source :location loc)))))
       `(progn (push ',action *current-home-actions*) ',action))))

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
