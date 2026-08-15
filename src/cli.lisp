;;;; src/cli.lisp
;;;;
;;;; Command-line parsing, the metadata-driven help system, and command
;;;; dispatch for every `linacs` subcommand (plan, apply, diff, validate, check,
;;;; explain, graph, export, list, facts, doctor, init, version). Also
;;;; defines BOOTSTRAP (Discovery, run at the start of every command) and
;;;; RESET-PROJECT-REGISTRIES (so re-running a command in a long-lived Lisp
;;;; image never silently accumulates stale registrations).
;;;;
;;;; Usage:
;;;;     linacs plan -C ~/my-home --profile work-laptop
;;;;     linacs apply --help
;;;;
;;;;   or, from a Lisp image directly:
;;;;
;;;;     (linacs.core:main (list "plan" "-C" "~/my-home"))

(in-package :linacs.core)

(defstruct cli-opts
  (root ".") (platform nil) (profile nil) (provider-overrides '())
  (dry-run nil) (continue-on-error nil) (output nil) (verbosity 1) (quiet nil)
  (format "sexp")
  (feature nil)
  (sudo-password-stdin nil) (sudo-reset nil)
  (example nil)
  (help nil))

(defun parse-args (args)
  "Parse ARGS (a list of strings, minus the leading command name) into a
CLI-OPTS struct. Returns (values opts unknown-flags). An option that looks
like a flag (starts with '-') but doesn't match anything recognized -- or
a recognized flag missing its required value -- is collected in
UNKNOWN-FLAGS rather than silently ignored, so the caller can show that
command's help instead of guessing what the person meant."
  (let ((opts (make-cli-opts)) (unknown '()))
    (loop while args
          do (let ((a (pop args)))
               (cond
                 ((or (string= a "-h") (string= a "--help")) (setf (cli-opts-help opts) t))
                 ((or (string= a "-C") (string= a "--root"))
                  (if args (setf (cli-opts-root opts) (pop args)) (push a unknown)))
                 ((or (string= a "-p") (string= a "--platform"))
                  (if args (setf (cli-opts-platform opts) (pop args)) (push a unknown)))
                 ((string= a "--profile")
                  (if args
                      (setf (cli-opts-profile opts) (intern (string-upcase (pop args)) :keyword))
                      (push a unknown)))
                 ((string= a "--provider")
                  (if args
                      (let* ((kv (pop args)) (pos (position #\= kv)))
                        (if pos
                            (push (cons (intern (string-upcase (string-left-trim ":" (subseq kv 0 pos))) :keyword)
                                        (intern (string-upcase (string-left-trim ":" (subseq kv (1+ pos)))) :keyword))
                                  (cli-opts-provider-overrides opts))
                            (push a unknown)))
                      (push a unknown)))
                 ((or (string= a "-n") (string= a "--dry-run")) (setf (cli-opts-dry-run opts) t))
                 ((string= a "--continue") (setf (cli-opts-continue-on-error opts) t))
                 ((or (string= a "-o") (string= a "--output"))
                  (if args (setf (cli-opts-output opts) (pop args)) (push a unknown)))
                 ((string= a "--format")
                  (if args (setf (cli-opts-format opts) (pop args)) (push a unknown)))
                 ((string= a "--feature")
                  (if args
                      (setf (cli-opts-feature opts) (intern (string-upcase (string-left-trim ":" (pop args))) :keyword))
                      (push a unknown)))
                 ((and (> (length a) 1) (char= (char a 0) #\-)
                       (every (lambda (c) (char= c #\v)) (subseq a 1)))
                  (incf (cli-opts-verbosity opts) (1- (length a))))
                 ((string= a "--verbose") (incf (cli-opts-verbosity opts)))
                  ((string= a "--sudo-password-stdin") (setf (cli-opts-sudo-password-stdin opts) t))
                  ((string= a "--sudo-reset") (setf (cli-opts-sudo-reset opts) t))
                  ((string= a "--quiet") (setf (cli-opts-quiet opts) t) (setf (cli-opts-verbosity opts) 0))
                  ((string= a "--example") (setf (cli-opts-example opts) t))
                  ((and (> (length a) 0) (char= (char a 0) #\-)) (push a unknown))
                 (t nil)))) ; a bare positional argument -- no command currently takes one, so ignore it
    (values opts (nreverse unknown))))

(defun reset-project-registries ()
  "Clear every registry that Discovery (re-)populates from scratch on each
invocation. REGISTER-PIPELINE-HOOK already de-duplicates by function
identity, so clearing *PIPELINE-HOOKS* here is the explicit per-invocation
reset (to drop hooks registered outside the discovery flow), not a
workaround for accumulation. DEFINE-FEATURE/REGISTER-PROVIDER/
DEFINE-CATALOG overwrite cleanly by name. A fresh per-invocation process
never notices any of this; a persistent one does."
  (clrhash *fact-probers*)
  (clrhash *fact-metadata*)
  (clrhash *feature-registry*)
  (clrhash *providers*)
  (clrhash *catalogs*)
  (clrhash *profiles*)
  (clrhash *pipeline-hooks*)
  (clrhash *dsl-forms*)
  (setf *current-home-thunk* nil))

(defun bootstrap (opts)
  "Run Discovery (step 0) against OPTS's project root."
  (reset-project-registries)
  (default-fact-probers)
  (default-dsl-forms)
  (discover-plugins)
  (discover-project-plugins (cli-opts-root opts))
  (discover-project (cli-opts-root opts)))

(defmacro with-cli-error-report (&body body)
  `(handler-case
       (handler-bind ((linacs-error #'handle-linacs-error-interactively))
         (let ((*restart-menu-p* (interactive-stream-p *query-io*)))
           ,@body))
     (linacs-error (e)
       (linacs.log:error* "~a" e)
       (uiop:quit 1))
     (error (e)
       (linacs.log:error* "Unexpected error: ~a" e)
       (uiop:quit 1))))

(defparameter *print-table-max-width* 60
  "Maximum column width for PRINT-TABLE; longer cells are truncated.")

(defun strip-ansi (s)
  "Remove ANSI escape sequences from S for display-width measurement."
  (let ((result (make-array (length s) :element-type 'character :fill-pointer 0 :adjustable t)))
    (with-input-from-string (in s)
      (loop for c = (read-char in nil nil)
            while c
            do (if (char= c #\Escape)
                   (loop for ec = (read-char in nil nil)
                         while ec
                         when (char= ec #\m) do (return))
                   (vector-push-extend c result))))
    result))

(defun display-width (s)
  "ANSI-stripped display width of string S."
  (length (strip-ansi (or s ""))))

(defun pad-to-width (s w)
  "Pad S with trailing spaces so its display (ANSI-stripped) width reaches W."
  (let* ((str (or s ""))
         (extra (- w (display-width str))))
    (if (plusp extra)
        (concatenate 'string str (make-string extra :initial-element #\Space))
        str)))

(defun print-table (headers rows)
  "Print a simple aligned table (a list of HEADERS strings, then each row
in ROWS as a list of strings, one per column) with a dashed rule under
the header. Empty ROWS still prints the header, so the shape of the
report is consistent whether or not anything is registered."
  (flet ((truncate-cell (s)
           (let ((str (or s "")))
             (if (> (length str) *print-table-max-width*)
                 (concatenate 'string (subseq str 0 (- *print-table-max-width* 3)) "...")
                 str))))
    (let* ((ncols (length headers))
           (truncated-rows (mapcar (lambda (r) (mapcar #'truncate-cell r)) rows))
           (truncated-headers (mapcar #'truncate-cell headers))
           (widths (loop for i below ncols
                         collect (reduce #'max
                                         (cons (display-width (nth i truncated-headers))
                                               (mapcar (lambda (r) (display-width (nth i r))) truncated-rows))))))
      (flet ((row-string (cells)
               (format nil "  ~{~a~^  ~}"
                       (loop for i below ncols
                             collect (pad-to-width (or (nth i cells) "") (nth i widths))))))
        (format t "~a~%" (row-string truncated-headers))
        (format t "~a~%" (row-string (mapcar (lambda (w) (make-string w :initial-element #\-)) widths)))
        (dolist (r truncated-rows) (format t "~a~%" (row-string r)))))))

(defun action-type-counts (actions)
  (let ((counts (make-hash-table :test 'eq)))
    (dolist (a actions) (incf (gethash (action-type a) counts 0)))
    (sort (loop for k being the hash-key of counts using (hash-value v) collect (cons k v))
          #'string< :key (lambda (p) (string (car p))))))

(defun action-status-glyph (action prune-p)
  "Return the status glyph for ACTION based on its :disabled flag and the
PRUNE-P trait: [x] disabled+prune, [-] disabled only, [+] would-change,
[!] unchanged."
  (let ((disabled (getf action :disabled)))
    (cond
      ((and disabled prune-p) "[x]")
      (disabled "[-]")
      (t (ecase (getf (execute-action action :mode :check) :status)
           (:would-change "[+]")
           (:unchanged "[!]"))))))

(defun provenance-string (id)
  (let ((prov (action-provenance id)))
    (if prov
        (let ((feat (provenance-feature prov))
              (prov-name (provenance-provider prov))
              (src (provenance-source prov)))
          (or (and feat (format nil "~a / ~a" feat prov-name))
              (and src (format nil "user:~a" src))
              ""))
        "")))

(defun package-via-label (action)
  "Return a short display string for the :via method of a :package action.
For non-package actions, return an empty string."
  (if (eq (action-type action) :package)
      (let ((via (or (getf action :via)
                     (resolve-package-via action))))
        (format nil ":~(~a~)" via))
      ""))

(defun plan-summary-legend ()
  "Return a single-line legend string for the status glyphs."
  "[+] apply  [!] already present  [x] remove  [-] disabled")

(defun summary-group (action)
  "Classify ACTION into a reporter summary group: :packages, :files,
:services, or :other. Used by the grouped apply summary and plan sections."
  (case (action-type action)
    (:package :packages)
    ((:service :timer) :services)
    ((:copy-file :symlink :ensure-dir :config-lines :config-ini :config-env
      :secret :stow :clone) :files)
    (t :other)))

(defparameter *action-group-names*
  '((:packages . "Packages")
    (:files . "Files")
    (:services . "Services")
    (:other . "Other"))
  "Display names for the ACTION-GROUP keywords, in canonical output order.")

(defun action-group-name (group)
  "The display name for an ACTION-GROUP keyword, falling back to the
keyword's string form."
  (or (cdr (assoc group *action-group-names*))
      (string-downcase (string group))))

(defun result-state-detail (result)
  "A short human-readable detail string for an ACTION-RESULT, for verbose
summaries: the underlying error message for failures, the elapsed duration
for completed actions, else an empty string."
  (cond
    ((eq (result-status result) :failed)
     (let ((err (result-error result)))
       (cond
         ((typep err 'execution-failure) (or (execution-failure-underlying err) "failed"))
         (err (princ-to-string err))
         (t "failed"))))
    (result (let ((dur (result-duration result)))
              (if dur (format nil "~,1fs" dur) "")))
    (t "")))

(defun colorize-glyph (glyph)
  "Wrap GLYPH in bold ANSI color if stdout is a TTY and NO_COLOR is not set.
Maps: [v] green, [+]/[!]/[~]/[-] yellow, [x] red."
  (if (and (interactive-stream-p *standard-output*)
           (not (uiop:getenv "NO_COLOR")))
      (let ((code (cdr (assoc glyph '(("[+]" . "1;33")
                                      ("[v]"  . "1;32")
                                      ("[!]"  . "1;33")
                                      ("[x]"  . "1;31")
                                      ("[~]"  . "1;33")
                                      ("[-]"  . "1;33"))
                              :test #'string=))))
        (if code
            (format nil "~C[~am~a~C[0m" #\Escape code glyph #\Escape)
            glyph))
      glyph))

(defun apply-sudo-password-stdin ()
  "Read a sudo password from *standard-input*, cache it in *SUDO-PASSWORD*
and in sudo's own credential cache via sudo -S."
  (let ((password (read-line *standard-input* nil "")))
    (setf *sudo-password* password)
    (unless (zerop (nth-value 2
                    (uiop:run-program (list "sudo" "-S" "true")
                                      :input (make-string-input-stream
                                              (format nil "~a~%" password))
                                      :ignore-error-status t)))
      (error 'execution-failure :action-type :privileged-command
             :target "sudo credential cache"
             :underlying "sudo -S true failed -- wrong password from stdin?"))))

(defun sudo-reset-after-run (opts)
  (when (and (cli-opts-sudo-reset opts) (not (privileged-p)))
    (uiop:run-program (list "sudo" "-k") :ignore-error-status t :output nil :error-output nil)))

(defun cmd-plan (opts)
  (bootstrap opts)
  (when (cli-opts-sudo-password-stdin opts) (apply-sudo-password-stdin))
  (multiple-value-bind (ordered home plan) (run-pipeline :profile (cli-opts-profile opts)
                                                         :project-root (cli-opts-root opts)
                                                         :provider-overrides (cli-opts-provider-overrides opts)
                                                         :platform (cli-opts-platform opts)
                                                         :execute-mode :plan-only)
    (declare (ignore ordered))
    (let* ((actions (plan-actions plan)))
      (when actions (preflight-notice actions))
      (let* ((prune-p (member :prune-explicitly-disabled (getf home :traits)))
             (verbose (>= (cli-opts-verbosity opts) 2))
             (feature-filter (cli-opts-feature opts))
             (feature-set (when feature-filter
                            (collect-feature-subtree feature-filter)))
             (filtered (if feature-set
                           (remove-if-not
                            (lambda (a)
                              (let ((prov (action-provenance (action-identity a))))
                                (and prov
                                     (member (provenance-feature prov) feature-set))))
                            actions)
                           actions))
             (annotated
              (loop for a in filtered
                    for id = (action-identity a)
                    for glyph = (action-status-glyph a prune-p)
                    for via = (package-via-label a)
                    collect (list glyph
                                  (string-downcase (string (action-type a)))
                                  (princ-to-string (action-target a))
                                  via
                                  (if verbose (provenance-string id) "")))))
        (format t "Resolved plan for ~a (traits: ~a):~%~%" (getf home :name) (or (getf home :traits) "none"))
        (when feature-filter
          (format t "Feature: ~a~%~a~%" (string-downcase (string feature-filter))
                  (feature-tree-string feature-filter)))
        (let ((display (mapcar (lambda (row)
                                 (cons (colorize-glyph (first row)) (rest row)))
                               annotated)))
          (if verbose
              (print-table '("STATUS" "TYPE" "TARGET" "VIA" "PROVENANCE") display)
              (print-table '("STATUS" "TYPE" "TARGET" "VIA")
                           (mapcar (lambda (r) (subseq r 0 4)) display))))
        (let* ((to-apply (count "[+]" annotated :key #'first :test #'string=))
               (present (count "[!]" annotated :key #'first :test #'string=))
               (remove (count "[x]" annotated :key #'first :test #'string=))
               (skipped (count "[-]" annotated :key #'first :test #'string=)))
          (format t "~%~d action(s)~@[ for ~a~]: ~d to apply, ~d already present~@[, ~d to remove~]~@[, ~d disabled~]~%"
                  (length filtered) (when feature-filter (string-downcase (string feature-filter)))
                  to-apply present
                  (if (plusp remove) remove 0)
                  (if (plusp skipped) skipped 0))
          (format t "~a~%" (plan-summary-legend)))))
    (sudo-reset-after-run opts)))



(defun cmd-check (opts)
  (bootstrap opts)
  (when (cli-opts-sudo-password-stdin opts) (apply-sudo-password-stdin))
  (run-pipeline :profile (cli-opts-profile opts) :project-root (cli-opts-root opts)
                :provider-overrides (cli-opts-provider-overrides opts)
                :platform (cli-opts-platform opts)
                :execute-mode :plan-only)
  (format t "Configuration resolves cleanly.~%")
  (sudo-reset-after-run opts))

(defun cmd-validate (opts)
  ;; Syntax-only: try to read every conventional file plus home.lisp without
  ;; resolving features/providers/facts.
  (let ((root (uiop:ensure-directory-pathname (cli-opts-root opts))) (ok t))
    (dolist (dir-name (cons "" *conventional-directories*))
      (let ((dir (if (string= dir-name "") root
                      (merge-pathnames (make-pathname :directory (list :relative dir-name)) root))))
        (when (uiop:directory-exists-p dir)
          (dolist (f (uiop:directory-files dir "*.lisp"))
            (handler-case (with-open-file (s f) (loop for form = (read s nil :eof) until (eq form :eof)))
              (error (e) (setf ok nil) (linacs.log:error* "Syntax error in ~a: ~a" f e)))))))
    (let ((home-file (merge-pathnames "home.lisp" root)))
      (when (probe-file home-file)
        (handler-case (with-open-file (s home-file) (loop for form = (read s nil :eof) until (eq form :eof)))
          (error (e) (setf ok nil) (linacs.log:error* "Syntax error in home.lisp: ~a" e)))))
    (if ok (format t "Syntax OK.~%") (uiop:quit 1))))

;;; --- Background thread abstraction (spinner) ----------------------------
;;;
;;; Wraps SBCL-specific thread creation behind a pair of helpers so the
;;; spinner animation works on SBCL and degrades gracefully (no animation)
;;; on implementations without threading or without the SBCL API.

(defun %make-background-thread (name function)
  "Create a background thread running FUNCTION. Returns a thread handle
or NIL. On non-SBCL implementations, FUNCTION is not called and NIL is
returned — the caller should degrade gracefully."
  #+sbcl (ignore-errors (sb-thread:make-thread function :name name))
  #-sbcl (declare (ignore name function)) nil)

(defun %join-thread (thread)
  "Wait for THREAD to finish. No-op when THREAD is NIL or on
implementations without threading."
  #+sbcl (sb-thread:join-thread thread :default nil)
  #-sbcl (declare (ignore thread)) nil)

;;; --- Spinner for long-running actions -----------------------------------

(defvar *spinner-chars* "|/-\\"
  "Characters to cycle through for the rotating spinner.")

(defvar *spinner-active* nil
  "When true, the spinner thread keeps rotating. Set to nil to stop it.")

(defvar *spinner-thread* nil
  "The background thread running the spinner animation, or nil.")

(defun start-spinner (base-line)
  "Start a background thread that displays a rotating spinner on the same
terminal line as BASE-LINE, updating every 150ms.  The base-line is printed
once on the calling thread; the spinner thread only cycles the last character
using backspace so the line is never fully reprinted (avoids visual artifacts
on wrapped terminal lines).  Does nothing on non-interactive terminals, on
implementations without threads, or if thread creation fails."
  (setf *spinner-active* t)
  ;; Print base-line once on the main thread; cursor stays at end
  (format t "~a" base-line)
  (finish-output)
  (setf *spinner-thread*
        (%make-background-thread
         "linacs-spinner"
         (lambda ()
           (loop for i from 0
                 while *spinner-active*
                 do (if (zerop i)
                        ;; First tick: just print the first char
                        (format t "~a" (aref *spinner-chars* 0))
                        ;; Subsequent ticks: backspace erases previous char, then print next
                        (format t "~C~C" #\Backspace (aref *spinner-chars* (mod i 4))))
                    (finish-output)
                    (sleep 0.15))
           ;; Erase the final spinner char so the :after/:failed/:skipped
           ;; handler can print the result line cleanly.
           (format t "~C" #\Backspace)
           (finish-output)))))

(defun stop-spinner ()
  "Stop the spinner thread and wait for it to finish.  Safe to call when
no spinner is running — returns immediately."
  (when *spinner-thread*
    (setf *spinner-active* nil)
    (%join-thread *spinner-thread*)
    (setf *spinner-thread* nil)))

;;; --- Progress reporting ---------------------------------------------------

(defun apply-progress-glyph (phase &optional result-plist)
  "Return the status glyph for a given apply-progress phase."
  (case phase
    (:before "[+]")
    (:after (case (getf result-plist :status)
              ((:changed :applied) "[v]")
              (:removed "[v]")
              (:unchanged "[!]")
              (t "[v]")))
    (:failed "[x]")
    (:skipped "[~]")))

(defun apply-progress-reporter (action phase &optional data)
  "Progress reporter bound to *PROGRESS-REPORTER* during CMD-APPLY.
On interactive terminals, shows a rotating spinner during action execution.
On non-interactive terminals (piped output, CI), shows static line labels."
  (let* ((tty-p (interactive-stream-p *query-io*))
         (target (princ-to-string (action-target action)))
         (type-name (string-downcase (string (action-type action))))
         (raw-glyph (if (and (eq phase :before) (getf action :disabled))
                        "[x]"
                        (apply-progress-glyph phase data)))
         (glyph (colorize-glyph raw-glyph)))
    (case phase
      (:before
       (if tty-p
           (let ((line (format nil "  ~a ~a ~a " glyph type-name target)))
              (start-spinner line))
            (format t "  ~a ~a ~a~%" glyph type-name target)))
      (:after
       (stop-spinner)
       (if tty-p
           (format t "~C~C[K  ~a ~a ~a~%" #\Return #\Escape glyph type-name target)
           (format t "  ~a ~a ~a~%" glyph type-name target))
       (finish-output))
      (:failed
       (stop-spinner)
       (if tty-p
           (format t "~C~C[K  ~a ~a ~a~%" #\Return #\Escape glyph type-name target)
           (format t "  ~a ~a ~a~%" glyph type-name target))
       (let ((err (cond
                    ((typep data 'execution-failure)
                     (execution-failure-underlying data))
                    (data (princ-to-string data))
                    (t nil))))
         (when (and err (not (string= err "")))
           (format t "    Error: ~a~%" err)))
       (dolist (entry *captured-subprocess-lines*)
         (format t "    ~a~%" (cdr entry)))
       (finish-output))
      (:skipped
       (stop-spinner)
       (if tty-p
           (format t "~C~C[K  ~a ~a ~a~%" #\Return #\Escape glyph type-name target)
           (format t "  ~a ~a ~a~%" glyph type-name target))
       (finish-output)))))

(defun print-apply-summary (plan &key verbose)
  "Print a summary of the executed ACTION-PLAN (REFACTOR.org Action 5):
grouped sections (Packages / Files / Services / Other) in canonical order,
each with its own table. In VERBOSE mode, adds a per-action STATE DETAIL
column (underlying error for failures, duration otherwise)."
  (let* ((results (plan-results plan))
         (rows (loop for a in (plan-actions plan)
                     for id = (action-identity a)
                     for result = (gethash id results)
                     for status = (result-status result)
                     for glyph = (case status
                                   ((:changed :applied :removed) "[v]")
                                   (:unchanged "[!]")
                                   (:failed "[x]")
                                   (:skipped "[~]")
                                   (t "[-]"))
                     for via = (package-via-label a)
                     collect (list (summary-group a) glyph
                                   (string-downcase (string (action-type a)))
                                   (princ-to-string (action-target a))
                                   via
                                   (and verbose (result-state-detail result)))))
         (counts (loop for v being the hash-value of results
                       for status = (result-status v)
                       count status into total
                       count (member status '(:changed :applied :removed)) into applied
                       count (eq status :unchanged) into unchanged
                       count (eq status :failed) into failed
                       count (eq status :skipped) into skipped
                       finally (return (list total applied unchanged failed skipped)))))
    (format t "~%")
    (dolist (group (mapcar #'car *action-group-names*))
      (let ((group-rows (remove-if-not (lambda (r) (eq (first r) group)) rows)))
        (when group-rows
          (format t "~a:~%" (action-group-name group))
          (let ((display (mapcar (lambda (r)
                                   (list* (colorize-glyph (second r)) (cddr r)))
                                 group-rows)))
            (if verbose
                (print-table '("STATUS" "TYPE" "TARGET" "VIA" "STATE DETAIL") display)
                (print-table '("STATUS" "TYPE" "TARGET" "VIA")
                             (mapcar (lambda (r) (subseq r 0 4)) display))))
          (terpri))))
    (destructuring-bind (total applied unchanged failed skipped) counts
      (format t "~d action(s): ~d applied, ~d unchanged~@[, ~d failed~]~@[, ~d skipped~]~%"
              total applied unchanged
              (if (plusp failed) failed 0)
              (if (plusp skipped) skipped 0))
      (format t "[v] applied  [!] unchanged  [x] failed  [~~] skipped~%"))))

(defun cmd-apply (opts)
  (bootstrap opts)
  (when (cli-opts-sudo-password-stdin opts) (apply-sudo-password-stdin))
  (let* ((verbose (>= (cli-opts-verbosity opts) 2))
         (*capture-subprocess-output* (and (not verbose) (not (cli-opts-dry-run opts))))
         (*progress-reporter* (and (not (cli-opts-dry-run opts))
                                   #'apply-progress-reporter))
         (*captured-subprocess-lines* nil))
    (multiple-value-bind (ordered home plan) (run-pipeline :profile (cli-opts-profile opts)
                                                           :project-root (cli-opts-root opts)
                                                           :provider-overrides (cli-opts-provider-overrides opts)
                                                           :platform (cli-opts-platform opts)
                                                           :execute-mode (if (cli-opts-dry-run opts) :check :apply)
                                                           :continue-on-error (cli-opts-continue-on-error opts))
      (declare (ignore ordered home))
      (unless (cli-opts-dry-run opts)
        (when plan (print-apply-summary plan :verbose verbose)))
      (sudo-reset-after-run opts))))

(defun cmd-diff (opts)
  "Resolve the plan and check each action against current system state.
Uses :plan-only mode (not :check) because run-pipeline's :check mode
dispatches executors inline but doesn't capture individual results;
we call execute-action separately to collect :would-change statuses."
  (bootstrap opts)
  (when (cli-opts-sudo-password-stdin opts) (apply-sudo-password-stdin))
  (multiple-value-bind (ordered home) (run-pipeline :profile (cli-opts-profile opts)
                                                       :project-root (cli-opts-root opts)
                                                       :provider-overrides (cli-opts-provider-overrides opts)
                                                       :platform (cli-opts-platform opts)
                                                       :execute-mode :plan-only)
    (when ordered (preflight-notice ordered))
    (let* ((verbose (>= (cli-opts-verbosity opts) 2))
           (headers (if verbose '("TYPE" "TARGET" "CURRENT" "EXPECTED" "PROVENANCE") '("TYPE" "TARGET")))
           (changes (if verbose
                        (loop for a in ordered
                              for result = (execute-action a :mode :check)
                              when (eq (getf result :status) :would-change)
                                collect (let* ((id (action-identity a))
                                               (prov (action-provenance id))
                                               (prov-str (if prov
(let ((feat (provenance-feature prov))
                                    (prov-name (provenance-provider prov))
                                    (src (provenance-source prov)))
                                                               (or (and feat (format nil "~a / ~a" feat prov-name))
                                                                   (and src (format nil "user:~a" src))
                                                                   ""))
                                                             "")))
                                          (list (string-downcase (string (action-type a)))
                                                (princ-to-string (action-target a))
                                                (or (getf result :current) "?")
                                                (or (getf result :expected) "?")
                                                prov-str)))
                        (loop for a in ordered
                              for result = (execute-action a :mode :check)
                              when (eq (getf result :status) :would-change)
                                collect (list (string-downcase (string (action-type a)))
                                              (princ-to-string (action-target a)))))))
      (if changes
          (progn
            (format t "~a differs from the resolved plan for ~a:~%~%" (or (cli-opts-root opts) ".") (getf home :name))
            (print-table headers changes)
            (format t "~%~d action(s) would change.~%" (length changes)))
          (format t "No differences -- the system already matches the resolved plan for ~a.~%" (getf home :name))))))

(defun cli-provider-override (opts feature-name)
  "The provider the CLI's --provider T=P flag forces for FEATURE-NAME, or
NIL if no override was given. Takes precedence over the home's :via."
  (cdr (assoc feature-name (cli-opts-provider-overrides opts))))

(defun collect-feature-subtree (fname)
  "Return FNAME plus every feature it transitively requires/composes-of
(the full feature subtree rooted at FNAME), preserving breadth-first
dependency order. Used by `plan --feature` to show the feature tree."
  (let ((seen '()))
    (labels ((walk (name)
               (unless (member name seen)
                 (push name seen)
                 (let ((feature (feature-by-name name)))
                   (dolist (dep (or (feature-requires feature)
                                    (feature-composed-of feature)))
                     (walk dep))))))
      (walk fname))
    (nreverse seen)))

(defun feature-tree-string (fname &optional (indent 0))
  "Render the feature subtree rooted at FNAME as an indented tree, e.g.:
editor
  packages
    compilers
  ui"
  (with-output-to-string (out)
    (let ((feature (feature-by-name fname)))
      (format out "~v@t~a~@[ -- ~a~]~%" indent
              (string-downcase (string fname)) (feature-description feature))
      (dolist (dep (or (feature-requires feature) (feature-composed-of feature)))
        (write-string (feature-tree-string dep (+ indent 2)) out)))))

(defun cmd-explain (opts)
  (bootstrap opts)
  (multiple-value-bind (ordered home) (run-pipeline :profile (cli-opts-profile opts)
                                                    :project-root (cli-opts-root opts)
                                                    :provider-overrides (cli-opts-provider-overrides opts)
                                                    :platform (cli-opts-platform opts)
                                                    :execute-mode :plan-only)
    (format t "Home: ~a~%Traits: ~a~%~%Features used:~%" (getf home :name) (or (getf home :traits) "none"))
    (print-table '("FEATURE" "PROVIDER USED" "DESCRIPTION" "COMPOSED OF")
                 (mapcar (lambda (r)
                           (let* ((fname (getf r :feature))
                                  (feature (feature-by-name fname)))
                              (multiple-value-bind (fn chosen-name) (select-provider fname (or (cli-provider-override opts fname) (getf r :via)))
                               (declare (ignore fn))
                               (list (string-downcase (string fname))
                                     (if chosen-name (string-downcase (string chosen-name)) "(skipped)")
                                     (or (feature-description feature) "")
                                     (composed-of-summary feature)))))
                         (getf home :use-features)))
    (format t "~%Action order:~%")
    (let* ((prune-p (member :prune-explicitly-disabled (getf home :traits)))
           (verbose (>= (cli-opts-verbosity opts) 2)))
      (if verbose
          (let* ((rows (loop for a in ordered for i from 1
                             for glyph = (action-status-glyph a prune-p)
                             for id = (action-identity a)
                             for via = (package-via-label a)
for facts-str = (let ((prov (action-provenance id)))
                                                (and prov (provenance-facts-snapshot prov)
                                                     (format nil "~{~a~^, ~}" (provenance-facts-snapshot prov))))
                             collect (list (princ-to-string i) glyph
                                           (string-downcase (string (action-type a)))
                                           (princ-to-string (action-target a))
                                           via
                                           (provenance-string id)
                                           (or facts-str ""))))
                 (display (mapcar (lambda (row)
                                    (destructuring-bind (num glyph &rest rest) row
                                      (list* num (colorize-glyph glyph) rest)))
                                  rows)))
            (print-table '("#" "STATUS" "TYPE" "TARGET" "VIA" "PROVENANCE" "FACTS INVOLVED")
                         display))
          (let* ((rows (loop for a in ordered for i from 1
                             for glyph = (action-status-glyph a prune-p)
                             for via = (package-via-label a)
                             collect (list (princ-to-string i) glyph
                                           (string-downcase (string (action-type a)))
                                           (princ-to-string (action-target a))
                                           via)))
                 (display (mapcar (lambda (row)
                                    (destructuring-bind (num glyph &rest rest) row
                                      (list* num (colorize-glyph glyph) rest)))
                                  rows)))
            (print-table '("#" "STATUS" "TYPE" "TARGET" "VIA")
                         display)))
      (format t "~%~d action(s).~%~a~%" (length ordered) (plan-summary-legend)))))

(defun cmd-graph (opts)
  (bootstrap opts)
  (probe-all-facts) (apply-profile (cli-opts-profile opts))
  (apply-platform-override (cli-opts-platform opts))
  (let ((home (run-current-home-thunk)))
    (if (getf home :use-features)
        (dolist (r (getf home :use-features))
          (let* ((fname (getf r :feature))
                 (feature (feature-by-name fname)))
            (format t "~a~@[ -- ~a~]~%" (string-downcase (string fname)) (feature-description feature))
            (dolist (dep (feature-requires feature))
              (format t "  requires ~a~%" (string-downcase (string dep))))
            (let ((composed (feature-composed-of feature)))
              (when composed
                (format t "  composed of: ~{~(~a~)~^, ~}~%" composed)))))
        (format t "(no use-feature forms in this home)~%"))))

(defun cmd-export (opts)
  (bootstrap opts)
  (multiple-value-bind (ordered home) (run-pipeline :profile (cli-opts-profile opts)
                                                       :project-root (cli-opts-root opts)
                                                       :provider-overrides (cli-opts-provider-overrides opts)
                                                       :platform (cli-opts-platform opts)
                                                       :execute-mode :plan-only)
    (declare (ignore home))
    (let ((out (if (cli-opts-output opts) (open (cli-opts-output opts) :direction :output :if-exists :supersede) t))
          (format (string-downcase (cli-opts-format opts))))
      (unwind-protect
           (cond
             ((string= format "sexp")
              (print (list :actions ordered) out)
              (terpri out))
             ((string= format "json")
              (format out "~a~%"
                      (encode-json (list :actions (mapcar #'action->plist ordered)))))
             (t
              (error "Unsupported export format: ~a" format)))
         (unless (eq out t) (close out))))))

(defun feature-provider-summary (fname)
  "One string summarizing every provider registered for FNAME, e.g.
\"bash (default), zsh\" -- this is the combined FEATURE | PROVIDERS view."
  (let ((candidates (find-providers-for fname)))
    (if candidates
        (format nil "~{~a~^, ~}"
                (mapcar (lambda (p) (format nil "~(~a~)~a"
                                            (provider-name p)
                                            (if (provider-default-p p) " (default)" "")))
                        (reverse candidates)))
        "(none registered)")))

(defun composed-of-summary (feature)
  "One-line summary of the feature's :composed-of sub-features, or empty."
  (let ((composed (feature-composed-of feature)))
    (if composed
        (format nil "~{~(~a~)~^, ~}" composed)
        "")))

(defun cmd-list (opts)
  (bootstrap opts)
  (format t "Features:~%")
  (let ((rows (loop for k being the hash-key of *feature-registry* using (hash-value f)
                     collect (list (string-downcase (string k))
                                    (or (feature-description f) "")
                                    (composed-of-summary f)
                                    (feature-provider-summary k)))))
    (if rows
        (print-table '("FEATURE" "DESCRIPTION" "COMPOSED OF" "PROVIDERS") (sort rows #'string< :key #'first))
        (format t "  (none registered)~%")))
  (terpri)

  (format t "Providers:~%")
  (let ((rows (loop for fname being the hash-key of *providers* using (hash-value providers)
                     append (mapcar (lambda (p)
                                      (list (string-downcase (string (provider-name p)))
                                             (string-downcase (string fname))
                                             (if (provider-default-p p) "yes" "")
                                             (or (provider-description p) "")))
                                    providers))))
    (if rows
        (print-table '("PROVIDER" "FOR FEATURE" "DEFAULT" "DESCRIPTION")
                     (sort rows #'string< :key (lambda (r) (format nil "~a:~a" (second r) (first r)))))
        (format t "  (none registered)~%")))
  (terpri)

  (format t "Catalogs:~%")
  (let ((names (loop for k being the hash-key of *catalogs* collect (string-downcase (string k)))))
    (if names
        (dolist (n (sort names #'string<)) (format t "  ~a~%" n))
        (format t "  (none registered)~%")))
  (terpri)

  (format t "Action types:~%")
  (let ((rows (loop for k being the hash-key of *action-types*
                     collect (list (string-downcase (string k)) (action-type-description k)))))
    (print-table '("TYPE" "DESCRIPTION") (sort rows #'string< :key #'first)))
  (terpri)

  (format t "DSL forms:~%")
  (let ((rows (loop for name being the hash-key of *dsl-forms* using (hash-value entry)
                    collect (list (string-downcase name) (getf entry :source)))))
    (if rows
        (print-table '("FORM" "DEFINED BY") (sort rows #'string< :key #'first))
        (format t "  (none registered)~%")))
  (terpri)

  (format t "Facts:~%")
  (let ((rows (loop for k being the hash-key of *fact-metadata* using (hash-value meta)
                    collect (list (string-downcase (string k))
                                  (princ-to-string (or (getf meta :type) ""))
                                  (or (getf meta :doc) "")))))
    (if rows
        (print-table '("FACT" "TYPE" "DESCRIPTION") (sort rows #'string< :key #'first))
        (format t "  (none registered)~%"))))

(defun cmd-facts (opts)
  "Print every resolved fact -- after probing and merging the selected
--profile -- one per line, aligned. Useful for answering \"why did LINACS pick
that provider on this machine\" without re-deriving it from probes."
  (bootstrap opts)
  (probe-all-facts)
  (apply-profile (cli-opts-profile opts))
  (apply-platform-override (cli-opts-platform opts))
  (let* ((pairs (loop for (k v) on *facts* by #'cddr collect (cons k v)))
         (sorted (sort (copy-list pairs) #'string< :key (lambda (p) (string (car p)))))
         (key-width (reduce #'max (mapcar (lambda (p) (length (string (car p)))) sorted) :initial-value 0))
         (val-width (reduce #'max (mapcar (lambda (p) (length (princ-to-string (cdr p)))) sorted) :initial-value 0))
         (type-width (reduce #'max (mapcar (lambda (p)
                                             (let ((meta (gethash (car p) *fact-metadata*)))
                                               (length (princ-to-string (or (getf meta :type) "")))))
                                           sorted)
                             :initial-value 0)))
    (format t "~va  ~va  ~a~%" key-width "FACT" val-width "VALUE" "TYPE")
    (format t "~va  ~va  ~a~%"
            key-width (make-string key-width :initial-element #\-)
            val-width (make-string val-width :initial-element #\-)
            (make-string type-width :initial-element #\-))
    (dolist (p sorted)
      (let* ((key (car p))
             (meta (gethash key *fact-metadata*))
             (val-str (princ-to-string (cdr p)))
             (type-str (princ-to-string (or (getf meta :type) ""))))
        (format t "~va  ~va  ~a~%" key-width (string key) val-width val-str type-str)))))

(defun feature-resolution-summary (r &optional overrides)
  "How feature request R will actually resolve: the chosen provider name,
or a clear diagnosis of why it can't resolve -- used by `linacs doctor`.
OVERRIDES is the --provider T=P alist; an entry for the feature takes
precedence over the request's own :via."
  (let* ((fname (getf r :feature))
         (via (or (cdr (assoc fname overrides)) (getf r :via)))
         (candidates (find-providers-for fname)))
    (cond
      ((null candidates) "NO PROVIDER REGISTERED")
      (via (if (find via candidates :key #'provider-name) (string-downcase (string via))
               (format nil "VIA ~a NOT FOUND" via)))
      ((= (length candidates) 1) (string-downcase (string (provider-name (first candidates)))))
      (t (let ((defaults (remove-if-not #'provider-default-p candidates)))
           (cond
             ((= (length defaults) 1) (string-downcase (string (provider-name (first defaults)))))
             ((> (length defaults) 1) "MULTIPLE :DEFAULT T PROVIDERS -- AMBIGUOUS")
             (t "AMBIGUOUS -- needs :via, or mark one :default t")))))))

(defun cmd-doctor (opts)
  (bootstrap opts)
  (probe-all-facts) (apply-profile (cli-opts-profile opts))
  (apply-platform-override (cli-opts-platform opts))
  (format t "Diagnostic checks:~%")
  (let ((checks-passed 0) (checks-warn 0) (checks-failed 0))
    (flet ((log-check (label ok-p &optional detail)
             (cond (ok-p (incf checks-passed) (format t "  ✓ ~a~%" label))
                   (detail (incf checks-warn)
                           (format t "  ⚠ ~a: ~a~%" label detail))
                   (t (incf checks-failed)
                       (format t "  ✗ ~a~%" label)))))
      (log-check "OS probed" (not (eq (fact :os) :unknown)) (format nil "detected ~a" (fact :os)))
      (log-check "Hostname resolved" (not (eq (fact :hostname) :unknown)) (fact :hostname))
      (log-check "Package manager detected" (not (eq (fact :package-manager) :unknown))
                 (format nil "found ~a" (fact :package-manager)))
      (log-check "Privileged (can install packages)" (privileged-p) "will use sudo per-action")
      (let ((type-mismatches 0))
        (maphash (lambda (key entry)
                   (declare (ignore entry))
                   (let* ((value (getf *facts* key))
                          (meta (gethash key *fact-metadata*))
                          (type (and meta (getf meta :type))))
                     (when (and type value (not (eq value :unknown))
                                (not (typep value type)))
                       (incf type-mismatches)
                       (log-check (format nil "Fact ~a type" key) nil
                                  (format nil "expected ~s, got ~s" type value)))))
                 *fact-probers*)
        (log-check "Fact type validation" (zerop type-mismatches)
                   (format nil "~d type mismatch(es)" type-mismatches)))
      (let ((home (run-current-home-thunk)))
        (log-check "Home definition loaded" t)
        (if (getf home :use-features)
            (dolist (r (getf home :use-features))
              (let* ((fname (getf r :feature))
                     (summary (feature-resolution-summary r (cli-opts-provider-overrides opts))))
                (log-check (format nil "Feature ~(~a~)" fname)
                           (not (search "NO PROVIDER" summary)) summary)))
            (log-check "Features defined" nil "no use-feature forms"))
        (let* ((all-actions (append (getf home :actions)
                                    (collect-actions-from-features (getf home :use-features)
                                                                   :provider-overrides (cli-opts-provider-overrides opts))))
               (types-used (remove-duplicates (mapcar #'action-type all-actions)))
               (missing-executors (remove-if (lambda (k) (gethash k *action-types*)) types-used)))
          (log-check "All action types have executors" (null missing-executors)
                     (format nil "missing: ~{~a~^, ~}" missing-executors))
          (let ((priv-count (count-if #'action-needs-privilege-p all-actions)))
            (log-check "Package installs requiring privilege" (or (zerop priv-count) (privileged-p))
                       (format nil "~d action(s) will use sudo" priv-count))))
        (let* ((os (fact :os)) (missing-entries 0))
          (unless (eq os :unknown)
            (let ((os-str (string-downcase (string os))))
              (maphash (lambda (cat-name entries)
                         (declare (ignore cat-name))
                         (dolist (e entries)
                           (unless (assoc os-str e :test #'string=)
                             (incf missing-entries))))
                       *catalogs*)))
          (log-check "Catalog coverage for OS" (zerop missing-entries)
                     (format nil "~d entries missing for ~(~a~)" missing-entries os))))
      (format t "~%Environment:~%  OS: ~a~%  Hostname: ~a~%  Privileged: ~a~%~%"
              (fact :os) (fact :hostname) (privileged-p))
      (format t "Results: ~d passed, ~d warning(s), ~d failed~%"
              checks-passed checks-warn checks-failed)
      (when (> checks-failed 0) (uiop:quit 1)))))

(defun write-file-if-absent (path content)
  "Write CONTENT verbatim to PATH unless it already exists. Existing files
are kept (never clobbered), so `linacs init` is idempotent even in --example
mode."
  (if (probe-file path)
      (linacs.log:warn* "Keeping existing ~a" path)
      (progn
        (with-open-file (s path :direction :output :if-exists :supersede)
          (write-string content s))
        (linacs.log:info "Wrote ~a" path))))

(defun seed-example-project (root)
  "Scaffold a tiny working project matching user-manual §2: a :shell feature
with a single :bash provider, a :packages catalog, a bashrc asset, and a
home.lisp that pulls the feature in. None of the files is overwritten if it
already exists."
  (write-file-if-absent
   (merge-pathnames "home.lisp" root)
   ";;;; home.lisp
(define-home my-home
  :traits (:prune-explicitly-disabled)
  (use-feature :shell))
")
  (write-file-if-absent
   (merge-pathnames "features/shell.lisp" root)
   ";;;; features/shell.lisp
(in-package :linacs.api)

(define-feature :shell
  :description \"Login shell and dotfiles\"
  :requires nil)
")
  (write-file-if-absent
   (merge-pathnames "providers/shell.lisp" root)
   ";;;; providers/shell.lisp
(in-package :linacs.api)

(define-provider :bash :for :shell
  (lambda (facts)
    (declare (ignore facts))
    (list
      '(:action :package :target :bash :via :system)
      '(:action :copy-file :to \"~/.bashrc\" :from \"bashrc\"))))
")
  (write-file-if-absent
   (merge-pathnames "catalogs/packages.lisp" root)
   ";;;; catalogs/packages.lisp
(in-package :linacs.api)

(define-catalog :packages
  (:bash (:fedora . \"bash\") (:ubuntu . \"bash\") (:arch . \"bash\")))
")
  (write-file-if-absent
   (merge-pathnames "bashrc" root)
   ";; Sample ~/.bashrc seeded by `linacs init --example`
# Add your own aliases and settings below.
"))

(defun cmd-init (opts)
  (let ((root (uiop:ensure-directory-pathname (cli-opts-root opts))))
    (dolist (d *conventional-directories*)
      (ensure-directories-exist (merge-pathnames (make-pathname :directory (list :relative d)) root)))
    (if (cli-opts-example opts)
        (seed-example-project root)
        (write-file-if-absent
         (merge-pathnames "home.lisp" root)
         ";;;; home.lisp
(define-home my-home
  :traits (:prune-explicitly-disabled)
  (package-preference :system))
"))
    (format t "Initialized LINACS project at ~a~%" root)
    (format t "For a fuller multi-machine example (profiles, templates, plugins, stow layout),~%  see the linacs-home project -- a sibling of the linacs repo.~%")))

(defun cmd-version (opts)
  (declare (ignore opts))
  (format t "linacs ~a~%" (asdf:component-version (asdf:find-system "linacs"))))

;;; --- Help system -----------------------------------------------------
;;;
;;; Every option flag has one canonical description, shared across every
;;; command that accepts it, so the two never drift out of sync. Every
;;; command declares which of these options it actually accepts, plus a
;;; one-line summary (shown in the top-level command list) and a couple
;;; of runnable examples (shown in its own --help).

(defparameter *option-specs*
  '((:root     "-C, --root DIR"      "Project root (default \".\")")
    (:platform "-p, --platform NAME" "Override the :os fact (e.g. fedora, arch, ubuntu)")
    (:profile  "--profile NAME"      "Select a defined profile (fact overrides)")
    (:provider "--provider T=P"      "Force provider P for feature T (e.g. :editor=:emacs)")
    (:dry-run  "-n, --dry-run"       "Show changes without executing them")
    (:continue "--continue"          "Keep going after a failed action")
    (:output   "-o, --output FILE"   "Write output to FILE")
    (:format   "--format FORMAT"     "Output format for export: sexp (default) or json")
    (:feature  "--feature NAME"      "Restrict plan/explain to a single feature and show its tree")
    (:verbose  "-v, --verbose"       "Increase verbosity (repeatable: -v, -vv, -vvv)")
    (:quiet    "--quiet"             "Only show errors")
    (:sudo-password-stdin "--sudo-password-stdin"
               "Read sudo password from stdin before resolving")
    (:sudo-reset "--sudo-reset"      "Run `sudo -k` after the command finishes")
    (:example  "--example"           "Seed a tiny working :shell example project instead of empty dirs (init)")
    (:help     "-h, --help"          "Show this command's help and exit")))

(defparameter *command-specs*
  (list
   (list :name "plan" :fn #'cmd-plan
          :summary "Show the resolved, ordered action list"
          :options '(:root :profile :provider :platform :feature :sudo-password-stdin :sudo-reset :verbose :quiet :help)
          :examples '("linacs plan -C ~/my-home --profile work-laptop"
                      "linacs plan --feature :editor -C ~/my-home   # just editor, with its feature tree"
                      "linacs plan --sudo-password-stdin < ~/.sudo-pass"))
   (list :name "apply" :fn #'cmd-apply
          :summary "Execute the ordered action list"
          :options '(:root :profile :provider :platform :dry-run :continue :sudo-password-stdin :sudo-reset :verbose :quiet :help)
           :examples '("linacs apply -C ~/my-home --profile work-laptop   # sudo prompted once up front, not per-action"
                       "linacs apply -C ~/my-home --profile work-laptop -n   # dry run"
                      "linacs apply --sudo-password-stdin < ~/.sudo-pass"))
   (list :name "diff" :fn #'cmd-diff
          :summary "Show which actions would change something"
          :options '(:root :profile :provider :platform :sudo-password-stdin :sudo-reset :verbose :quiet :help)
          :examples '("linacs diff -C ~/my-home --profile work-laptop"))
   (list :name "validate" :fn #'cmd-validate
          :summary "Check configuration syntax only (facts/providers untouched)"
          :options '(:root :verbose :quiet :help)
          :examples '("linacs validate -C ~/my-home"))
   (list :name "check" :fn #'cmd-check
          :summary "Fully resolve the configuration without executing anything"
          :options '(:root :profile :provider :platform :sudo-password-stdin :sudo-reset :verbose :quiet :help)
          :examples '("linacs check -C ~/my-home --profile work-laptop"))
   (list :name "explain" :fn #'cmd-explain
          :summary "Print the resolved feature graph and action order"
          :options '(:root :profile :provider :platform :verbose :quiet :help)
          :examples '("linacs explain -C ~/my-home --profile work-laptop"))
   (list :name "graph" :fn #'cmd-graph
         :summary "Print the abstract feature dependency graph"
         :options '(:root :profile :verbose :quiet :help)
         :examples '("linacs graph -C ~/my-home --profile work-laptop"))
   (list :name "export" :fn #'cmd-export
          :summary "Write the resolved action list as a data s-expression"
          :options '(:root :profile :provider :platform :output :format :verbose :quiet :help)
          :examples '("linacs export -C ~/my-home --profile work-laptop -o /tmp/plan.sexp"
                      "linacs export -C ~/my-home --profile work-laptop --format json -o /tmp/plan.json"))
   (list :name "list" :fn #'cmd-list
         :summary "List registered features, providers, catalogs, action types"
         :options '(:root :verbose :quiet :help)
         :examples '("linacs list -C ~/my-home"))
   (list :name "facts" :fn #'cmd-facts
          :summary "Print resolved facts, after probing and profile merge"
          :options '(:root :profile :platform :verbose :quiet :help)
          :examples '("linacs facts -C ~/my-home --profile work-laptop"))
   (list :name "doctor" :fn #'cmd-doctor
          :summary "Diagnose the environment and provider coverage"
          :options '(:root :profile :provider :platform :verbose :quiet :help)
          :examples '("linacs doctor -C ~/my-home --profile work-laptop"))
(list :name "init" :fn #'cmd-init
         :summary "Scaffold a new project"
         :options '(:root :example :help)
         :examples '("linacs init -C ~/my-home"
                     "linacs init -C ~/my-home --example   # seed a tiny working :shell project"))
   (list :name "version" :fn #'cmd-version
         :summary "Print the LINACS version"
         :options '(:help)
         :examples '("linacs version")))
  "One entry per CLI command: :name, :fn, :summary, the :options it
accepts (keys into *OPTION-SPECS*), and a few :examples.")

(defun command-spec (name)
  (find name *command-specs* :key (lambda (s) (getf s :name)) :test #'string=))

(defun print-options-table (option-keys)
  (let* ((rows (mapcar (lambda (k) (rest (assoc k *option-specs*))) option-keys))
         (width (reduce #'max (mapcar (lambda (r) (length (first r))) rows) :initial-value 0)))
    (dolist (r rows)
      (format t "  ~va  ~a~%" width (first r) (second r)))))

(defun print-command-help (spec)
  (format t "Usage: linacs ~a [options]~%~%~a~%~%Options:~%" (getf spec :name) (getf spec :summary))
  (print-options-table (getf spec :options))
  (when (getf spec :examples)
    (format t "~%Examples:~%")
    (dolist (e (getf spec :examples)) (format t "  ~a~%" e))))

(defun print-usage ()
  (format t "Usage: linacs <command> [options]~%~%Commands:~%")
  (let ((width (reduce #'max (mapcar (lambda (s) (length (getf s :name))) *command-specs*))))
    (dolist (s *command-specs*)
      (format t "  ~va  ~a~%" width (getf s :name) (getf s :summary))))
  (format t "~%Run `linacs <command> --help` to see that command's own options and examples.~%~%Global options:~%")
  (print-options-table (remove-duplicates
                        (reduce #'append (mapcar (lambda (s) (getf s :options)) *command-specs*)
                                :from-end t)
                        :from-end t)))

(defun main (&optional (argv (uiop:command-line-arguments)))
  (cond
    ((null argv) (print-usage))
    ((member (first argv) '("-h" "--help") :test #'string=) (print-usage))
    (t
     (let* ((command (first argv))
            (spec (command-spec command)))
       (if (not spec)
           (progn
             (linacs.log:error* "Unknown command: ~a" command)
             (terpri)
             (print-usage)
             (uiop:quit 1))
           (multiple-value-bind (opts unknown) (parse-args (rest argv))
             (cond
               ((cli-opts-help opts) (print-command-help spec))
               (unknown
                (linacs.log:error* "Unknown or malformed option(s) for '~a': ~{~a~^ ~}" command unknown)
                (terpri)
                (print-command-help spec)
                (uiop:quit 1))
               (t
                (linacs.log:set-verbosity (if (cli-opts-quiet opts) 0 (cli-opts-verbosity opts)))
                (with-cli-error-report (funcall (getf spec :fn) opts))))))))))
