;;;; src/domain/action/action.lisp
;;;;
;;;; The ACTION CLOS object model (REFACTOR.org Action 2 -- "Make Action a
;;;; First-Class Object"). The base ACTION class plus a per-type subclass
;;;; hierarchy, behind the existing plist convention: plists remain the
;;;; external wire format (DSL macros, providers, export, plugin code), and
;;;; PLIST->ACTION / ACTION->PLIST in protocol.lisp bridge the two worlds.
;;;; Executors still receive plists this pass; the object layer is what
;;;; future steps migrate the executors onto gradually.
;;;;
;;;; Base-class slots mirror the universally-shared plist keys stamped by
;;;; the DSL and the pipeline (:action/:target/:priority/:depends-on/:source/
;;;; :location/:force/:disabled/:project-root/:asset-root). Type-specific
;;;; keys live on subclasses (see protocol.lisp's DEFINE-ACTION). An optional
;;;; ORIGINAL slot preserves the untouched input plist for lossless round
;;;; trips and for action types that have no subclass yet.

(in-package :linacs.core)

(defclass action ()
  ((type         :initarg :type         :initform nil :reader action-type)
   (target       :initarg :target       :initform nil :reader action-target)
   (priority     :initarg :priority     :initform :provider :reader action-priority)
   (depends-on   :initarg :depends-on   :initform nil :reader action-depends-on)
   (source       :initarg :source       :initform nil :reader action-source)
   (location     :initarg :location     :initform nil :reader action-location)
   (force        :initarg :force        :initform nil :reader action-force)
   (disabled     :initarg :disabled     :initform nil :reader action-disabled)
   (project-root :initarg :project-root :initform nil :reader action-project-root)
   ;; Generic file-metadata keys, read generically by every filesystem-family
   ;; executor via apply-file-ownership / set-file-mode (helpers.lisp): mode
   ;; (permission bits), owner (user name/UID), group (group name/GID).
   (mode          :initarg :mode         :initform nil :reader action-mode)
   (owner         :initarg :owner        :initform nil :reader action-owner)
   (group         :initarg :group        :initform nil :reader action-group)
   ;; NOTE: no :reader action-asset-root here -- that reader is a generic
   ;; whose plist method lives in pipeline.lisp (which loads later and owns
   ;; *asset-root* / *project-root*). The private accessor below lets
   ;; pipeline.lisp define the object method in the file that owns those
   ;; dynamic variables.
   (asset-root   :initarg :asset-root   :initform nil :accessor action-asset-root-slot)
   (original     :initarg :original     :initform nil :accessor action-original))
  (:documentation "Base class of the LINACS action object model. Works
alongside the plist convention: PLIST->ACTION produces instances, and
unknown/plugin action types fall back to this generic class with the raw
plist preserved in ACTION-ORIGINAL."))