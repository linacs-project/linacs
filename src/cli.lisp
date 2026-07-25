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
                            (push (cons (intern (string-upcase (subseq kv 0 pos)) :keyword)
                                        (intern (string-upcase (subseq kv (1+ pos))) :keyword))
                                  (cli-opts-provider-overrides opts))
                            (push a unknown)))
                      (push a unknown)))
                 ((or (string= a "-n") (string= a "--dry-run")) (setf (cli-opts-dry-run opts) t))
                 ((string= a "--continue") (setf (cli-opts-continue-on-error opts) t))
                 ((or (string= a "-o") (string= a "--output"))
                  (if args (setf (cli-opts-output opts) (pop args)) (push a unknown)))
                 ((string= a "-vv") (incf (cli-opts-verbosity opts) 2))
                 ((or (string= a "-v") (string= a "--verbose")) (incf (cli-opts-verbosity opts)))
                 ((string= a "--quiet") (setf (cli-opts-quiet opts) t) (setf (cli-opts-verbosity opts) 0))
                 ((and (> (length a) 0) (char= (char a 0) #\-)) (push a unknown))
                 (t nil)))) ; a bare positional argument -- no command currently takes one, so ignore it
    (values opts (nreverse unknown))))

(defun reset-project-registries ()
  "Clear every registry that Discovery (re-)populates from scratch on each
invocation. Without this, calling MAIN more than once in a long-lived Lisp
image (a REPL, a saved image used interactively) would silently accumulate
duplicate pipeline hooks -- register-pipeline-hook has no identity to
de-duplicate by, unlike DEFINE-FEATURE/REGISTER-PROVIDER/DEFINE-CATALOG,
which already overwrite cleanly by name. A fresh per-invocation process
never notices this; a persistent one does."
  (clrhash *fact-probers*)
  (clrhash *feature-registry*)
  (clrhash *providers*)
  (clrhash *catalogs*)
  (clrhash *profiles*)
  (clrhash *pipeline-hooks*)
  (setf *current-home-thunk* nil))

(defun bootstrap (opts)
  "Run Discovery (step 0) against OPTS's project root."
  (reset-project-registries)
  (default-fact-probers)
  (discover-plugins)
  (discover-project-plugins (cli-opts-root opts))
  (discover-project (cli-opts-root opts)))

