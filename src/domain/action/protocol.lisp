;;;; src/domain/action/protocol.lisp
;;;;
;;;; The action object-model protocol (REFACTOR.org Action 2). On top of the
;;;; base ACTION class this provides:
;;;;
;;;;   * *ACTION-CLASSES* -- the action-type keyword -> class map, and the
;;;;     DEFINE-ACTION helper that registers a per-type subclass with typed
;;;;     accessors,
;;;;   * PLIST->ACTION / MAKE-ACTION -- build instances from the plist
;;;;     convention (the DSL, providers, export, and plugin wire format),
;;;;   * the ACTION->PLIST object method -- reconstructs a plist from an
;;;;     instance's slots, canonicalizing the historical :TO/:TARGET
;;;;     inconsistency (dsl.lisp's FILE form emits both; see REFACTOR
;;;;     Action 2),
;;;;   * object methods for the shared accessor generics (ACTION-IDENTITY,
;;;;     ACTION-SOURCE-LABEL, SAME-ACTION-CONTENT-P) so ACTION instances are
;;;;     first-class citizens of identity, dedup, and conflict reporting.
;;;;
;;;; Executors still receive plists this pass: EXECUTE-ACTION converts an
;;;; ACTION instance back via ACTION->PLIST before dispatching. Future
;;;; actions migrate the executors themselves onto the object protocol.

(in-package :linacs.core)

