;;;; src/discovery/registry.lisp
;;;;
;;;; The fact registry and probing driver (REFACTOR.org Thought 14 / 23,
;;;; Action 18). A Fact is a probed or profile-overridden truth about the
;;;; current machine (:os, :hostname, :laptop-p, :display-server, and
;;;; anything a provider author adds); *FACTS* holds the resolved plist
;;;; for the current run.
;;;;
;;;; This file holds the registries (*FACT-SOURCES*, *FACT-OBJECTS*,
;;;; *FACTS*, *FACTS-READ*), the REGISTER-FACT-SOURCE /
;;;; DECLARE-FACT-SOURCE registration seam, the PROBE-ALL-FACTS driver,
;;;; and the FACT / FACT* / FACT-KNOWN-P readers. The built-in probe
;;;; implementations live in probers.lisp; the registrations of the
;;;; built-in facts (the sources LINACS always probes) live in
;;;; fact-sources.lisp. The FACT-SOURCE and FACT classes themselves live
;;;; in src/domain/fact.lisp, loaded before this file.
;;;;
;;;; Usage:
;;;;   Reading a fact, from inside a home definition or a provider:
;;;;
;;;;     (fact :laptop-p)
;;;;
;;;;   Registering a new one, typically from a project's providers/ file:
;;;;
;;;;     (register-fact-source :gpu (lambda () (if (probe-file "...") :nvidia :unknown)))

(in-package :linacs.core)