(defmacro with-cli-error-report (&body body)
  `(handler-case (progn ,@body)
     (linacs-error (e)
       (linacs.log:error* "~a" e)
       (uiop:quit 1))
     (error (e)
       (linacs.log:error* "Unexpected error: ~a" e)
       (uiop:quit 1))))

(defparameter *print-table-max-width* 60
  "Maximum column width for PRINT-TABLE; longer cells are truncated.")

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
                                         (cons (length (nth i truncated-headers))
                                               (mapcar (lambda (r) (length (or (nth i r) ""))) truncated-rows))))))
      (flet ((row-string (cells)
               (format nil "  ~{~a~^  ~}"
                       (loop for i below ncols collect (format nil "~va" (nth i widths) (or (nth i cells) ""))))))
        (format t "~a~%" (row-string truncated-headers))
        (format t "~a~%" (row-string (mapcar (lambda (w) (make-string w :initial-element #\-)) widths)))
        (dolist (r truncated-rows) (format t "~a~%" (row-string r)))))))

(defun action-type-counts (actions)
  (let ((counts (make-hash-table :test 'eq)))
    (dolist (a actions) (incf (gethash (action-type a) counts 0)))
    (sort (loop for k being the hash-key of counts using (hash-value v) collect (cons k v))
          #'string< :key (lambda (p) (string (car p))))))

(defun cmd-plan (opts)
  (bootstrap opts)
  (multiple-value-bind (ordered home) (run-pipeline :profile (cli-opts-profile opts)
                                                       :project-root (cli-opts-root opts)
                                                       :execute-mode :plan-only)
    (format t "Resolved plan for ~a (traits: ~a):~%~%" (getf home :name) (or (getf home :traits) "none"))
    (print-table '("TYPE" "TARGET")
                 (mapcar (lambda (a) (list (string-downcase (string (action-type a)))
                                            (princ-to-string (action-target a))))
                         ordered))
    (format t "~%~d action(s)~@[ -- ~{~a~^, ~}~]~%"
            (length ordered)
            (and ordered (mapcar (lambda (p) (format nil "~a ~(~a~)" (cdr p) (car p))) (action-type-counts ordered))))))

(defun cmd-check (opts)
  (bootstrap opts)
  (run-pipeline :profile (cli-opts-profile opts) :project-root (cli-opts-root opts) :execute-mode :plan-only)
  (format t "Configuration resolves cleanly.~%"))

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

(defun cmd-apply (opts)
  (bootstrap opts)
  (run-pipeline :profile (cli-opts-profile opts) :project-root (cli-opts-root opts)
                :execute-mode (if (cli-opts-dry-run opts) :check :apply))
  (format t "Apply complete.~%"))

(defun cmd-diff (opts)
  "Resolve the plan and check each action against current system state.
Uses :plan-only mode (not :check) because run-pipeline's :check mode
dispatches executors inline but doesn't capture individual results;
we call execute-action separately to collect :would-change statuses."
  (bootstrap opts)
  (multiple-value-bind (ordered home) (run-pipeline :profile (cli-opts-profile opts)
                                                       :project-root (cli-opts-root opts)
                                                       :execute-mode :plan-only)
    (let ((changes (loop for a in ordered
                         for result = (execute-action a :mode :check)
                         when (eq (getf result :status) :would-change)
                           collect (list (string-downcase (string (action-type a)))
                                          (princ-to-string (action-target a))))))
      (if changes
          (progn
            (format t "~a differs from the resolved plan for ~a:~%~%" (or (cli-opts-root opts) ".") (getf home :name))
            (print-table '("TYPE" "TARGET") changes)
            (format t "~%~d action(s) would change.~%" (length changes)))
          (format t "No differences -- the system already matches the resolved plan for ~a.~%" (getf home :name))))))

(defun cmd-explain (opts)
  (bootstrap opts)
  (multiple-value-bind (ordered home) (run-pipeline :profile (cli-opts-profile opts)
                                                       :project-root (cli-opts-root opts)
                                                       :execute-mode :plan-only)
    (format t "Home: ~a~%Traits: ~a~%~%Features used:~%" (getf home :name) (or (getf home :traits) "none"))
    (print-table '("FEATURE" "PROVIDER USED" "DESCRIPTION")
                 (mapcar (lambda (r)
                           (let* ((fname (getf r :feature))
                                  (feature (feature-by-name fname)))
                             (multiple-value-bind (fn chosen-name) (select-provider fname (getf r :via))
                               (declare (ignore fn))
                               (list (string-downcase (string fname))
                                     (if chosen-name (string-downcase (string chosen-name)) "(skipped)")
                                     (or (feature-description feature) "")))))
                         (getf home :use-features)))
    (format t "~%Action order:~%")
    (print-table '("#" "TYPE" "TARGET")
                 (loop for a in ordered for i from 1
                       collect (list (princ-to-string i) (string-downcase (string (action-type a)))
                                      (princ-to-string (action-target a)))))
    (format t "~%~d action(s).~%" (length ordered))))

(defun cmd-graph (opts)
  (bootstrap opts)
  (probe-all-facts) (apply-profile (cli-opts-profile opts))
  (let ((home (run-current-home-thunk)))
    (if (getf home :use-features)
        (dolist (r (getf home :use-features))
          (let* ((fname (getf r :feature))
                 (feature (feature-by-name fname)))
            (format t "~a~@[ -- ~a~]~%" (string-downcase (string fname)) (feature-description feature))
            (dolist (dep (feature-requires feature))
              (format t "  requires ~a~%" (string-downcase (string dep))))))
        (format t "(no use-feature forms in this home)~%"))))

(defun cmd-export (opts)
  (bootstrap opts)
  (multiple-value-bind (ordered home) (run-pipeline :profile (cli-opts-profile opts)
                                                       :project-root (cli-opts-root opts)
                                                       :execute-mode :plan-only)
    (declare (ignore home))
    (let ((out (if (cli-opts-output opts) (open (cli-opts-output opts) :direction :output :if-exists :supersede) t))
          (form (list :actions ordered)))
      (unwind-protect (progn (print form out) (terpri out))
        (unless (eq out t) (close out))))))

(defun feature-provider-summary (fname)
  "One string summarizing every provider registered for FNAME, e.g.
\"bash (default), zsh\" -- this is the combined FEATURE | PROVIDERS view."
  (let ((candidates (find-providers-for fname)))
    (if candidates
        (format nil "~{~a~^, ~}"
                (mapcar (lambda (p) (format nil "~(~a~)~a" (first p) (if (third p) " (default)" "")))
                        (reverse candidates)))
        "(none registered)")))

(defun cmd-list (opts)
  (bootstrap opts)
  (format t "Features:~%")
  (let ((rows (loop for k being the hash-key of *feature-registry* using (hash-value f)
                     collect (list (string-downcase (string k))
                                    (or (feature-description f) "")
                                    (feature-provider-summary k)))))
    (if rows
        (print-table '("FEATURE" "DESCRIPTION" "PROVIDERS") (sort rows #'string< :key #'first))
        (format t "  (none registered)~%")))
  (terpri)

  (format t "Providers:~%")
  (let ((rows (loop for fname being the hash-key of *providers* using (hash-value plist)
                     append (mapcar (lambda (p)
                                      (list (string-downcase (string (first p)))
                                             (string-downcase (string fname))
                                             (if (third p) "yes" "")
                                             (or (fourth p) "")))
                                    plist))))
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
    (print-table '("TYPE" "DESCRIPTION") (sort rows #'string< :key #'first))))

(defun cmd-facts (opts)
  "Print every resolved fact -- after probing and merging the selected
--profile -- one per line, aligned. Useful for answering \"why did LINACS pick
that provider on this machine\" without re-deriving it from probes."
  (bootstrap opts)
  (probe-all-facts)
  (apply-profile (cli-opts-profile opts))
  (let* ((pairs (loop for (k v) on *facts* by #'cddr collect (cons k v)))
         (sorted (sort (copy-list pairs) #'string< :key (lambda (p) (string (car p)))))
         (width (reduce #'max (mapcar (lambda (p) (length (string (car p)))) sorted) :initial-value 0)))
    (dolist (p sorted)
      (format t "~va  ~s~%" width (string (car p)) (cdr p)))))

(defun feature-resolution-summary (r)
  "How feature request R will actually resolve: the chosen provider name,
or a clear diagnosis of why it can't resolve -- used by `linacs doctor`."
  (let* ((fname (getf r :feature))
         (via (getf r :via))
         (candidates (find-providers-for fname)))
    (cond
      ((null candidates) "NO PROVIDER REGISTERED")
      (via (if (assoc via candidates) (string-downcase (string via))
               (format nil "VIA ~a NOT FOUND" via)))
      ((= (length candidates) 1) (string-downcase (string (first (first candidates)))))
      (t (let ((defaults (remove-if-not #'third candidates)))
           (cond
             ((= (length defaults) 1) (string-downcase (string (first (first defaults)))))
             ((> (length defaults) 1) "MULTIPLE :DEFAULT T PROVIDERS -- AMBIGUOUS")
             (t "AMBIGUOUS -- needs :via, or mark one :default t")))))))

(defun cmd-doctor (opts)
  (bootstrap opts)
  (probe-all-facts) (apply-profile (cli-opts-profile opts))
  (format t "OS: ~a~%Hostname: ~a~%Privileged (can install packages): ~a~%~%"
          (fact :os) (fact :hostname) (privileged-p))
  (let ((home (run-current-home-thunk)))
    (format t "Home: ~a (traits: ~a)~%~%" (getf home :name) (or (getf home :traits) "none"))
    (format t "Feature resolution:~%")
    (if (getf home :use-features)
        (print-table '("FEATURE" "RESOLVES TO")
                     (mapcar (lambda (r) (list (string-downcase (string (getf r :feature)))
                                                 (feature-resolution-summary r)))
                             (getf home :use-features)))
        (format t "  (no use-feature forms in this home)~%"))
    (let* ((all-actions (append (getf home :actions) (collect-actions-from-features (getf home :use-features))))
           (privileged-count (count-if #'action-needs-privilege-p all-actions)))
      (format t "~%Package installs requiring privilege: ~d~a~%"
              privileged-count
              (if (and (> privileged-count 0) (not (privileged-p)))
                  " -- linacs apply will use sudo for just those steps; you may be prompted"
                  "")))))

(defun cmd-init (opts)
  (let ((root (uiop:ensure-directory-pathname (cli-opts-root opts))))
    (dolist (d (cons "files" *conventional-directories*))
      (ensure-directories-exist (merge-pathnames (make-pathname :directory (list :relative d)) root)))
    (let ((home-file (merge-pathnames "home.lisp" root)))
      (unless (probe-file home-file)
        (with-open-file (s home-file :direction :output)
          (format s ";;;; home.lisp~%(define-home my-home~%  :traits (:prune-explicitly-disabled))~%"))))
    (format t "Initialized LINACS project at ~a~%" root)))

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
    (:platform "-p, --platform NAME" "Target platform (default: auto-detect)")
    (:profile  "--profile NAME"      "Select a defined profile (fact overrides)")
    (:provider "--provider T=P"      "Prefer provider P for feature T")
    (:dry-run  "-n, --dry-run"       "Show changes without executing them")
    (:continue "--continue"          "Keep going after a failed action")
    (:output   "-o, --output FILE"   "Write output to FILE")
    (:verbose  "-v, --verbose"       "Increase verbosity (repeatable: -v, -vv)")
    (:quiet    "--quiet"             "Only show errors")
    (:help     "-h, --help"          "Show this command's help and exit")))

(defparameter *command-specs*
  (list
   (list :name "plan" :fn #'cmd-plan
         :summary "Show the resolved, ordered action list"
         :options '(:root :profile :verbose :quiet :help)
         :examples '("linacs plan -C ~/my-home --profile work-laptop"))
   (list :name "apply" :fn #'cmd-apply
         :summary "Execute the ordered action list"
         :options '(:root :profile :dry-run :continue :verbose :quiet :help)
         :examples '("linacs apply -C ~/my-home --profile work-laptop   # sudo (if needed) is per-action, not up front"
                     "linacs apply -C ~/my-home --profile work-laptop -n   # dry run"))
   (list :name "diff" :fn #'cmd-diff
         :summary "Show which actions would change something"
         :options '(:root :profile :verbose :quiet :help)
         :examples '("linacs diff -C ~/my-home --profile work-laptop"))
   (list :name "validate" :fn #'cmd-validate
         :summary "Check configuration syntax only (facts/providers untouched)"
         :options '(:root :verbose :quiet :help)
         :examples '("linacs validate -C ~/my-home"))
   (list :name "check" :fn #'cmd-check
         :summary "Fully resolve the configuration without executing anything"
         :options '(:root :profile :verbose :quiet :help)
         :examples '("linacs check -C ~/my-home --profile work-laptop"))
   (list :name "explain" :fn #'cmd-explain
         :summary "Print the resolved feature graph and action order"
         :options '(:root :profile :verbose :quiet :help)
         :examples '("linacs explain -C ~/my-home --profile work-laptop"))
   (list :name "graph" :fn #'cmd-graph
         :summary "Print the abstract feature dependency graph"
         :options '(:root :profile :verbose :quiet :help)
         :examples '("linacs graph -C ~/my-home --profile work-laptop"))
   (list :name "export" :fn #'cmd-export
         :summary "Write the resolved action list as a data s-expression"
         :options '(:root :profile :output :verbose :quiet :help)
         :examples '("linacs export -C ~/my-home --profile work-laptop -o /tmp/plan.sexp"))
   (list :name "list" :fn #'cmd-list
         :summary "List registered features, providers, catalogs, action types"
         :options '(:root :verbose :quiet :help)
         :examples '("linacs list -C ~/my-home"))
   (list :name "facts" :fn #'cmd-facts
         :summary "Print resolved facts, after probing and profile merge"
         :options '(:root :profile :verbose :quiet :help)
         :examples '("linacs facts -C ~/my-home --profile work-laptop"))
   (list :name "doctor" :fn #'cmd-doctor
         :summary "Diagnose the environment and provider coverage"
         :options '(:root :profile :verbose :quiet :help)
         :examples '("linacs doctor -C ~/my-home --profile work-laptop"))
   (list :name "init" :fn #'cmd-init
         :summary "Scaffold a new project"
         :options '(:root :help)
         :examples '("linacs init -C ~/my-home"))
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
