;;;; src/report.lisp
;;;;
;;;; The LINACS presentation layer (USERUX redesign, Phase 1): a set of pure
;;;; functions from a REPORT-CONTEXT -- the resolved plan, the facts, the
;;;; home definition, and the CLI options -- to human-readable output. Each
;;;; RENDER-* function returns a LIST OF LINES; it never prints, reads the
;;;; terminal, or mutates global state. This keeps the whole presentation
;;;; unit-testable without parsing stdout, and gives the future TUI views
;;;; (docs/tui-design.md) their content source for free.
;;;;
;;;; Phase 1 scope (foundation, no user-visible change): the shared
;;;; vocabulary every command's output will be rebuilt from in Phase 3 --
;;;; REPORT-CONTEXT, ACTION-VERB (natural-language verbs), REASON-LINE
;;;; (provenance-derived why-lines), MACHINE-HEADER (facts-derived machine
;;;; summary), NEXT-STEPS (the consistent footer), SUMMARY-LINE, and
;;;; RENDER-ACTION-LINE (the verbosity ladder: intent+reason at default,
;;;; source at -v, facts at -vv, implementation at -vvv). Plus
;;;; COLLECT-CHECK-STATUSES, the single ':check mode' evaluation path that
;;;; plan/diff/status will share.
;;;;
;;;; Loaded after cli.lisp (see linacs-cli.asd): it references the
;;;; CLI-OPTS accessors and cli.lisp's shared helpers (COLORIZE-GLYPH,
;;;; PACKAGE-VIA-LABEL, ACTION-GROUP-NAME, ...). It lives in the CLI system,
;;;; not the :linacs library, so library consumers never pull in the
;;;; presentation machinery -- the same load-unit boundary cli.lisp itself
;;;; sits behind.

(in-package :linacs.core)

(defstruct report-context
  (plan nil)
  (facts nil)
  (home nil)
  (opts nil))

;;; --- Natural-language vocabulary ------------------------------------------

(defparameter *action-verbs*
  '((:package . "Install")
    (:ensure-dir . "Create")
    (:copy-file . "Configure")
    (:symlink . "Link")
    (:service . "Enable")
    (:timer . "Schedule")
    (:env-var . "Set")
    (:config-lines . "Configure")
    (:config-ini . "Configure")
    (:config-env . "Configure")
    (:secret . "Install secret")
    (:stow . "Stow")
    (:clone . "Clone")
    (:repository . "Add repository")
    (:user . "Create user")
    (:group . "Create group")
    (:authorized-key . "Authorize key")
    (:permissions . "Set permissions")
    (:mount . "Mount")
    (:sysctl . "Set sysctl")
    (:kernel-module . "Load kernel module")
    (:hostname . "Set hostname")
    (:locale . "Configure locale")
    (:firewall . "Configure firewall")
    (:cron . "Install cron job")
    (:command . "Run command"))
  "Natural-language verb for each action type, in the imperative mood a
user would actually say (\"Install emacs\", \"Enable sshd\"). Plugin action
types without an entry fall back to their type name.")

(defun action-verb (action)
  "The natural-language verb for ACTION (its type), falling back to the
type's downcased string when no verb is registered."
  (or (cdr (assoc (action-type action) *action-verbs*))
      (string-downcase (string (action-type action)))))

(defun action-natural-target (action)
  "The human-readable target of ACTION: the catalog-resolved package name
for :package actions (what the user actually gets installed), the expanded
target otherwise. Pure string; never probes the system."
  (if (eq (action-type action) :package)
      (princ-to-string (catalog-lookup :packages (action-target action) (getf *facts* :os)))
      (princ-to-string (action-target action))))

(defparameter *desktop-display-names*
  '((:kde . "KDE Plasma") (:gnome . "GNOME") (:xfce . "XFCE")
    (:sway . "Sway") (:hyprland . "Hyprland") (:i3 . "i3")
    (:other . "Desktop"))
  "Human display names for :desktop fact values, for machine headers.")

(defun desktop-display-name (value)
  "Human name for a :desktop fact VALUE (:kde -> \"KDE Plasma\"), or the
capitalized keyword string for unrecognized values."
  (or (cdr (assoc value *desktop-display-names*))
      (and value (string-capitalize (string value)))
      nil))

