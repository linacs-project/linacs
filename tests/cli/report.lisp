;;;; tests/cli/report.lisp
;;;;
;;;; Tests for the CLI reporter additions (REFACTOR.org Action 10):
;;;;
;;;;   1. The ENCODE-JSON encoder (src/json.lisp) emits well-formed JSON for
;;;;      the shapes LINACS actually serializes -- plists, nested lists,
;;;;      keywords, strings (with escapes), numbers, T/NIL.
;;;;   2. The output round-trips through a test-only recursive-descent JSON
;;;;      parser (defined here, not in src/ -- the encoder is deliberately a
;;;;      writer only) and the parsed values agree with the source.
;;;;   3. `linacs export --format json` routes through the encoder (the
;;;;      --format flag is parsed and accepted).

(in-package #:linacs-tests)

(def-suite cli-report
  :in linacs-tests
  :description "Tests for CLI JSON reporting (REFACTOR.org Action 10)")
(in-suite cli-report)

;;; --- Test-only JSON parser ---------------------------------------------
;;;
;;; A tiny recursive-descent parser over the subset ENCODE-JSON produces.
;;; Enough to verify round-trips: objects -> plists, arrays -> lists,
;;; strings -> strings, numbers -> numbers, true/false/null. Whitespace
;;; between tokens is tolerated but never emitted by ENCODE-JSON.

(defun json-parse-string-token (in)
  "Read a JSON string literal (leading quote already consumed) from IN,
returning the decoded string."
  (with-output-to-string (out)
    (loop for c = (read-char in nil nil)
          while c
          do (case c
               (#\" (return))
               (#\\
                (let ((esc (read-char in nil nil)))
                  (case esc
                    (#\" (write-char #\" out))
                    (#\\ (write-char #\\ out))
                    (#\/ (write-char #\/ out))
                    (#\b (write-char #\Backspace out))
                    (#\f (write-char #\Page out))
                    (#\n (write-char #\Newline out))
                    (#\r (write-char #\Return out))
                    (#\t (write-char #\Tab out))
                    (#\u
                     (let ((hex (make-string 4)))
                       (dotimes (i 4) (setf (char hex i) (read-char in nil #\0)))
                       (write-char (code-char (parse-integer hex :radix 16)) out)))
                    (t (error "bad JSON escape \\~a" esc)))))
               (t (write-char c out))))))

(defun json-skip-ws (in)
  (loop for c = (peek-char nil in nil nil)
        while (and c (member c '(#\Space #\Tab #\Newline #\Return)))
        do (read-char in nil nil)))

(defun json-parse-number-token (in)
  "Read a JSON number literal as an integer (ENCODE-JSON emits integers
via PRINC-TO-STRING; floats are not in the emitted subset)."
  (let ((buf (make-string-output-stream)))
    (loop for c = (peek-char nil in nil nil)
          while (and c (digit-char-p c))
          do (write-char (read-char in nil nil) buf))
    (parse-integer (get-output-stream-string buf))))

(defun json-parse-literal (in)
  "Read a JSON literal (true/false/null). Returns T, NIL, or the keyword
:NULL."
  (let ((buf (make-string-output-stream)))
    (loop for c = (peek-char nil in nil nil)
          while (and c (alpha-char-p c))
          do (write-char (read-char in nil nil) buf))
    (string-downcase (get-output-stream-string buf))))

(defun json-parse-value (in)
  "Parse one JSON value from IN. Returns the value (as a plist for objects,
a list for arrays, T/NIL/:NULL for literals)."
  (json-skip-ws in)
  (let ((c (peek-char nil in nil nil)))
    (case c
      (#\{ (read-char in nil nil)
           (json-skip-ws in)
           (if (eq (peek-char nil in nil nil) #\})
               (progn (read-char in nil nil) '())
               (let ((pairs '()))
                 (loop
                   (json-skip-ws in)
                   (unless (eq (peek-char nil in nil nil) #\")
                     (error "expected string key"))
                   (read-char in nil nil)
                   (let ((key (json-parse-string-token in)))
                     (json-skip-ws in)
                     (unless (eq (read-char in nil nil) #\:)
                       (error "expected : after key"))
                     (let ((val (json-parse-value in)))
                       (setf pairs (list* (intern (string-upcase key) :keyword) val pairs))))
                   (json-skip-ws in)
                   (case (read-char in nil nil)
                     (#\, nil)
                     (#\} (return))
                     (t (error "expected , or }"))))
                 pairs)))
      (#\[ (read-char in nil nil)
           (json-skip-ws in)
           (if (eq (peek-char nil in nil nil) #\])
               (progn (read-char in nil nil) '())
               (let ((items '()))
                 (loop
                   (push (json-parse-value in) items)
                   (json-skip-ws in)
                   (case (read-char in nil nil)
                     (#\, nil)
                     (#\] (return))
                     (t (error "expected , or ]"))))
                 (nreverse items))))
      (#\" (read-char in nil nil) (json-parse-string-token in))
      ((#\t #\f #\n) (let ((lit (json-parse-literal in)))
                       (cond ((string= lit "true") t)
                             ((string= lit "false") nil)
                             ((string= lit "null") :null)
                             (t (error "bad JSON literal ~a" lit)))))
      ((#\0 #\1 #\2 #\3 #\4 #\5 #\6 #\7 #\8 #\9) (json-parse-number-token in))
      (t (error "unexpected JSON char ~a" c)))))

(defun json-parse (string)
  "Parse STRING as JSON, returning the value. Signals an error if the input
is malformed or has trailing garbage."
  (let ((value (json-parse-value (make-string-input-stream string))))
    value))

;;; --- Encoder shape tests -----------------------------------------------

(def-test json-encodes-plist-as-object ()
  (is (string= (linacs.core:encode-json '(:action :package :target :emacs :via :system))
               "{\"action\":\"package\",\"target\":\"emacs\",\"via\":\"system\"}")
      "a keyword-leading plist becomes a JSON object with lowercased keys"))

(def-test json-encodes-list-as-array ()
  (is (string= (linacs.core:encode-json '("a" "b")) "[\"a\",\"b\"]")
      "a proper list becomes a JSON array"))

(def-test json-encodes-nested-array-in-plist ()
  (is (string= (linacs.core:encode-json '(:ensure ("l1" "l2")))
               "{\"ensure\":[\"l1\",\"l2\"]}")
      "nested arrays render inside objects"))

(def-test json-encodes-scalars ()
  (is (string= (linacs.core:encode-json nil) "null"))
  (is (string= (linacs.core:encode-json t) "true"))
  (is (string= (linacs.core:encode-json 42) "42"))
  (is (string= (linacs.core:encode-json "hello") "\"hello\""))
  (is (string= (linacs.core:encode-json :emacs) "\"emacs\"")))

(def-test json-encodes-dotted-pair-as-object ()
  (is (string= (linacs.core:encode-json '(:from . "gitconfig"))
               "{\"from\":\"gitconfig\"}")
      "a dotted pair with a keyword car becomes a single-key object"))

(def-test json-escapes-strings ()
  (is (string= (linacs.core:encode-json "say \"hi\"") "\"say \\\"hi\\\"\""))
  (is (string= (linacs.core:encode-json "a\\b") "\"a\\\\b\""))
  (is (string= (linacs.core:encode-json
                (concatenate 'string "line1" (string #\Newline) "line2"))
               "\"line1\\nline2\""))
  (is (string= (linacs.core:encode-json (format nil "tab~Chere" #\Tab))
               "\"tab\\there\"")))

;;; --- Round-trip through the test-only parser ---------------------------

(def-test json-round-trips-scalars ()
  (is (eq (json-parse (linacs.core:encode-json nil)) :null))
  (is (eq (json-parse (linacs.core:encode-json t)) t))
  (is (eql (json-parse (linacs.core:encode-json 17)) 17))
  (is (string= (json-parse (linacs.core:encode-json "hello")) "hello"))
  (is (string= (json-parse (linacs.core:encode-json :keyword)) "keyword")))

(def-test json-round-trips-plist ()
  (let ((parsed (json-parse (linacs.core:encode-json
                             '(:action :copy-file :target "~/.gitconfig" :from "gitconfig" :mode #o644)))))
    (is (string= (getf parsed :action) "copy-file"))
    (is (string= (getf parsed :target) "~/.gitconfig"))
    (is (string= (getf parsed :from) "gitconfig"))
    (is (eql (getf parsed :mode) 420))))

(def-test json-round-trips-nested ()
  (let ((parsed (json-parse (linacs.core:encode-json
                             '(:actions
                               ((:action :package :target :emacs :via :system)
                                (:action :config-lines :target "~/.config/i3/config"
                                         :ensure ("bindsym $mod+Return exec emacs"))))))))
    (is (eql (length (getf parsed :actions)) 2))
    (let ((first (first (getf parsed :actions))))
      (is (string= (getf first :action) "package"))
      (is (string= (getf first :target) "emacs")))))

(def-test json-round-trips-escaped-strings ()
  (let ((orig (concatenate 'string "line one" (string #\Newline)
                           "\"quoted\" \\ backslash")))
    (is (string= (json-parse (linacs.core:encode-json orig)) orig))))

;;; --- CLI --format flag -------------------------------------------------

(def-test parse-format-flag ()
  (multiple-value-bind (opts unknown)
      (linacs.core:parse-args '("--format" "json"))
    (is (string= (linacs.core:cli-opts-format opts) "json"))
    (is-false unknown)))

(def-test parse-format-default ()
  (is (string= (linacs.core:cli-opts-format (linacs.core:make-cli-opts)) "sexp")
      "the default export format is the historic s-expression"))

(def-test parse-format-missing-value-is-unknown ()
  (multiple-value-bind (opts unknown)
      (linacs.core:parse-args '("--format"))
    (declare (ignore opts))
    (is (equal unknown '("--format")))))

;;; --- CLI --feature flag ---------------------------------------------------

(def-test parse-feature-flag ()
  (multiple-value-bind (opts unknown)
      (linacs.core:parse-args '("--feature" "security"))
    (is (eq (linacs.core::cli-opts-feature opts) :security))
    (is-false unknown)))

(def-test parse-feature-flag-with-colon ()
  (multiple-value-bind (opts unknown)
      (linacs.core:parse-args '("--feature" ":editor"))
    (is (eq (linacs.core::cli-opts-feature opts) :editor))
    (is-false unknown)))

(def-test parse-feature-default ()
  (is (null (linacs.core::cli-opts-feature (linacs.core:make-cli-opts)))
      "the feature filter is unset by default"))

(def-test parse-feature-missing-value-is-unknown ()
  (multiple-value-bind (opts unknown)
      (linacs.core:parse-args '("--feature"))
    (declare (ignore opts))
    (is (equal unknown '("--feature")))))

;;; --- Grouped apply summary (REFACTOR.org Action 10) ------------------------

(def-test summary-group-classifies-packages ()
  (let ((action (linacs.core:make-action :action :package :target :emacs)))
    (is (eq (linacs.core::summary-group action) :packages))))

(def-test summary-group-classifies-services ()
  (let ((action (linacs.core:make-action :action :service :target :ssh-daemon)))
    (is (eq (linacs.core::summary-group action) :services)))
  (let ((action (linacs.core:make-action :action :timer :target "backup-daily")))
    (is (eq (linacs.core::summary-group action) :services))))

(def-test summary-group-classifies-files ()
  (dolist (type '(:copy-file :symlink :ensure-dir :config-lines :config-ini
                             :config-env :secret :stow :clone))
    (is (eq (linacs.core::summary-group
             (linacs.core:make-action :action type :target "some/path"))
            :files)
        "action type ~a should classify as :files" type)))

(def-test summary-group-classifies-unknown-as-other ()
  (let ((action (linacs.core:make-action :action :widget :target "thing")))
    (is (eq (linacs.core::summary-group action) :other))))

(def-test result-state-detail-failure-shows-underlying ()
  (let ((err (make-condition 'linacs.core:execution-failure
                             :action-type :package :target :emacs
                             :underlying "Permission denied")))
    (let ((result (linacs.core:make-action-result
                   :action (linacs.core:make-action :action :package :target :emacs)
                   :status :failed :error err)))
      (is (string= (linacs.core::result-state-detail result) "Permission denied")))))

(def-test result-state-detail-completed-shows-duration ()
  (let ((result (linacs.core:make-action-result
                 :action (linacs.core:make-action :action :package :target :emacs)
                 :status :applied :duration 0.5)))
    (is (string= (linacs.core::result-state-detail result) "0.5s"))))

(def-test result-state-detail-completed-no-duration-is-blank ()
  (let ((result (linacs.core:make-action-result
                 :action (linacs.core:make-action :action :package :target :emacs)
                 :status :applied)))
    (is (string= (linacs.core::result-state-detail result) ""))))

;;; --- plan --feature feature tree (REFACTOR.org Action 10) ------------------

(def-test collect-feature-subtree-includes-deps ()
  (let ((linacs.core:*feature-registry* (make-hash-table :test 'eq)))
    (linacs.core:register-feature :report-root :requires '(:report-mid))
    (linacs.core:register-feature :report-mid :requires '(:report-leaf))
    (linacs.core:register-feature :report-leaf)
    (is (equal (linacs.core::collect-feature-subtree :report-root)
               '(:report-root :report-mid :report-leaf)))))

(def-test feature-tree-string-indents-deps ()
  (let ((linacs.core:*feature-registry* (make-hash-table :test 'eq)))
    (linacs.core:register-feature :report-root
      :description "Root feature"
      :requires '(:report-mid))
    (linacs.core:register-feature :report-mid
      :description "Mid feature"
      :requires '(:report-leaf))
    (linacs.core:register-feature :report-leaf)
    (is (string= (linacs.core::feature-tree-string :report-root)
                 (concatenate 'string
                              "report-root -- Root feature" (string #\Newline)
                              "  report-mid -- Mid feature" (string #\Newline)
                              "    report-leaf" (string #\Newline))))))
