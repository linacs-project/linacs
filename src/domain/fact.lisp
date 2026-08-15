;;;; src/domain/fact.lisp
;;;;
;;;; First-class FACT-SOURCE and FACT value objects (REFACTOR.org Thought 14
;;;; / Action 14). A FACT-SOURCE answers "how do I discover this?" -- the
;;;; probe function (if any), the registrant, and the declared :type/:doc
;;;; metadata. A FACT answers "what did I discover, and how much do I trust
;;;; it?" -- the resolved value plus confidence (:probed / :profile /
;;;; :platform) and the source that produced it.
;;;;
;;;; The registries live in src/facts.lisp: *FACT-SOURCES* maps a fact key
;;;; to a FACT-SOURCE, *FACT-OBJECTS* maps it to the run's FACT. *FACTS*
;;;; remains a plain plist of values -- the wire format providers and
;;;; templates receive -- so a provider's `(getf facts :key)` keeps working
;;;; (linacs-security, linacs-editor, and friends rely on it).
;;;;
;;;; This loads before src/facts.lisp so the registries can store instances
;;;; (see linacs.asd).

(in-package :linacs.core)

(defclass fact-source ()
  ((name       :initarg :name       :reader fact-source-name
               :documentation "The fact key (a keyword, e.g. :OS).")
   (probe-fn   :initarg :probe-fn   :initform nil :reader fact-source-probe-fn
               :documentation "The zero-argument probe function; NIL for a
declared-only fact (see DECLARE-FACT-SOURCE).")
   (registrant :initarg :registrant :initform nil :reader fact-source-registrant
               :documentation "Who registered this source (a package name or
\"linacs-core\"), shown in conflict messages and `linacs list`.")
   (type       :initarg :type       :initform nil :reader fact-source-type
               :documentation "A CL type specifier checked at probe time.")
   (doc        :initarg :doc        :initform nil :reader fact-source-doc
               :documentation "Human-readable description, shown by `linacs list`."))
  (:documentation "How one fact is discovered: the probe function, its
registrant, and the declared :type/:doc metadata. Distinguishes 'how do I
discover this?' (the source) from 'what did I discover?' (a FACT)."))

(defclass fact ()
  ((name       :initarg :name       :reader fact-name
               :documentation "The fact key (a keyword, e.g. :OS).")
   (value      :initarg :value      :reader fact-value
               :documentation "The resolved value.")
   (confidence :initarg :confidence :initform :probed :reader fact-confidence
               :documentation "How this value was obtained: :PROBED from a
prober, :PROFILE from a profile override, :PLATFORM from --platform.")
   (source     :initarg :source     :initform nil :reader fact-source-of
               :documentation "What produced the value: the FACT-SOURCE for a
probed fact, the profile name for a profile override, or :PLATFORM."))
  (:documentation "One resolved fact for the current run: the value plus
confidence and source, for provenance reporting."))

(defun make-fact-source (&key name probe-fn registrant type doc)
  "Construct a FACT-SOURCE from its parts."
  (make-instance 'fact-source
                 :name name :probe-fn probe-fn
                 :registrant registrant :type type :doc doc))

(defun make-fact (&key name value (confidence :probed) source)
  "Construct a FACT from its parts. CONFIDENCE is :PROBED unless overridden."
  (make-instance 'fact
                 :name name :value value
                 :confidence confidence :source source))

(defun fact-source-p (x)
  "T if X is a FACT-SOURCE instance."
  (typep x 'fact-source))

(defun fact-p (x)
  "T if X is a FACT instance."
  (typep x 'fact))
