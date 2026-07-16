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
             ,@forms
             (list :name ',name
                   :traits ',traits
                   :use-features (reverse *current-home-use-features*)
                   :actions (reverse *current-home-actions*))))))

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

(defmacro %push-user-action (source-label action-type target-key target &rest opts)
  "Shared machinery for the home-level convenience macros. All of ACTION-TYPE,
TARGET, and OPTS are macro-time literal data; only TARGET-KEY varies by form
 (:target for most types, but :copy-file uses :to for its primary path)."
  (let ((action (list* :action action-type target-key target (append opts (list :priority :user :source source-label)))))
    `(push ',action *current-home-actions*)))

(defmacro file (target &rest opts)
  "(file \"~/.gitconfig\" :from \"gitconfig\" ...) -> :copy-file action."
  (let ((action (list* :action :copy-file :target target :to target
                       (append opts (list :priority :user :source "user:file")))))
    `(push ',action *current-home-actions*)))

(defmacro directory (target &rest opts)
  "(directory \"~/.ssh\" :mode #o700) -> :ensure-dir action."
  (let ((action (list* :action :ensure-dir :target target
                       (append opts (list :priority :user :source "user:directory")))))
    `(push ',action *current-home-actions*)))

(defmacro symlink (target &rest opts)
  "(symlink \"~/.emacs.d\" :to \"~/.config/emacs\") -> :symlink action."
  (let ((action (list* :action :symlink :target target
                       (append opts (list :priority :user :source "user:symlink")))))
    `(push ',action *current-home-actions*)))

(defmacro package (target &rest opts)
  "(package \"vim\" :disabled t) -> :package action, defaulting :via :system."
  (let* ((via (or (getf opts :via) :system))
         (opts (list* :via via opts)))
    (let ((action (list* :action :package :target target
                         (append opts (list :priority :user :source "user:package")))))
      `(push ',action *current-home-actions*))))

(defmacro secret (target &rest opts)
  "(secret \"~/.ssh/id_ed25519\" :from :pass :path \"ssh/id_ed25519\") -> :secret action."
  (let ((action (list* :action :secret :target target
                       (append opts (list :priority :user :source "user:secret")))))
    `(push ',action *current-home-actions*)))

(defmacro env-var (target &rest opts)
  "(env-var \"EDITOR\" :value \"emacs\" :file \"~/.profile\") -> :env-var action."
  (let ((action (list* :action :env-var :target target
                       (append opts (list :priority :user :source "user:env-var")))))
    `(push ',action *current-home-actions*)))

(defmacro config-lines (target &rest opts)
  (let ((action (list* :action :config-lines :target target
                       (append opts (list :priority :user :source "user:config-lines")))))
    `(push ',action *current-home-actions*)))

(defmacro config-ini (target &rest opts)
  (let ((action (list* :action :config-ini :target target
                       (append opts (list :priority :user :source "user:config-ini")))))
    `(push ',action *current-home-actions*)))

(defmacro config-env (target &rest opts)
  (let ((action (list* :action :config-env :target target
                       (append opts (list :priority :user :source "user:config-env")))))
    `(push ',action *current-home-actions*)))

(defmacro direct-action (&rest args)
  "(direct-action :reason \"...\" (:action :package :target \"x\" ...) ...)
Each trailing form is already a literal action plist; :force is implied
since a user reached for the escape hatch deliberately."
  (let* ((reason-pos (position :reason args))
         (reason (and reason-pos (nth (1+ reason-pos) args)))
         (action-forms (if reason-pos (nthcdr (+ reason-pos 2) args) args)))
    `(dolist (a ',action-forms)
       (push (append (copy-list a)
                     (list :priority :user :force t
                           :source ,(format nil "direct-action: ~a" reason)))
             *current-home-actions*))))

;;; --- System administration convenience forms --------------------------
;;; Same literal-data convention as the forms above: arguments are taken
;;; as macro-time data, never evaluated as code.

(defmacro user (target &rest opts)
  "(user \"deploy\" :shell \"/bin/bash\" :create-home t) -> :user action."
  (let ((action (list* :action :user :target target
                       (append opts (list :priority :user :source "user:user")))))
    `(push ',action *current-home-actions*)))

(defmacro group (target &rest opts)
  "(group \"docker\" :gid 999) -> :group action."
  (let ((action (list* :action :group :target target
                       (append opts (list :priority :user :source "user:group")))))
    `(push ',action *current-home-actions*)))

(defmacro authorized-key (target &rest opts)
  "(authorized-key \"deploy\" :key \"ssh-ed25519 AAAA...\") -> :authorized-key action."
  (let ((action (list* :action :authorized-key :target target
                       (append opts (list :priority :user :source "user:authorized-key")))))
    `(push ',action *current-home-actions*)))

(defmacro permissions (target &rest opts)
  "(permissions \"/var/lib/mysql\" :owner \"mysql\" :group \"mysql\" :mode #o750) -> :permissions action."
  (let ((action (list* :action :permissions :target target
                       (append opts (list :priority :user :source "user:permissions")))))
    `(push ',action *current-home-actions*)))

(defmacro mount (target &rest opts)
  "(mount \"/mnt/data\" :device \"/dev/sdb1\" :fstype \"ext4\") -> :mount action."
  (let ((action (list* :action :mount :target target
                       (append opts (list :priority :user :source "user:mount")))))
    `(push ',action *current-home-actions*)))

(defmacro sysctl (target &rest opts)
  "(sysctl \"net.ipv4.ip_forward\" :value 1) -> :sysctl action."
  (let ((action (list* :action :sysctl :target target
                       (append opts (list :priority :user :source "user:sysctl")))))
    `(push ',action *current-home-actions*)))

(defmacro kernel-module (target &rest opts)
  "(kernel-module \"nfs\" :state :loaded) / (kernel-module \"usb-storage\" :state :blacklisted)."
  (let ((action (list* :action :kernel-module :target target
                       (append opts (list :priority :user :source "user:kernel-module")))))
    `(push ',action *current-home-actions*)))

(defmacro hostname (target &rest opts)
  "(hostname \"myhost.example.com\") -> :hostname action."
  (let ((action (list* :action :hostname :target target
                       (append opts (list :priority :user :source "user:hostname")))))
    `(push ',action *current-home-actions*)))

(defmacro locale (target &rest opts)
  "(locale \"en_US.UTF-8\" :timezone \"America/New_York\") -> :locale action."
  (let ((action (list* :action :locale :target target
                       (append opts (list :priority :user :source "user:locale")))))
    `(push ',action *current-home-actions*)))

(defmacro firewall (target &rest opts)
  "(firewall 22 :protocol \"tcp\" :allow t) -> :firewall action."
  (let ((action (list* :action :firewall :target target
                       (append opts (list :priority :user :source "user:firewall")))))
    `(push ',action *current-home-actions*)))

(defmacro cron (target &rest opts)
  "(cron \"nightly-backup\" :schedule \"0 2 * * *\" :command \"/usr/local/bin/backup.sh\") -> :cron action."
  (let ((action (list* :action :cron :target target
                       (append opts (list :priority :user :source "user:cron")))))
    `(push ',action *current-home-actions*)))

(defmacro command (target &rest opts)
  "(command \"clone dotfiles repo\" :run \"git clone ...\" :creates \"~/.dotfiles\") -> :command action."
  (let ((action (list* :action :command :target target
                       (append opts (list :priority :user :source "user:command")))))
    `(push ',action *current-home-actions*)))

(defmacro clone (target &rest opts)
  "(clone \"~/.dotfiles\" :url \"https://example.com/dotfiles.git\" :branch \"main\" :depth 1)
-> :clone action. Ensures a git repo is checked out at TARGET; a repeat
run checks the actual origin remote, not just whether TARGET exists."
  (let ((action (list* :action :clone :target target
                       (append opts (list :priority :user :source "user:clone")))))
    `(push ',action *current-home-actions*)))

(defmacro stow (target &rest opts)
  "(stow \"fish\") -> :stow action. Mirrors files/fish/** onto :to (default
~), folding whole directories when nothing exists yet and merging
file-by-file when the target already exists -- GNU-Stow style, with no
dependency on the stow binary."
  (let ((action (list* :action :stow :target target
                       (append opts (list :priority :user :source "user:stow")))))
    `(push ',action *current-home-actions*)))
