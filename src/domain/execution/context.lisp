;;;; src/domain/execution/context.lisp
;;;;
;;;; Execution context (REFACTOR.org Action 4). A single CLOS object owns
;;;; the execution-scope state that used to live in dynamic globals --
;;;; facts, project root, asset root, the results table, provenance, and
;;;; the progress/capture controls -- so an execution can be constructed
;;;; and run in isolation (tests build a context directly, no global
;;;; binding), while production keeps its dynamic bindings via
;;;; WITH-EXECUTION-CONTEXT for backwards compatibility.
;;;;
;;;; The dynamic variables still exist (below) as the compatibility
;;;; channel: EXECUTE-ACTION / EXECUTE-PLAN bind them FROM the context for
;;;; the duration of a run, and the 26 plist executors keep reading them
;;;; unchanged. When no context is in play, behavior is identical to
;;;; before this module existed.

(in-package :linacs.core)

(defvar *execution-context* nil
  "The active EXECUTION-CONTEXT, dynamically bound by
WITH-EXECUTION-CONTEXT for the duration of an executor call, or NIL when
executing under the plain dynamic globals. Context combinators
(CONTEXT-FACTS, CONTEXT-RESULTS, ...) read through this.")

(defvar *project-root* "."
  "The project root, bound to the -C/--root value during resolution (step
2 of the Execution Model) and execution. Providers and pipeline hooks
read it to locate the project's assets -- e.g. deciding whether
<name>/ exists for stow mode -- instead of (truename \".\"), which
is wrong whenever linacs is invoked with -C from a different cwd.
Provider actions are also tagged with an equivalent :project-root plist
entry so the file-related executors (:copy-file, :stow, ...) resolve
their :from/:target sources under it at execution time.")

(defvar *asset-root* #P"./"
  "The asset root: where :from sources and stow packages resolve, relative
to the project root. Defaults to the project root itself (the convention
is plain repo-root packages -- there is no files/ directory). A home may
override it via DEFINE-HOME's :asset-root option -- e.g. :asset-root \"..\"
when the linacs machinery lives in a linacs/ subfolder of a dotfiles repo
whose packages sit at the repo root. RESOLVE-PLAN binds it to the
absolute, canonicalized path for the whole resolution + execution scope
and stamps it onto every action as :asset-root so executors resolve under
it at execution time.")

(defvar *provenance* (make-hash-table :test 'equal)
  "Maps action identity -> provenance plist (:feature :provider :facts-snapshot
or :source :location for user-level actions). Populated during pipeline step 2
and never consulted in normal operation -- zero overhead during execution.")

(defvar *action-results* (make-hash-table :test 'equal)
  "Maps action identity -> result plist (:status :applied :already-met :failed
or :skipped, and optionally :error for failures). Populated during pipeline
step 5 by EXECUTE-ACTION. Used by --continue mode.")

(defvar *progress-reporter* nil
  "When non-nil, a function of (action phase &optional data) called by
EXECUTE-ACTION before and after each action execution.  PHASE is :BEFORE,
:AFTER, or :FAILED.  For :AFTER, DATA is the result plist.  For
:FAILED, DATA is the condition.")

(defvar *current-action* nil
  "The action plist currently being executed, dynamically bound by
EXECUTE-ACTION for the duration of an executor call. Read by the
subprocess capture path (helpers.lisp) so ACTION-OUTPUT events can tag
the output chunks with the action that produced them; NIL outside any
executor call.")

(defvar *capture-subprocess-output* nil
  "When non-nil, RUN-PRIVILEGED in helpers.lisp captures subprocess stdout/stderr
into *CAPTURED-SUBPROCESS-LINES* instead of passing them through to the terminal.
Used by `linacs apply` to show live progress glyphs without subprocess noise.")

(defvar *captured-subprocess-lines* nil
  "List of (stream-type . string) entries captured during subprocess execution
when *CAPTURE-SUBPROCESS-OUTPUT* is non-nil.  Reset per-action in
EXECUTE-ACTION.  Stream-type is :STDOUT or :STDERR.")

(defclass execution-context ()
  ((facts     :initarg :facts     :initform nil :reader execution-context-facts)
   (project-root :initarg :project-root :initform nil
                 :reader execution-context-project-root)
   (asset-root   :initarg :asset-root   :initform nil
                 :reader execution-context-asset-root)
   (results   :initarg :results   :initform nil :reader execution-context-results)
   (provenance :initarg :provenance :initform nil
               :reader execution-context-provenance)
   (progress-reporter :initarg :progress-reporter :initform nil
                      :reader execution-context-progress-reporter)
   (capture-subprocess-output :initarg :capture-subprocess-output :initform nil
                              :reader execution-context-capture-subprocess-output))
  (:documentation "Owns the execution-scope state for one run: facts,
project/asset roots, the results and provenance tables, and the
progress/capture controls. Construct via MAKE-EXECUTION-CONTEXT (seeded
from the current dynamic globals) and run executors under it with
WITH-EXECUTION-CONTEXT, or pass it through EXECUTE-PLAN/EXECUTE-ACTION's
:CONTEXT argument."))

(defun make-execution-context (&key facts project-root asset-root results provenance
                                  progress-reporter capture-subprocess-output)
  "Construct an EXECUTION-CONTEXT.  Any slot not supplied is seeded from
the current dynamic globals (*FACTS*, *PROJECT-ROOT*, *ASSET-ROOT*,
*ACTION-RESULTS*, *PROVENANCE*, *PROGRESS-REPORTER*,
*CAPTURE-SUBPROCESS-OUTPUT*), so a bare (make-execution-context) captures
today's whole environment and behavior is unchanged."
  (make-instance 'execution-context
                 :facts (or facts *facts*)
                 :project-root (or project-root *project-root*)
                 :asset-root (or asset-root *asset-root*)
                 :results (or results *action-results*)
                 :provenance (or provenance *provenance*)
                 :progress-reporter (or progress-reporter *progress-reporter*)
                 :capture-subprocess-output (or capture-subprocess-output
                                              *capture-subprocess-output*)))

(defmacro with-execution-context (context &body body)
  "Bind the execution dynamic globals from CONTEXT (an EXECUTION-CONTEXT)
for the duration of BODY, so executors that read *FACTS*, *PROJECT-ROOT*,
*ASSET-ROOT*, *ACTION-RESULTS*, *PROVENANCE*, *PROGRESS-REPORTER*, and
*CAPTURE-SUBPROCESS-OUTPUT* see the context's state.  Slots that are NIL
fall through to the ambient dynamic value.  Establishes *EXECUTION-CONTEXT*
so the CONTEXT-* combinators resolve too.  A NIL CONTEXT is a no-op: the
historic dynamic globals remain in effect (useful for defaulted &key args
such as EXECUTE-PLAN's)."
  (let ((ctx (gensym "CTX")))
    `(let ((,ctx ,context))
       (if ,ctx
           (let ((*execution-context* ,ctx)
                 (*facts* (or (execution-context-facts ,ctx) *facts*))
                 (*project-root* (or (execution-context-project-root ,ctx) *project-root*))
                 (*asset-root* (or (execution-context-asset-root ,ctx) *asset-root*))
                 (*action-results* (or (execution-context-results ,ctx) *action-results*))
                 (*provenance* (or (execution-context-provenance ,ctx) *provenance*))
                 (*progress-reporter* (or (execution-context-progress-reporter ,ctx)
                                          *progress-reporter*))
                 (*capture-subprocess-output*
                  (or (execution-context-capture-subprocess-output ,ctx)
                      *capture-subprocess-output*)))
             ,@body)
           (let ((*execution-context* *execution-context*))
             ,@body)))))

(defun context-facts ()
  "The facts of the active execution context, else *FACTS*."
  (if *execution-context*
      (execution-context-facts *execution-context*)
      *facts*))

(defun context-project-root ()
  "The project root of the active execution context, else *PROJECT-ROOT*."
  (if *execution-context*
      (execution-context-project-root *execution-context*)
      *project-root*))

(defun context-asset-root ()
  "The asset root of the active execution context, else *ASSET-ROOT*."
  (if *execution-context*
      (execution-context-asset-root *execution-context*)
      *asset-root*))

(defun context-results ()
  "The results table of the active execution context, else *ACTION-RESULTS*."
  (if *execution-context*
      (or (execution-context-results *execution-context*) *action-results*)
      *action-results*))

(defun context-provenance ()
  "The provenance table of the active execution context, else *PROVENANCE*."
  (if *execution-context*
      (or (execution-context-provenance *execution-context*) *provenance*)
      *provenance*))

(defun context-progress-reporter ()
  "The progress reporter of the active execution context, else *PROGRESS-REPORTER*."
  (if *execution-context*
      (or (execution-context-progress-reporter *execution-context*) *progress-reporter*)
      *progress-reporter*))
