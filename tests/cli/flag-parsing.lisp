(in-package #:linacs-tests)

(def-suite cli-flag-parsing
  :in linacs-tests
  :description "Tests for CLI option flag parsing")
(in-suite cli-flag-parsing)

(def-test parse-sudo-password-stdin ()
  "--sudo-password-stdin sets cli-opts-sudo-password-stdin to T"
  (multiple-value-bind (opts unknown)
      (linacs.core:parse-args '("--sudo-password-stdin"))
    (is (linacs.core:cli-opts-sudo-password-stdin opts))
    (is-false unknown)))

(def-test parse-sudo-reset ()
  "--sudo-reset sets cli-opts-sudo-reset to T"
  (multiple-value-bind (opts unknown)
      (linacs.core:parse-args '("--sudo-reset"))
    (is (linacs.core:cli-opts-sudo-reset opts))
    (is-false unknown)))

(def-test parse-both-sudo-flags ()
  "Both --sudo-password-stdin and --sudo-reset can be given together"
  (multiple-value-bind (opts unknown)
      (linacs.core:parse-args '("--sudo-password-stdin" "--sudo-reset"))
    (is (linacs.core:cli-opts-sudo-password-stdin opts))
    (is (linacs.core:cli-opts-sudo-reset opts))
    (is-false unknown)))

(def-test parse-sudo-flags-with-other-flags ()
  "sudo flags coexist with other options like --dry-run, --profile"
  (multiple-value-bind (opts unknown)
      (linacs.core:parse-args '("--sudo-password-stdin" "--dry-run" "--profile" "work"))
    (is (linacs.core:cli-opts-sudo-password-stdin opts))
    (is (linacs.core:cli-opts-dry-run opts))
    (is (eq (linacs.core:cli-opts-profile opts) :work))
    (is-false (linacs.core:cli-opts-sudo-reset opts))
    (is-false unknown)))

(def-test parse-sudo-flags-defaults ()
  "Default cli-opts has sudo flags as NIL"
  (let ((opts (linacs.core:make-cli-opts)))
    (is-false (linacs.core:cli-opts-sudo-password-stdin opts))
    (is-false (linacs.core:cli-opts-sudo-reset opts))))

(def-test parse-unknown-flag-is-collected ()
  "An unrecognized flag is collected in unknown-flags, not silently ignored"
  (multiple-value-bind (opts unknown)
      (linacs.core:parse-args '("--sudo-password-stdin" "--bogus-flag"))
    (is (linacs.core:cli-opts-sudo-password-stdin opts))
    (is (equal unknown '("--bogus-flag")))))

(def-test parse-verbosity-single-v ()
  "-v raises verbosity by one above the default of 1 (to 2)"
  (multiple-value-bind (opts unknown)
      (linacs.core:parse-args '("-v"))
    (is (= (linacs.core:cli-opts-verbosity opts) 2))
    (is-false unknown)))

(def-test parse-verbosity-double-v ()
  "-vv raises verbosity by two above the default of 1 (to 3)"
  (multiple-value-bind (opts unknown)
      (linacs.core:parse-args '("-vv"))
    (is (= (linacs.core:cli-opts-verbosity opts) 3))
    (is-false unknown)))

(def-test parse-verbosity-triple-v ()
  "-vvv raises verbosity to 4 (was previously rejected as an unknown flag)"
  (multiple-value-bind (opts unknown)
      (linacs.core:parse-args '("-vvv"))
    (is (= (linacs.core:cli-opts-verbosity opts) 4))
    (is-false unknown)))

(def-test parse-verbosity-quadruple-v ()
  "-vvvv raises verbosity to 5"
  (multiple-value-bind (opts unknown)
      (linacs.core:parse-args '("-vvvv"))
    (is (= (linacs.core:cli-opts-verbosity opts) 5))
    (is-false unknown)))

(def-test parse-verbose-long-form ()
  "--verbose raises verbosity by one and is not misparsed as a -v run"
  (multiple-value-bind (opts unknown)
      (linacs.core:parse-args '("--verbose"))
    (is (= (linacs.core:cli-opts-verbosity opts) 2))
    (is-false unknown)))

(def-test parse-verbosity-default ()
  "No verbosity flags leaves the default of 1 in place"
  (multiple-value-bind (opts unknown)
      (linacs.core:parse-args '("--platform" "fedora"))
    (is (= (linacs.core:cli-opts-verbosity opts) 1))
    (is-false unknown)))

(def-test parse-provider-override ()
  "--provider T=P is parsed into cli-opts-provider-overrides as a (feature . provider) cons"
  (multiple-value-bind (opts unknown)
      (linacs.core:parse-args '("--provider" ":editor=:emacs"))
    (is (equal (linacs.core:cli-opts-provider-overrides opts) '((:editor . :emacs))))
    (is-false unknown)))

(def-test parse-provider-override-repeatable ()
  "Repeated --provider flags accumulate into the overrides list"
  (multiple-value-bind (opts unknown)
      (linacs.core:parse-args '("--provider" ":editor=:emacs" "--provider" ":shell=:fish"))
    ;; overrides are pushed, so the last flag is at the head
    (is (equal (linacs.core:cli-opts-provider-overrides opts) '((:shell . :fish) (:editor . :emacs))))
    (is-false unknown)))

(def-test parse-platform-flag ()
  "--platform NAME stores the raw platform string"
  (multiple-value-bind (opts unknown)
      (linacs.core:parse-args '("--platform" "fedora"))
    (is (string= (linacs.core:cli-opts-platform opts) "fedora"))
    (is-false unknown)))

(def-test parse-example-flag ()
  "--example sets cli-opts-example to T and is not reported unknown"
  (multiple-value-bind (opts unknown)
      (linacs.core:parse-args '("--example"))
    (is (linacs.core:cli-opts-example opts))
    (is-false unknown)))

(def-test parse-example-flag-with-root ()
  "--example coexists with -C"
  (multiple-value-bind (opts unknown)
      (linacs.core:parse-args '("--example" "-C" "/tmp/my-home"))
    (is (linacs.core:cli-opts-example opts))
    (is (equal (linacs.core:cli-opts-root opts) "/tmp/my-home"))
    (is-false unknown)))

(def-test parse-example-flag-default ()
  "Default cli-opts has example as NIL"
  (is-false (linacs.core:cli-opts-example (linacs.core:make-cli-opts))))