(defvar *fact-sources* (make-hash-table :test 'eq)
  "Maps fact key -> FACT-SOURCE object (probe function, registrant, type,
doc). Populated by REGISTER-FACT-SOURCE and DECLARE-FACT-SOURCE.")

(defvar *fact-objects* (make-hash-table :test 'eq)
  "Maps fact key -> FACT object for the current run. Populated by
PROBE-ALL-FACTS (confidence :PROBED), APPLY-PROFILE (:PROFILE) and
APPLY-PLATFORM-OVERRIDE (:PLATFORM). Used for provenance reporting; the
value plist *FACTS* is derived from it.")

(defvar *facts* nil
  "Plist of resolved fact values, populated by PROBE-ALL-FACTS and merged
with a profile's overrides. Read via FACT. This stays a plist of plain
values because it is the wire format providers and templates receive --
a provider's `(getf facts :key)` must keep returning a value.")

(defvar *facts-read* (make-hash-table :test 'eq)
  "Set of fact keys read during the current provider invocation. Populated
by FACT* and reset before each provider call. Used for provenance tracking
so the :facts-snapshot only includes facts the provider actually consulted.")

(defun register-fact-source (key prober-fn &optional (registrant (package-name *package*))
                             &key type doc)
  "Register a fact source for KEY -- a probe function plus its registrant
and optional :TYPE/:DOC metadata. If a different registrant already
registered a source for the same KEY, signal FACT-PROBER-CONFLICT and abort
startup -- there is no implicit first-one-wins resolution.

Optional keyword arguments:
  :TYPE -- a CL type specifier checked at probe time (via TYPEP) for
           informative warnings when the prober returns an unexpected value.
  :DOC  -- a human-readable description shown by `linacs list`."
  (let ((existing (gethash key *fact-sources*)))
    (when (and existing (not (string= (fact-source-registrant existing) registrant)))
      (error 'fact-prober-conflict
             :fact-key key
             :registrants (list (fact-source-registrant existing) registrant)))
    (setf (gethash key *fact-sources*)
          (make-fact-source :name key :probe-fn prober-fn
                            :registrant registrant :type type :doc doc)))
  key)

(defun declare-fact-source (key &key type doc)
  "Document a fact key that has no prober -- e.g. a profile-only fact like
:work-p or :languages -- without registering one. Registers a FACT-SOURCE
with no probe function, so `linacs list` shows the fact and APPLY-PROFILE
does not warn on it as a possible typo. Same metadata keywords as
REGISTER-FACT-SOURCE: :TYPE (a CL type specifier) and :DOC (a
human-readable description)."
  (setf (gethash key *fact-sources*)
        (make-fact-source :name key :registrant nil :type type :doc doc))
  key)

(defun probe-all-facts ()
  "Run every registered fact source probe once and populate *FACT-OBJECTS*
with FACT instances (confidence :PROBED), then derive the *FACTS* value
plist from them. Validates each probed value against its declared :type (if
one exists), logging a warning on mismatch via `linacs.log:warn*`."
  (clrhash *fact-objects*)
  (maphash (lambda (key source)
             (when (fact-source-probe-fn source)
               (let ((value (funcall (fact-source-probe-fn source))))
                 (when (and (fact-source-type source)
                            (not (typep value (fact-source-type source))))
                   (linacs.log:warn* "Fact ~s returned ~s (type ~s), which does not match declared type ~s"
                                     key value (type-of value) (fact-source-type source)))
                 (setf (gethash key *fact-objects*)
                       (make-fact :name key :value value
                                  :confidence :probed :source source)))))
           *fact-sources*)
  (refresh-facts-plist)
  *facts*)

(defun refresh-facts-plist ()
  "Rebuild *FACTS* -- the value plist -- from *FACT-OBJECTS*. Called after
every mutation of the fact store so the provider/template wire format stays
in sync with the FACT objects."
  (let ((result '()))
    (maphash (lambda (key fact)
               (setf result (list* key (fact-value fact) result)))
             *fact-objects*)
    (setf *facts* result)))

(defun set-fact (key value &key (confidence :probed) source)
  "Record KEY => VALUE as a FACT in *FACT-OBJECTS* with CONFIDENCE and
SOURCE, then refresh the *FACTS* value plist. Shared by the probe, profile
and platform-override paths."
  (setf (gethash key *fact-objects*)
        (make-fact :name key :value value :confidence confidence :source source))
  (refresh-facts-plist)
  value)

(defun apply-platform-override (platform)
  "Override the :os fact from the CLI's --platform NAME flag. Applied after
PROBE-ALL-FACTS and APPLY-PROFILE so the explicitly-given command-line
platform wins over both the auto-probe and any profile override. NAME is a
raw string (e.g. \"fedora\", \"arch\", \"ubuntu\"), interned to a keyword;
returns *FACTS*. A NIL PLATFORM is a no-op."
  (when platform
    (set-fact :os (intern (string-upcase platform) :keyword)
              :confidence :platform :source :platform))
  *facts*)

(defun fact (key)
  "Read a fact by keyword. Reflects probed values merged with any
profile override -- the home definition cannot distinguish the two.
Returns NIL for both \"key probed with value NIL\" and \"key never
probed\"; use FACT-KNOWN-P to distinguish."
  (getf *facts* key))

(defun fact-known-p (key)
  "T if KEY exists in *FACTS* (was probed or profile-overridden),
regardless of its value.  Returns NIL if KEY was never probed
(e.g. a misspelling or a prober that was never registered)."
  (let ((sentinel (make-symbol "FACT-NOT-FOUND")))
    (not (eq sentinel (getf *facts* key sentinel)))))

(defun fact* (key)
  "Like FACT but also records KEY in *FACTS-READ* for provenance tracking.
Provider authors should use this instead of FACT when the provider wants
its fact dependencies to appear in the :facts-snapshot provenance field.
Using plain FACT is still fine for internal code that shouldn't appear
in provenance traces."
  (setf (gethash key *facts-read*) t)
  (getf *facts* key))

(defun reset-facts-read ()
  "Clear *FACTS-READ*. Called before each provider invocation."
  (clrhash *facts-read*))

(defun snapshot-facts-read ()
  "Return the list of fact keys read since the last RESET-FACTS-READ,
suitable for embedding in a :facts-snapshot provenance plist."
  (loop for k being the hash-key of *facts-read* collect k))
