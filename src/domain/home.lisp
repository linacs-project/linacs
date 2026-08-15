;;;; src/domain/home.lisp
;;;;
;;;; The first-class HOME-DEFINITION value object (REFACTOR.org Thought 12 /
;;;; Action 17). The user DSL -- DEFINE-HOME and the home-level convenience
;;;; forms -- previously accumulated its output into dynamic variables that a
;;;; thunk flattened into a bare plist `(:name ... :traits ... :actions ...)`.
;;;; This file gives that output an explicit representation: a HOME-DEFINITION
;;;; instance carrying the home's name, traits, asset-root, use-feature
;;;; requests, user-level actions, and package-preference chain, which feeds
;;;; resolution (REFACTOR.org Execution Model step 2).
;;;;
;;;; The DSL must not expose CLOS to users (thought 12's stated goal): this
;;;; class is core-internal -- exported from :linacs.core, deliberately NOT
;;;; re-exported through :linacs.api -- and is only ever constructed by the
;;;; thunk captured in DEFINE-HOME (src/dsl.lisp) and read by the pipeline
;;;; and CLI via the HOME-DEFINITION-* readers.
;;;;
;;;; This loads before src/dsl.lisp so the DEFINE-HOME thunk can construct
;;;; instances (see linacs.asd).

(in-package :linacs.core)

(defclass home-definition ()
  ((name               :initarg :name               :reader home-definition-name
                       :documentation "The home's name (a keyword, e.g. :MY-HOME).")
   (traits             :initarg :traits             :initform nil :reader home-definition-traits
                       :documentation "Global policy flags for this home (e.g.
:PRUNE-EXPLICITLY-DISABLED), set via DEFINE-HOME's :traits option.")
   (asset-root         :initarg :asset-root         :initform nil :reader home-definition-asset-root
                       :documentation "A path relative to the project root under
which :from sources and stow packages resolve; NIL means the project root
itself (DEFINE-HOME's :asset-root option).")
   (use-features       :initarg :use-features       :initform nil :reader home-definition-use-features
                       :documentation "The USE-FEATURE request plists in
declaration order, each (:feature ... :via ... :custom ...).")
   (actions            :initarg :actions            :initform nil :reader home-definition-actions
                       :documentation "User-level action plists (from FILE, PACKAGE,
SECRET, ...) in declaration order, stamped with :priority :user.")
   (package-preference :initarg :package-preference :initform nil :reader home-definition-package-preference
                       :documentation "The ordered chain of :via methods to try for
PACKAGE forms without an explicit :via, or NIL for the default (:SYSTEM)."))
  (:documentation "The explicit output of the user DSL: a single DEFINE-HOME's
declared intent -- name, traits, asset-root, use-feature requests, user-level
actions, and package-preference chain -- that feeds resolution. Never exposed
to users as CLOS; constructed by the DEFINE-HOME thunk and read via the
HOME-DEFINITION-* readers by the pipeline and CLI."))

(defun make-home-definition (&key name traits asset-root use-features actions package-preference)
  "Construct a HOME-DEFINITION from its parts. USE-FEATURES and ACTIONS are
expected in declaration order; TRAITS defaults to NIL (no traits), ASSET-ROOT
to NIL (the project root itself), and PACKAGE-PREFERENCE to NIL (the
:SYSTEM chain)."
  (make-instance 'home-definition
                 :name name
                 :traits traits
                 :asset-root asset-root
                 :use-features use-features
                 :actions actions
                 :package-preference package-preference))