(defun fact-display-string (key)
  "A human display string for fact KEY's value, or NIL when the fact is
absent. Special-cases :desktop (KDE Plasma) and :os (capitalized keyword);
everything else is PRINC-TO-STRING of the value."
  (let ((v (getf *facts* key)))
    (case key
      (:desktop (desktop-display-name v))
      (:os (and v (string-capitalize (string v))))
      (:display-server (and v (string-capitalize (string v))))
      (t (and v (princ-to-string v))))))

(defun fact-value-string (value)
  "PRINC-style rendering of a fact VALUE, with keywords and booleans
downcased for the compact -vv \"key = value\" output (wayland, t, nil)."
  (cond
    ((null value) "nil")
    ((eq value t) "t")
    ((keywordp value) (string-downcase (string value)))
    (t (princ-to-string value))))

(defun os-display-string ()
  "The machine's OS as a display string: \"Fedora 42\" when both :os and
:os-version are known, \"Fedora\" when only the keyword is known, NIL when
:os is absent or :unknown."
  (let ((os (getf *facts* :os))
        (ver (getf *facts* :os-version)))
    (cond
      ((and os (not (eq os :unknown)) ver)
       (format nil "~a ~a" (string-capitalize (string os)) ver))
      ((and os (not (eq os :unknown)))
       (string-capitalize (string os)))
      (t nil))))

;;; --- Provenance-derived reason lines ---------------------------------------

(defun fact-label (key)
  "Downcased string form of a fact KEY, for reason lines and -vv output."
  (string-downcase (string key)))

(defun facts-snapshot-string (snapshot)
  "Render a provenance :facts-snapshot (a list of fact keys) as
\"display-server = wayland, laptop-p = t\" by looking up the current run's
values in *FACTS*. NIL or an empty snapshot yields NIL."
  (and snapshot
       (format nil "~{~a~^, ~}"
               (mapcar (lambda (k)
                         (format nil "~a = ~a" (fact-label k)
                                 (fact-value-string (getf *facts* k))))
                       snapshot))))

(defun reason-line (action)
  "A short human-readable reason for ACTION, derived from its provenance:
\"editor via emacs\" for provider actions (facts read while it was produced
appended as \"(display-server = wayland)\"), \"explicitly disabled
(home.lisp:42)\" for disabled user actions, the source location otherwise.
Falls back to \"user declaration\"."
  (let* ((prov (action-provenance (action-identity action)))
         (feat (and prov (provenance-feature prov)))
         (provider (and prov (provenance-provider prov)))
         (loc (and prov (provenance-location prov)))
         (src (and prov (provenance-source prov)))
         (snap (and prov (provenance-facts-snapshot prov))))
    (cond
      (feat (format nil "~a~@[ via ~a~]~@[ (~a)~]"
                    (fact-label feat)
                    (and provider (fact-label provider))
                    (facts-snapshot-string snap)))
      ((getf action :disabled)
       (if loc (format nil "explicitly disabled (~a)" loc) "explicitly disabled"))
      (loc (princ-to-string loc))
      (src (princ-to-string src))
      (t "user declaration"))))

;;; --- Machine header --------------------------------------------------------

(defun machine-header (&key (facts *facts*))
  "A one-line human description of the machine, e.g.
\"thinkpad · Fedora 42 · KDE Plasma · Wayland\". Facts are read from the
FACTS plist (default *FACTS*); absent facts drop silently from the list.
Returns \"Machine\" when nothing useful is known."
  (labels ((fv (key) (getf facts key))
           (os-str ()
             (let ((os (fv :os))
                   (ver (fv :os-version)))
               (cond
                 ((and os (not (eq os :unknown)) ver)
                  (format nil "~a ~a" (string-capitalize (string os)) ver))
                 ((and os (not (eq os :unknown)))
                  (string-capitalize (string os)))
                 (t nil))))
           (display-str (key)
             (let ((v (fv key)))
               (and v (string-capitalize (string v))))))
    (let* ((host (let ((h (fv :hostname)))
                   (and h (not (string= h "unknown")) h)))
           (parts (remove-if #'null
                             (list host
                                   (os-str)
                                   (desktop-display-name (fv :desktop))
                                   (display-str :display-server)))))
      (if parts (format nil "~{~a~^ · ~}" parts) "Machine"))))

;;; --- Shared line helpers ----------------------------------------------------

(defun blank-line ()
  "An empty output line."
  "")

