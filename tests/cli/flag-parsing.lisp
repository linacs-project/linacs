(in-package #:linacs-tests)

(def-suite cli-flag-parsing
  :description "Tests for CLI option flag parsing")

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
