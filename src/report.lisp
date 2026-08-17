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

(defun location-display-string (loc)
  "Render a provenance LOCATION for display. LOC is the value stamped by
the DSL: a (:file \"<path>\") plist, or already a string. Returns the
plain path string for (:file ...) plists (no \"(FILE ...)\" wrapper);
strings pass through unchanged; anything else is PRINC-TO-STRING'd."
  (cond
    ((and (consp loc) (getf loc :file))
     (princ-to-string (getf loc :file)))
    ((stringp loc) loc)
    (t (princ-to-string loc))))

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
       (if loc (format nil "explicitly disabled (~a)" (location-display-string loc))
           "explicitly disabled"))
      (loc (location-display-string loc))
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

(defun package-via-display (ctx via)
  "Render a package :VIA keyword for display. :system is shown as the
concrete package manager resolved from the :package-manager fact (e.g.
\"dnf\" on Fedora), or \"system\" when no manager is known; other vias
show their keyword name (e.g. \"pip\"). Returns NIL when VIA is NIL."
  (if (eq via :system)
      (let ((pm (getf (report-context-facts ctx) :package-manager)))
        (if (and pm (not (eq pm :unknown)))
            (string-downcase (symbol-name pm))
            "system"))
      (and via (string-downcase (symbol-name via)))))

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
         (via (let ((v (and (eq (action-type action) :package)
                            (getf action :via))))
                (and v (format nil "via ~a" (package-via-display ctx v)))))
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

;;; --- Apply preview & failure report -----------------------------------------

(defun apply-preview-counts (ordered)
  "Count ORDERED actions per summary group (see SUMMARY-GROUP), in canonical
order, as an alist of (group . count). Every group appears, including zero
counts, so the preview shape is stable."
  (mapcar (lambda (g) (cons g (count-if (lambda (a) (eq (summary-group a) g)) ordered)))
          (mapcar #'car *action-group-names*)))

(defun render-apply-preview (ctx ordered)
  "The pre-apply preview: a machine header, a grouped count line
(\"8 action(s) · Packages: 2 · Files: 5 · Services: 1 · Other: 0\"), a
blank line, and the confirmation prompt \"Continue? [y/N]\" as its final
line. Pure: returns lines; the caller prints them and reads the answer."
  (append
   (list (machine-header :facts (report-context-facts ctx))
         ""
         (summary-line
          (cons (format nil "~d action(s)" (length ordered))
                (loop for (g . n) in (apply-preview-counts ordered)
                      collect (format nil "~a: ~d" (action-group-name g) n))))
         "")
   (list "Continue? [y/N]")))

(defun render-apply-failed (ctx)
  "The partial-failure summary for an aborted apply run: machine header,
counts of completed/failed actions, \"Remaining: N not attempted\", the
warning that the system is only partially configured, and the Next: footer.
Reads the run's results from the plan's :results table (which shares
*ACTION-RESULTS*), so it reflects exactly what executed so far."
  (let* ((plan (report-context-plan ctx))
         (ordered (plan-actions plan))
         (results (plan-results plan))
         (total (length ordered))
         (done (hash-table-count results))
         (failed (loop for v being the hash-value of results
                       count (eq (result-status v) :failed)))
         (completed (- done failed)))
    (append
     (list (machine-header :facts (report-context-facts ctx))
           ""
           (summary-line (list (format nil "~d completed" completed)
                               (format nil "~d failed" failed)))
           (format nil "Remaining: ~d not attempted" (- total done))
           ""
           "System state is partially configured.")
     (next-steps '("check" "apply")))))

;;; --- Phase 3: command renderers -------------------------------------------
;;;
;;; One RENDER-* per human command. Each returns a list of lines (pure); the
;;; corresponding cmd-* in cli.lisp shrinks to resolve -> build context ->
;;; print. Functions needing the :check status of every action accept an
;;; optional :statuses hash (identity -> result plist) so they are testable
;;; without touching the real filesystem; they compute it via
;;; COLLECT-CHECK-STATUSES when omitted.

(defun render-header (ctx)
  "The machine header plus a blank line -- the standard opening for human
commands."
  (list (machine-header :facts (report-context-facts ctx)) ""))

(defun split-lines (text)
  "Split TEXT into a list of lines (the trailing newline, if any, removed)."
  (let ((lines '()) (start 0))
    (loop for pos = (position #\Newline text :start start)
          while pos
          do (push (subseq text start pos) lines)
             (setf start (1+ pos)))
    (push (subseq text start) lines)
    (nreverse lines)))

(defun as-list (x)
  "X as a list: X itself when already a list, else (X)."
  (if (listp x) x (list x)))

(defun semantic-value-string (v)
  "Render a semantic :current/:expected VALUE: strings verbatim, plists as
downcased \"key: value\" pairs (e.g. ensure-dir's (exists: nil, mode: nil)),
otherwise PRINC."
  (cond
    ((stringp v) v)
    ((and (consp v) (keywordp (car v)))
     (format nil "~{~a~^, ~}"
             (loop for (k val) on v by #'cddr
                   collect (format nil "~(~a~): ~a" k (fact-value-string val)))))
    (t (princ-to-string v))))

(defun plan-glyph (action statuses prune-p)
  "The plan glyph for ACTION: [x] disabled+prune, [-] disabled only,
otherwise from its :check status via STATUSES (a hash of identity -> result
plist): [+] for :would-change, [!] for :unchanged."
  (let ((disabled (getf action :disabled)))
    (cond
      ((and disabled prune-p) "[x]")
      (disabled "[-]")
      (t (ecase (getf (gethash (action-identity action) statuses) :status)
           (:would-change "[+]")
           (:unchanged "[!]"))))))

(defun apply-result-glyph (status)
  "Map an apply-run result STATUS to its glyph."
  (case status
    ((:changed :applied :removed) "[v]")
    (:unchanged "[!]")
    (:failed "[x]")
    (:skipped "[~]")
    (t "[-]")))

(defun render-plan (ctx &key statuses)
  "The resolved plan: machine header, a summary line, the ordered actions
grouped into Packages / Files / Services / Other sections as
natural-language lines (verb + target + reason, plus the -v/-vv/-vvv detail
ladder), the counts and glyph legend, and the Next: footer. Supports
--feature via the context's opts: the actions are restricted to the feature
subtree and its tree is shown."
  (let* ((home (report-context-home ctx))
         (plan (report-context-plan ctx))
         (opts (report-context-opts ctx))
         (all (plan-actions plan))
         (prune-p (member :prune-explicitly-disabled (home-definition-traits home)))
         (feature-filter (cli-opts-feature opts))
         (feature-set (when feature-filter (collect-feature-subtree feature-filter)))
         (actions (if feature-set
                      (remove-if-not (lambda (a)
                                       (let ((prov (action-provenance (action-identity a))))
                                         (and prov (member (provenance-feature prov) feature-set))))
                                     all)
                      all))
         (statuses (or statuses (collect-check-statuses actions)))
         (annotated (mapcar (lambda (a) (cons (plan-glyph a statuses prune-p) a)) actions))
         (to-apply (count "[+]" annotated :key #'car :test #'string=))
         (present (count "[!]" annotated :key #'car :test #'string=))
         (remove (count "[x]" annotated :key #'car :test #'string=))
         (skipped (count "[-]" annotated :key #'car :test #'string=)))
    (append
     (render-header ctx)
     (list (format nil "Plan for ~a: ~d action(s)"
                   (home-definition-name home) (length actions)))
     (when feature-filter
       (list ""
             (format nil "Feature: ~(~a~)" feature-filter)
             (string-trim '(#\Newline) (feature-tree-string feature-filter))))
     (loop for group in (mapcar #'car *action-group-names*)
           for group-rows = (remove-if-not (lambda (r) (eq (summary-group (cdr r)) group))
                                           annotated)
           when group-rows
             append (append (list "" (action-group-name group))
                            (mapcar (lambda (row)
                                      (format nil "  ~a"
                                              (render-action-line ctx (cdr row)
                                                                  :glyph (colorize-glyph (car row)))))
                                    group-rows)))
     (list ""
           (summary-line (list (format nil "~d action(s)" (length actions))
                               (and (plusp to-apply) (format nil "~d to apply" to-apply))
                               (and (plusp present) (format nil "~d already present" present))
                               (and (plusp remove) (format nil "~d to remove" remove))
                               (and (plusp skipped) (format nil "~d disabled" skipped)))))
     (list (plan-summary-legend))
     (next-steps '("apply")))))

(defun diff-detail-lines (result)
  "Semantic before/after detail lines for a :check RESULT plist: \"+/- rows\"
for the :config-* family (:added/:removed), \"current:/expected:\" rows
otherwise."
  (let ((added (getf result :added))
        (removed (getf result :removed)))
    (cond
      ((or added removed)
       (append (mapcar (lambda (l) (format nil "    + ~a" l)) (as-list added))
               (mapcar (lambda (l) (format nil "    - ~a" l)) (as-list removed))))
      (t
       (append (and (getf result :current)
                    (mapcar (lambda (l) (format nil "    current: ~a" l))
                            (split-lines (semantic-value-string (getf result :current)))))
               (and (getf result :expected)
                    (mapcar (lambda (l) (format nil "    expected: ~a" l))
                            (split-lines (semantic-value-string (getf result :expected))))))))))

(defun render-diff (ctx &key statuses)
  "The semantic before/after report: which actions would change and how,
each with a current/expected (or +/-) detail line. Converged output when
nothing would change. Ends with the Next: footer."
  (let* ((home (report-context-home ctx))
         (plan (report-context-plan ctx))
         (ordered (plan-actions plan))
         (statuses (or statuses (collect-check-statuses ordered)))
         (changes (loop for a in ordered
                        for result = (gethash (action-identity a) statuses)
                        when (eq (getf result :status) :would-change)
                          collect (cons a result))))
    (if changes
        (append
         (render-header ctx)
         (list (format nil "~d action(s) would change for ~a:"
                       (length changes) (home-definition-name home)))
         (loop for (a . result) in changes
               append (cons (format nil "  ~a" (render-action-line ctx a :status :would-change))
                            (diff-detail-lines result)))
         (list "" (format nil "~d action(s) would change." (length changes)))
         (next-steps '("apply")))
        (append
         (render-header ctx)
         (list (format nil "No differences -- the system already matches the resolved plan for ~a."
                       (home-definition-name home)))
         (next-steps '("status"))))))

(defun render-apply-detail (ctx)
  "The verbose apply detail (-vv): the executed plan grouped into Packages /
Files / Services / Other tables with per-action status glyphs. The live
progress reporter already printed the per-action lines at lower verbosity."
  (let* ((plan (report-context-plan ctx))
         (results (plan-results plan))
         (rows (loop for a in (plan-actions plan)
                     for result = (gethash (action-identity a) results)
                     for status = (result-status result)
                     collect (list (summary-group a)
                                   (colorize-glyph (apply-result-glyph status))
                                   (string-downcase (string (action-type a)))
                                   (princ-to-string (action-target a))
                                   (package-via-label a)))))
    (loop for group in (mapcar #'car *action-group-names*)
          for group-rows = (remove-if-not (lambda (r) (eq (first r) group)) rows)
          when group-rows
            append (append (list (action-group-name group))
                           (table-lines '("STATUS" "TYPE" "TARGET" "VIA")
                                        (mapcar (lambda (r) (cdr r)) group-rows))))))

(defun render-apply (ctx)
  "The apply outcome: LINACS APPLY COMPLETE / INCOMPLETE, glyph-count lines
(✓ applied · = already satisfied · - removals · ! skipped), the
converged/partially-configured line, and the Next: footer. Reads the run's
results from the plan's :results table."
  (let* ((plan (report-context-plan ctx))
         (results (plan-results plan))
         (applied (loop for v being the hash-value of results
                        count (member (result-status v) '(:changed :applied))))
         (removed (loop for v being the hash-value of results
                        count (eq (result-status v) :removed)))
         (unchanged (loop for v being the hash-value of results
                          count (eq (result-status v) :unchanged)))
         (failed (loop for v being the hash-value of results
                       count (eq (result-status v) :failed)))
         (skipped (loop for v being the hash-value of results
                        count (eq (result-status v) :skipped))))
    (append
     (list (if (plusp failed) "LINACS APPLY INCOMPLETE" "LINACS APPLY COMPLETE")
           (summary-line (list (format nil "✓ ~d applied" applied)
                               (format nil "= ~d already satisfied" unchanged)
                               (and (plusp removed) (format nil "- ~d removals" removed))
                               (and (plusp failed) (format nil "✗ ~d failed" failed))
                               (and (plusp skipped) (format nil "! ~d skipped" skipped))))
           (if (plusp failed)
               "Configuration is partially configured."
               "Configuration is now converged."))
     (if (plusp failed)
         (next-steps '("check" "apply"))
         (next-steps '("status"))))))

(defun render-conflict-identity (id)
  "A display string for a conflict IDENTITY cons, e.g. \"copy-file ~/.x\"."
  (format nil "~(~a~) ~a" (car id) (cdr id)))

(defun render-conflict-line (record)
  "One line describing a deduplication conflict RECORD (identity . plist):
a user override, or a same-priority conflict resolved in favor of the kept
definition."
  (destructuring-bind (id . info) record
    (format nil "  ~a: ~a (dropped ~a)"
            (render-conflict-identity id)
            (if (eq (getf info :type) :override)
                "user declaration overrides provider"
                "conflicting definitions resolved")
            (getf info :dropped))))

(defun render-check (ctx &key profile)
  "The full check report: machine header, home/profile, the features and how
they resolve, plan counts by category, the privileged-action count, resolved
conflicts, the closing READY TO APPLY line, and the Next: footer."
  (let* ((home (report-context-home ctx))
         (plan (report-context-plan ctx))
         (opts (report-context-opts ctx))
         (actions (plan-actions plan))
         (conflicts (plan-conflicts plan))
         (priv (count-if #'action-needs-privilege-p actions))
         (feature-lines (loop for r in (home-definition-use-features home)
                              for fname = (getf r :feature)
                              collect (format nil "  ✓ ~(~a~) → ~a"
                                              fname
                                              (feature-resolution-summary r (cli-opts-provider-overrides opts))))))
    (append
     (render-header ctx)
     (list (format nil "Home: ~a~@[ (profile: ~a)~]"
                   (home-definition-name home) profile))
     (when feature-lines
       (cons "" (append (list "Features:") feature-lines)))
     (list ""
           (summary-line (cons (format nil "~d action(s)" (length actions))
                               (loop for g in (mapcar #'car *action-group-names*)
                                     for n = (count-if (lambda (a) (eq (summary-group a) g)) actions)
                                     when (plusp n)
                                       collect (format nil "~a: ~d" (action-group-name g) n))))
           (format nil "~d action(s) will use sudo" priv))
     (when conflicts
       (append (list "" (format nil "~d conflict(s) resolved:" (length conflicts)))
               (mapcar #'render-conflict-line conflicts)))
     (list "" "Ready to apply.")
     (next-steps '("plan")))))

(defun render-explain (ctx &key statuses)
  "The resolved feature graph and action order: machine header, home and
traits, the features-used table, the ordered action table (provenance and
facts columns at -vv), counts and legend, and the Next: footer."
  (let* ((home (report-context-home ctx))
         (plan (report-context-plan ctx))
         (opts (report-context-opts ctx))
         (ordered (plan-actions plan))
         (verbose (>= (cli-opts-verbosity opts) 2))
         (prune-p (member :prune-explicitly-disabled (home-definition-traits home)))
         (statuses (or statuses (collect-check-statuses ordered)))
         (feature-rows (loop for r in (home-definition-use-features home)
                             for fname = (getf r :feature)
                             for feature = (feature-by-name fname)
                             collect (multiple-value-bind (fn chosen-name)
                                         (select-provider fname (or (cli-provider-override opts fname)
                                                                     (getf r :via)))
                                       (declare (ignore fn))
                                       (list (string-downcase (string fname))
                                             (if chosen-name (string-downcase (string chosen-name)) "(skipped)")
                                             (or (feature-description feature) "")
                                             (composed-of-summary feature)))))
         (action-rows (loop for a in ordered for i from 1
                            for glyph = (plan-glyph a statuses prune-p)
                            for id = (action-identity a)
                            for prov = (action-provenance id)
                            for facts-str = (and prov (provenance-facts-snapshot prov)
                                                 (format nil "~{~a~^, ~}" (provenance-facts-snapshot prov)))
                            collect (if verbose
                                        (list (princ-to-string i) glyph
                                              (string-downcase (string (action-type a)))
                                              (princ-to-string (action-target a))
                                              (package-via-label a)
                                              (provenance-string id)
                                              (or facts-str ""))
                                        (list (princ-to-string i) glyph
                                              (string-downcase (string (action-type a)))
                                              (princ-to-string (action-target a))
                                              (package-via-label a))))))
    (append
     (render-header ctx)
     (list (format nil "Home: ~a~@[ (traits: ~a)~]"
                   (home-definition-name home) (or (home-definition-traits home) "none"))
           "" "Features used:")
     (table-lines '("FEATURE" "PROVIDER USED" "DESCRIPTION" "COMPOSED OF")
                  feature-rows)
     (list "" "Action order:")
     (table-lines (if verbose '("#" "STATUS" "TYPE" "TARGET" "VIA" "PROVENANCE" "FACTS INVOLVED")
                          '("#" "STATUS" "TYPE" "TARGET" "VIA"))
                  (mapcar (lambda (row)
                            (list* (first row) (colorize-glyph (second row)) (cddr row)))
                          action-rows))
     (list "" (format nil "~d action(s)." (length ordered)))
     (list (plan-summary-legend))
     (next-steps '("apply")))))

(defun render-graph (ctx)
  "The abstract feature dependency graph: each use-feature with its requires
and composed-of relations, and the Next: footer."
  (let* ((home (report-context-home ctx))
         (use-features (home-definition-use-features home)))
    (if use-features
        (append
         (render-header ctx)
         (loop for r in use-features
               for fname = (getf r :feature)
               for feature = (feature-by-name fname)
               append (cons (format nil "~(~a~)~@[ -- ~a~]" fname (feature-description feature))
                            (append (mapcar (lambda (dep) (format nil "  requires ~(~a~)" dep))
                                            (feature-requires feature))
                                    (when (feature-composed-of feature)
                                      (list (format nil "  composed of: ~{~(~a~)~^, ~}"
                                                    (feature-composed-of feature)))))))
         (list "")
         (next-steps '("plan")))
        (append (render-header ctx)
                (list "(no use-feature forms in this home)")
                (next-steps '("plan"))))))

(defun list-section (title headers rows)
  "A catalogue section: TITLE, then the TABLE-LINES over ROWS sorted by
first column, or an empty note when ROWS is NIL."
  (if rows
      (cons title (table-lines headers (sort rows #'string< :key #'first)))
      (list title "  (none registered)")))

(defun render-list (ctx)
  "The full catalogue of registered features, providers, catalogs, action
types, package/service/repository backends, DSL forms, and fact sources.
Ends with the Next: footer."
  (let* ((feature-rows (loop for k being the hash-key of *feature-registry* using (hash-value f)
                             collect (list (string-downcase (string k))
                                           (or (feature-description f) "")
                                           (composed-of-summary f)
                                           (feature-provider-summary k))))
         (provider-rows (loop for fname being the hash-key of *providers* using (hash-value providers)
                              append (mapcar (lambda (p)
                                               (list (string-downcase (string (provider-name p)))
                                                     (string-downcase (string fname))
                                                     (if (provider-default-p p) "yes" "")
                                                     (or (provider-description p) "")))
                                             providers)))
         (catalog-rows (loop for k being the hash-key of *catalogs*
                             collect (list (string-downcase (string k)))))
         (action-rows (loop for k being the hash-key of *action-types*
                            collect (list (string-downcase (string k))
                                          (action-type-description k))))
         (pkg-rows (loop for k being the hash-key of *package-backends* using (hash-value b)
                         collect (list (string-downcase (string k)) (or (backend-description b) ""))))
         (svc-rows (loop for k being the hash-key of *service-backends* using (hash-value b)
                         collect (list (string-downcase (string k))
                                       (string-downcase (string (service-backend-scope b)))
                                       (if (service-backend-privileged-p b) "yes" "")
                                       (or (service-backend-description b) ""))))
         (repo-rows (loop for k being the hash-key of *repository-backends* using (hash-value b)
                          collect (list (string-downcase (string k))
                                        (or (repository-backend-description b) ""))))
         (dsl-rows (loop for name being the hash-key of *dsl-forms* using (hash-value entry)
                         collect (list (string-downcase name) (getf entry :source))))
         (fact-rows (loop for k being the hash-key of *fact-sources* using (hash-value source)
                          collect (list (string-downcase (string k))
                                        (princ-to-string (or (fact-source-type source) ""))
                                        (or (fact-source-doc source) "")
                                        (or (fact-source-registrant source) "")))))
    (append
     (render-header ctx)
     (list-section "Features" '("FEATURE" "DESCRIPTION" "COMPOSED OF" "PROVIDERS") feature-rows)
     (list "")
     (list-section "Providers" '("PROVIDER" "FOR FEATURE" "DEFAULT" "DESCRIPTION") provider-rows)
     (list "")
     (list-section "Catalogs" '("CATALOG") catalog-rows)
     (list "")
     (list-section "Action types" '("TYPE" "DESCRIPTION") action-rows)
     (list "")
     (list-section "Package backends" '("VIA" "DESCRIPTION") pkg-rows)
     (list "")
     (list-section "Service backends" '("NAME" "SCOPE" "SUDO" "DESCRIPTION") svc-rows)
     (list "")
     (list-section "Repository backends" '("METHOD" "DESCRIPTION") repo-rows)
     (list "")
     (list-section "DSL forms" '("FORM" "DEFINED BY") dsl-rows)
     (list "")
     (list-section "Facts" '("FACT" "TYPE" "DESCRIPTION" "SOURCE") fact-rows)
     (next-steps '("plan")))))

(defun render-facts (ctx)
  "The resolved facts: machine header plus a table of FACT / VALUE / TYPE /
CONFIDENCE / SOURCE, and the Next: footer."
  (let* ((pairs (loop for (k v) on *facts* by #'cddr collect (cons k v)))
         (sorted (sort (copy-list pairs) #'string< :key (lambda (p) (string (car p)))))
         (rows (mapcar (lambda (p)
                         (let* ((key (car p))
                                (source (gethash key *fact-sources*))
                                (obj (gethash key *fact-objects*)))
                           (list (string key)
                                 (princ-to-string (cdr p))
                                 (princ-to-string (or (and source (fact-source-type source)) ""))
                                 (princ-to-string (if obj (fact-confidence obj) :unknown))
                                 (princ-to-string (if obj (fact-source-display-name obj) "")))))
                       sorted)))
    (append (render-header ctx)
            (table-lines '("FACT" "VALUE" "TYPE" "CONFIDENCE" "SOURCE") rows)
            (next-steps '("explain")))))

(defun render-validate (ctx &key problems)
  "The validate result: one \"Syntax OK.\" line, or a ✗ line per PROBLEM,
then the Next: footer."
  (declare (ignore ctx))
  (if problems
      (append (mapcar (lambda (p) (format nil "  ✗ ~a" p)) problems)
              (next-steps '("check")))
      (append (list "Syntax OK.")
              (next-steps '("check")))))

(defun render-doctor (ctx &key checks passed warn failed)
  "The doctor report: machine header, the checklist (✓/⚠/✗), the results
summary line, and the Next: footer. CHECKS is a list of (label status
detail) triples."
  (append
   (render-header ctx)
   (list "Diagnostic checks:")
   (mapcar (lambda (c)
             (destructuring-bind (label status detail) c
               (let ((mark (case status (:ok "✓") (:warn "⚠") (t "✗"))))
                 (format nil "  ~a ~a~@[: ~a~]" mark label detail))))
           checks)
   (list ""
         (format nil "Results: ~d passed, ~d warning(s), ~d failed"
                 passed warn failed))
   (next-steps '("apply"))))

(defun render-init (ctx &key root example)
  "The init result: the project path, the created structure, the
linacs-home pointer, and the Next: footer."
  (declare (ignore ctx))
  (append
   (list (format nil "Initialized LINACS project at ~a" root)
         "" "Created:")
   (mapcar (lambda (d) (format nil "  ~a/" d)) *conventional-directories*)
   (list "  home.lisp")
   (when example
     (append (list "" "Example :shell feature seeded:")
             (mapcar (lambda (f) (format nil "  ~a" f))
                     '("features/shell.lisp" "providers/shell.lisp"
                       "catalogs/packages.lisp" "bashrc"))))
   (list ""
         "For a fuller multi-machine example (profiles, templates, plugins, stow"
         "layout), see the linacs-home project -- a sibling of the linacs repo.")
   (next-steps '("check"))))

(defun render-version (ctx)
  "The version line: \"linacs 0.1.0\" at default verbosity, and
\"linacs 0.1.0 · SBCL 2.6.6 · /path/to/linacs\" at -v+."
  (let* ((version (asdf:component-version (asdf:find-system "linacs")))
         (verbose (>= (cli-opts-verbosity (report-context-opts ctx)) 2))
         (impl (lisp-implementation-type))
         (impl-version (lisp-implementation-version))
(path #+sbcl (and verbose (ignore-errors sb-ext:*runtime-pathname*))
      #-sbcl nil))
    (if (and verbose impl)
        (list (format nil "linacs ~a~@[ · ~a ~a~]~@[ · ~a~]"
                      version impl impl-version path))
        (list (format nil "linacs ~a" version)))))