(defun rule-line (&optional (char #\─) (n 60))
  "A horizontal rule line of N CHARs (default 60 em-dashes)."
  (make-string n :initial-element char))

(defun summary-line (parts)
  "Join PARTS (strings or NIL) into one line: \"5 changes · 13 already OK ·
1 removal · 2 privileged\". NIL parts drop out; empty input yields NIL."
  (let ((joined (format nil "~{~a~^ · ~}" (remove-if #'null parts))))
    (and (plusp (length joined)) joined)))

(defun next-steps (commands)
  "The consistent footer: a blank line, \"Next:\", then one indented
\"linacs <command>\" line per COMMAND (a list of strings)."
  (append (list "" "Next:")
          (mapcar (lambda (c) (format nil "  linacs ~a" c)) commands)))

;;; --- Verbosity ladder -------------------------------------------------------

(defun executor-name (type)
  "The name of TYPE's registered executor as a downcased symbol name
without the package prefix (\"execute-package\"), or NIL when it cannot
be determined (e.g. a closure or an unregistered type)."
  (ignore-errors
    (let* ((fn (find-executor type))
           (name (nth-value 2 (function-lambda-expression fn))))
      (and (symbolp name) (string-downcase (symbol-name name))))))

(defun render-action-line (ctx action &key glyph status (verbosity (cli-opts-verbosity (report-context-opts ctx))))
  "Render one natural-language action line for ACTION at VERBOSITY. The
default line is \"<glyph> <verb> <target> — <reason>\". Each additional
-v level appends a detail line below it:
  -v   source/provenance (feature, provider, or declaration location)
  -vv  + facts read while the action was produced
  -vvv + implementation (action type, :via, executor)
GLYPH defaults to \"[+]\" when neither a glyph nor a STATUS is given;
STATUS is rendered through STATUS-GLYPH when supplied."
  (let* ((glyph (or glyph (and status (status-glyph status)) "[+]"))
         (verb (action-verb action))
         (target (action-natural-target action))
         (reason (reason-line action))
         (via (and (eq (action-type action) :package)
                   (let ((v (getf action :via)))
                     (and v (format nil ":~(~a~)" v)))))
         (prov (action-provenance (action-identity action)))
         (source (and prov (provenance-source prov)))
         (snap (and prov (provenance-facts-snapshot prov)))
         (facts (facts-snapshot-string snap))
         (executor (executor-name (action-type action)))
         (impl (format nil "~(~a~)~@[ via :~(~a~)~]~@[ (~a)~]"
                       (string (action-type action)) (getf action :via) executor))
         (base (format nil "~a ~a ~a~@[ ~a~] — ~a"
                       glyph verb target via reason))
         (detail (remove-if #'null
                            (list (and (>= verbosity 2) source
                                       (format nil "    source: ~a" source))
                                  (and (>= verbosity 3) facts
                                       (format nil "    facts: ~a" facts))
                                  (and (>= verbosity 4)
                                       (format nil "    implementation: ~a" impl))))))
    (if detail
        (format nil "~a~{~%~a~}" base detail)
        base)))

(defun status-glyph (status)
  "Map a result/check STATUS keyword to its display glyph: :applied/:changed
\"[v]\", :would-change \"[+]\", :unchanged/:already-met \"[!]\", :removed
\"[x]\", :failed \"[x]\", :skipped \"[-]\", else \"[ ]\"."
  (case status
    ((:applied :changed) "[v]")
    ((:would-change) "[+]")
    ((:unchanged :already-met) "[!]")
    ((:removed :failed) "[x]")
    (:skipped "[-]")
    (t "[ ]")))

;;; --- Check-mode evaluation ---------------------------------------------------

(defun collect-check-statuses (ordered)
  "Run EXECUTE-ACTION in :check mode over the ORDERED action list and return
an EQUAL-keyed hash table mapping each action's identity to its executor
result plist. (Identity conses are freshly allocated per ACTION-IDENTITY
call, so an EQUAL test -- the same convention *ACTION-RESULTS* and
*PROVENANCE* use -- is required for lookup, not EQ.) This is the single
':check' evaluation path plan, diff, and (later) status share, so the
status of every action is computed exactly once per invocation."
  (let ((result (make-hash-table :test 'equal)))
    (dolist (a ordered)
      (setf (gethash (action-identity a) result)
            (execute-action a :mode :check)))
    result))