(defvar *action-classes* (make-hash-table :test 'eq)
  "Maps action type keyword -> class name symbol (an ACTION subclass, or the
base ACTION class for types with no registered subclass).")

(defvar *action-slot-maps* (make-hash-table :test 'eq)
  "Maps class name symbol -> alist of (plist-key . slot-name). Declared by
DEFINE-ACTION; used by PLIST->ACTION to map plist keys onto constructor
initargs and by ACTION->PLIST to reconstruct them back.")

(defvar *action-absorb-keys* (make-hash-table :test 'eq)
  "Maps class name symbol -> list of plist keys to drop on ACTION->PLIST
output. Used to absorb redundant aliases: :COPY-FILE historically carried
both :TO and :TARGET with the same value (dsl.lisp's FILE form); the
canonical plist keeps only :TARGET.")

(defun register-action-class (type class-name &optional slot-map absorb-keys)
  "Programmatically twin of DEFINE-ACTION's registration half: associate
TYPE with the ACTION subclass named CLASS-NAME, recording SLOT-MAP (alist of
(plist-key . slot-name)) and ABSORB-KEYS for round trips."
  (setf (gethash type *action-classes*) class-name)
  (when slot-map (setf (gethash class-name *action-slot-maps*) slot-map))
  (when absorb-keys (setf (gethash class-name *action-absorb-keys*) absorb-keys))
  class-name)

(defun action-type->class (type)
  (or (gethash type *action-classes*)
      'action))

(defun plist->action (plist)
  "Build an ACTION instance from PLIST. Dispatches on :ACTION to the
registered subclass, or falls back to the base ACTION class (preserving the
raw plist in ACTION-ORIGINAL for unknown/plugin types). Base initargs
(:priority :depends-on :source :location :force :disabled :project-root
:asset-root) pass through only when present in PLIST, so the CLASS's
initforms (e.g. priority :provider) act as defaults. Type-specific plist
keys go through the *ACTION-SLOT-MAPS* initargs -- this is where the
:TO-vs-:TARGET semantics are decided per subclass."
  (let* ((type (action-type plist))
         (class-name (action-type->class type))
         (class (find-class class-name))
         (slot-map (gethash (class-name class) *action-slot-maps*))
         (base-keys '(:priority :depends-on :source :location :force
                      :disabled :project-root :asset-root :mode :owner :group))
         (base-initargs (loop for key in base-keys
                              when (member key plist)
                                append (list key (getf plist key))))
         (slot-initargs (loop for (key . slot) in slot-map
                              when (member key plist)
                                append (list key (getf plist key)))))
    (apply #'make-instance class
           (append base-initargs slot-initargs
                   (list :type type
                         :target (action-target plist)
                         :original (copy-list plist))))))

(defmethod action->plist ((action action))
  "Reconstruct the canonical plist for an ACTION instance. Starts from the
preserved ACTION-ORIGINAL (lossless for unknown/plugin keys), then overrides
:action and :target from the canonical slots and each modeled plist key from
its slot, finally dropping keys in *ACTION-ABSORB-KEYS* (the :TO/:TARGET
canonicalization)."
  (let* ((class-name (class-name (class-of action)))
         (slot-map (gethash class-name *action-slot-maps*))
         (absorb-keys (gethash class-name *action-absorb-keys*))
         (out (copy-list (or (action-original action)
                             (list :action (action-type action)
                                   :target (action-target action))))))
    (setf (getf out :action) (action-type action))
    (setf (getf out :target) (action-target action))
    (dolist (entry slot-map)
      (let ((key (car entry)) (slot (cdr entry)))
        (when (slot-value action slot)
          (setf (getf out key) (slot-value action slot)))))
    (dolist (key absorb-keys)
      (remf out key))
    out))

(defun make-action (&rest args)
  "Construct an ACTION instance. Accepts either a single action plist:
    (make-action '(:action :copy-file :target \"~/.x\" :from \"x\"))
  or keyword arguments in plist form:
    (make-action :action :copy-file :target \"~/.x\" :from \"x\")
  Returns the appropriate subclass instance via PLIST->ACTION."
  (let ((plist (if (and (= (length args) 1) (listp (first args)))
                   (first args)
                   args)))
    (plist->action plist)))

(defmethod action-identity ((action action))
  "Identity of an ACTION instance: delegate to the plist protocol so the
registered identity functions in *ACTION-IDENTITY-FUNCTIONS* keep working
unchanged."
  (action-identity (action->plist action)))

(defmethod action-source-label ((action action))
  (or (action-source action) "unspecified"))

(defmethod same-action-content-p ((a action) (b action))
  (same-action-content-p (action->plist a) (action->plist b)))

(defmethod same-action-content-p ((a action) (b list))
  (same-action-content-p (action->plist a) b))

(defmethod same-action-content-p ((a list) (b action))
  (same-action-content-p a (action->plist b)))

(defmethod action-description ((action action))
  (action-description (action->plist action)))

(defmethod action-dedup-behavior ((action action))
  (action-dedup-behavior (action->plist action)))

(defmethod execute-action ((action action) &key (mode :apply) context)
  "EXECUTE-ACTION for an ACTION instance: delegate to the plist method via
ACTION->PLIST, so executors (which still speak plists) see exactly the same
action as for a plist caller. CONTEXT is an optional EXECUTION-CONTEXT
forwarded to the plist method."
  (execute-action (action->plist action) :mode mode :context context))

;;; --- Per-type subclasses (pilot set) -------------------------------

(defmacro define-action (class-name kind &key absorb-keys slots)
  "Define CLASS-NAME as an ACTION subclass for action-type KIND. SLOTS is a
list of (slot-name initarg-key accessor-name); each spec registers the slot
on the class and the keyword->slot mapping PLIST->ACTION / ACTION->PLIST
use. ABSORB-KEYS are plist keys dropped from canonical ACTION->PLIST output
(e.g. the historical :TO/:TARGET alias on :copy-file). Registers KIND ->
CLASS-NAME in *ACTION-CLASSES*."
  `(progn
     (defclass ,class-name (action)
       ,(mapcar (lambda (spec)
                  (destructuring-bind (slot initarg accessor) spec
                    `(,slot :initarg ,initarg :initform nil :reader ,accessor)))
                slots))
     (register-action-class ,kind ',class-name
                            ',(mapcar (lambda (spec)
                                        (destructuring-bind (slot initarg accessor) spec
                                          (declare (ignore accessor))
                                          (cons initarg slot)))
                                      slots)
                            ',absorb-keys)
     ',class-name))

(define-action package-action :package
  :slots ((via            :via              package-action-via)
          (scope          :scope            package-action-scope)
          (remote         :remote           package-action-remote)
          (remote-url     :remote-url       package-action-remote-url)
          (container-name :container-name   package-action-container-name)
          (as             :as               package-action-as)))

(define-action copy-file-action :copy-file
  :absorb-keys (:to)
  :slots ((from     :from     copy-file-from)
          (content  :content  copy-file-content)
          (template :template copy-file-template)
          (renderer :renderer copy-file-renderer)
          (secrets  :secrets  copy-file-secrets)))

(define-action ensure-dir-action :ensure-dir
  :slots nil)

(define-action service-action :service
  :slots ((enabled :enabled service-enabled)
          (running :running service-running)))

(define-action symlink-action :symlink
  :slots ((destination :to symlink-destination)))

(define-action stow-action :stow
  :slots ((from        :from        stow-from)
          (target-root :to          stow-target-root)))

(define-action timer-action :timer
  :slots ((on-calendar :on-calendar timer-on-calendar)))

(define-action env-var-action :env-var
  :slots ((value :value env-var-value)
          (file  :file  env-var-file)))

(define-action config-lines-action :config-lines
  :slots ((ensure :ensure config-lines-ensure)
          (remove :remove config-lines-remove)))

(define-action config-ini-action :config-ini
  :slots ((section :section config-ini-section)
          (set     :set     config-ini-set)
          (unset   :unset   config-ini-unset)))

(define-action config-env-action :config-env
  :slots ((set :set config-env-set)))

(define-action secret-action :secret
  :slots ((from     :from     secret-from)
          (path     :path     secret-path)
          (message  :message  secret-message)
          (template :template secret-template)
          (renderer :renderer secret-renderer)
          (secrets  :secrets  secret-secrets)))

(define-action user-action :user
  :slots ((uid         :uid         user-uid)
          (gid         :gid         user-gid)
          (shell       :shell       user-shell)
          (home        :home        user-home)
          (create-home :create-home user-create-home)
          (system      :system      user-system)
          (locked      :locked      user-locked)
          (remove-home :remove-home user-remove-home)))

(define-action group-action :group
  :slots ((gid :gid group-action-gid)))

(define-action authorized-key-action :authorized-key
  :slots ((key     :key     authorized-key-key)
          (comment :comment authorized-key-comment)))

(define-action permissions-action :permissions
  :slots ((recursive :recursive permissions-recursive)))

(define-action mount-action :mount
  :slots ((device  :device  mount-device)
          (fstype  :fstype  mount-fstype)
          (options :options mount-options)
          (dump    :dump    mount-dump)
          (pass    :pass    mount-pass)))

(define-action sysctl-action :sysctl
  :slots ((value :value sysctl-value)
          (file  :file  sysctl-file)))

(define-action kernel-module-action :kernel-module
  :slots ((state :state kernel-module-state)))

(define-action hostname-action :hostname
  :slots nil)

(define-action locale-action :locale
  :slots ((timezone :timezone locale-timezone)))

(define-action firewall-action :firewall
  :slots ((protocol :protocol firewall-protocol)
          (allow    :allow    firewall-allow)))

(define-action cron-action :cron
  :slots ((schedule :schedule cron-schedule)
          (user     :user     cron-user)
          (command  :command  cron-command)))

(define-action command-action :command
  :slots ((run         :run         command-run)
          (creates     :creates     command-creates)
          (unless      :unless      command-unless)
          (only-if     :only-if     command-only-if)
          (sudo        :sudo        command-sudo)
          (remove-run  :remove-run  command-remove-run)))

(define-action clone-action :clone
  :slots ((url    :url    clone-url)
          (branch :branch clone-branch)
          (depth  :depth  clone-depth)))

(define-action repository-action :repository
  :slots ((method :method repository-method)))