;;;; src/action-types/helpers.lisp
;;;;
;;;; Shared utilities used by the built-in action executors: path/home
;;;; expansion, reading and writing files (with on-demand sudo escalation
;;;; when, and only when, a plain write actually fails for lack of
;;;; privilege), POSIX mode/owner/group inspection and mutation (same
;;;; escalate-on-demand pattern), running a command with or without sudo,
;;;; and the REPORT macro every executor uses to build its return value.
;;;;
;;;; The core policy this file implements, used throughout every action
;;;; executor: NEVER require the whole linacs process to run as root. Try
;;;; every filesystem operation as the invoking user first; only escalate
;;;; via sudo, for that one specific command, if the plain attempt
;;;; actually fails for lack of privilege. A plain dotfile write in your
;;;; own home directory should never touch sudo at all.

(in-package :linacs.core)

(defun invoking-user-home ()
  "The real, invoking user's home directory -- even when running under
sudo, where $HOME is reset to the target user's (root's, by default).
Falls back to plain $HOME when not running under sudo, and to \"/\" if
neither is available. This exists purely as a safety net for someone who
runs `sudo linacs` out of habit; linacs itself never asks you to."
  (let ((sudo-user (uiop:getenv "SUDO_USER")))
    (or (and sudo-user (plusp (length sudo-user))
             (ignore-errors
              (let* ((line (string-trim '(#\Newline)
                             (uiop:run-program (list "getent" "passwd" sudo-user)
                                                :output '(:string :stripped t))))
                     (fields (uiop:split-string line :separator '(#\:))))
                (nth 5 fields))))
        (uiop:getenv "HOME")
        "/")))

(defun expand-home (path)
  "Expand a leading ~ to the invoking user's home directory."
  (let ((home (invoking-user-home)))
    (if (and (> (length path) 0) (char= (char path 0) #\~))
        (concatenate 'string home (subseq path 1))
        path)))

(defun read-file-string (path)
  (when (probe-file path)
    (uiop:read-file-string path)))

(defun write-file-string (path content)
  (ensure-directories-exist path)
  (with-open-file (f path :direction :output :if-exists :supersede :if-does-not-exist :create)
    (write-string content f)))

(defun file-mode (path)
  "Best-effort POSIX permission bits for PATH, or nil if unavailable."
  (ignore-errors
   (parse-integer
    (string-trim '(#\Newline #\Space)
                 (uiop:run-program (list "stat" "-c" "%a" (namestring path))
                                    :output '(:string :stripped t)))
    :radix 8)))

(defun read-sudo-password-visible ()
  "Read password from *query-io* with echo ON.
Used as a fallback when the terminal cannot be manipulated
(e.g. no TTY, or sb-posix unavailable)."
  (format *query-io* "[sudo] password for ~a (will be visible): "
          (or (uiop:getenv "USER") "root"))
  (finish-output *query-io*)
  (string-trim '(#\Newline) (read-line *query-io* nil "")))

(defun read-sudo-password ()
  "Prompt for and read a sudo password with terminal echo disabled.
Operates directly on SBCL's own terminal fd via sb-posix:tcsetattr,
avoiding the need for any child-process terminal access.

NOTE: Uses SBCL-specific symbols (sb-unix:unix-isatty, sb-posix:tcgetattr,
sb-posix:tcsetattr). The visible-echo fallback READ-SUDO-PASSWORD-VISIBLE
is pure ANSI CL and is reached on any non-SBCL implementation or when the
sb-posix contrib is not loaded.

Falls back to READ-SUDO-PASSWORD-VISIBLE when no TTY is available or
when the terminal-manipulation calls fail (e.g. sb-posix contrib not
built, or running in a CI environment)."
  (if (plusp (sb-unix:unix-isatty 0))
      (handler-case
          (progn
            (require :sb-posix)
            (let* ((orig (sb-posix:tcgetattr 0))
                   (noecho (sb-posix:tcgetattr 0)))
              (setf (sb-posix:termios-lflag noecho)
                    (logandc2 (sb-posix:termios-lflag noecho) sb-posix:echo))
              (sb-posix:tcsetattr 0 sb-posix:tcsanow noecho)
              (unwind-protect
                   (progn
                     (format *query-io* "[sudo] password for ~a: "
                             (or (uiop:getenv "USER") "root"))
                     (finish-output *query-io*)
                     (string-trim '(#\Newline) (read-line *query-io* nil "")))
                (sb-posix:tcsetattr 0 sb-posix:tcsanow orig)
                (terpri *query-io*)
                (finish-output *query-io*))))
        (error ()
          (read-sudo-password-visible)))
      (read-sudo-password-visible)))

(defvar *sudo-askpass* (uiop:getenv "SUDO_ASKPASS")
  "Cached at load time. When set, RUN-PRIVILEGED uses `sudo -A` instead
of interactive password prompting, delegating to the askpass program
specified by the environment variable.")

(defvar *capture-subprocess-output* nil
  "When non-nil, RUN-PRIVILEGED captures subprocess stdout/stderr into
*CAPTURED-SUBPROCESS-LINES* instead of passing it through to the terminal.
Set by CMD-APPLY in non-verbose mode.")

(defvar *captured-subprocess-lines* nil
  "List of (stream-keyword . string) pairs captured during the current
action's subprocess calls.  Reset per action in EXECUTE-ACTION.")

(defun sudo-n-or-a-prefix ()
  "Return (list \"sudo\" \"-n\") for cached-credential use, or
(list \"sudo\" \"-A\") when SUDO_ASKPASS is set."
  (if (and *sudo-askpass* (plusp (length *sudo-askpass*)))
      (list "sudo" "-A")
      (list "sudo" "-n")))

(defun run-privileged (args &key input)
  "Run a command, prefixing with sudo unless already privileged.

Credentials are validated before the actual command runs:
  1. Try `sudo -n true`/`sudo -A true` -- if cached or askpass works, skip.
  2. Otherwise prompt for a password (echo off when possible) and cache
     it via `sudo -S true`.
  3. Run the real command with `~{~a~^ ~}` (no prompt, cached).

:INPUT -- string content to pass to the command's stdin (via
          MAKE-STRING-INPUT-STREAM).

Signals EXECUTION-FAILURE if the command exits non-zero."
  (let* ((needs-sudo-p (not (privileged-p))))
    (when needs-sudo-p
      (unless (zerop (nth-value 2
                      (uiop:run-program (append (sudo-n-or-a-prefix) (list "true"))
                                        :ignore-error-status t)))
        ;; Prompt interactively only when no askpass is configured.
        (unless *sudo-askpass*
          (let ((password (read-sudo-password)))
            (unless (zerop (nth-value 2
                            (uiop:run-program (list "sudo" "-S" "true")
                                              :input (make-string-input-stream
                                                      (format nil "~a~%" password))
                                              :ignore-error-status t)))
              (error 'execution-failure :action-type :privileged-command
                     :target "credential validation"
                     :underlying (format nil "sudo -S true failed -- wrong password?")))))))
    (let* ((prefix (if needs-sudo-p (sudo-n-or-a-prefix) '()))
           (cmd (append prefix args)))
      (when needs-sudo-p
        (linacs.log:debug* "Privileged command: ~{~a~^ ~}" cmd))
      (if *capture-subprocess-output*
          (let* ((out-str (make-string-output-stream))
                 (err-str (make-string-output-stream))
                 (exit-code (nth-value 2
                                (uiop:run-program cmd
                                                  :output out-str
                                                  :error-output err-str
                                                  :input (when input
                                                           (make-string-input-stream input))
                                                  :ignore-error-status t))))
            (let ((out (get-output-stream-string out-str))
                  (err (get-output-stream-string err-str)))
              (when (plusp (length out))
                (push (cons :stdout out) *captured-subprocess-lines*))
              (when (plusp (length err))
                (push (cons :stderr err) *captured-subprocess-lines*))
              (unless (zerop exit-code)
                (error 'execution-failure :action-type :privileged-command
                       :target (format nil "~{~a~^ ~}" args)
                       :underlying (format nil "Command exited with status ~d." exit-code)))
              exit-code))
          (let ((exit-code (nth-value 2
                               (uiop:run-program cmd :output t :error-output t
                                                 :input (when input
                                                          (make-string-input-stream input))
                                                 :ignore-error-status t))))
            (unless (zerop exit-code)
              (error 'execution-failure :action-type :privileged-command
                     :target (format nil "~{~a~^ ~}" args)
                     :underlying (format nil "Command exited with status ~d." exit-code)))
            exit-code)))))

(defun ensure-directories-with-escalation (dir)
  "Ensure DIR (and its parents) exist. Tries as the invoking user first;
only if that fails (the parent needs root to write into) does it retry
via a privileged `mkdir -p`."
  (handler-case (ensure-directories-exist (uiop:ensure-directory-pathname dir))
    (error ()
      (run-privileged (list "mkdir" "-p" (namestring (uiop:ensure-directory-pathname dir)))))))

(defun write-privileged-file (path content)
  "Write CONTENT to PATH via sudo unconditionally -- used internally by
WRITE-FILE-WITH-ESCALATION once a plain write has already failed, and
directly by executors that always target a root-owned path (e.g.
/etc/hostname). Pipes content through stdin to `sudo sh -c cat>PATH`,
avoiding any world-readable temporary files. Ensures the destination's
parent directory exists first, with the same escalate-if-needed policy."
  (ensure-directories-with-escalation (uiop:pathname-directory-pathname (pathname path)))
  (if (privileged-p)
      (write-file-string path content)
      (run-privileged (list "sh" "-c" (format nil "cat > ~a" path))
                      :input content)))

(defun write-file-with-escalation (path content)
  "Write CONTENT to PATH. Tries as the invoking user first; only if that
fails for lack of privilege does it fall back to WRITE-PRIVILEGED-FILE.
This is the one every executor targeting a person-supplied :target should
use -- a dotfile in your own home directory never touches sudo; a path
that genuinely needs root transparently does, for just that one write."
  (handler-case (write-file-string path content)
    (error () (write-privileged-file path content))))

(defun set-file-mode (path mode)
  "chmod PATH to MODE. Tries as the invoking user first; escalates via
sudo only if that plain attempt fails."
  (when mode
    (let ((args (list "chmod" (format nil "~o" mode) (namestring path))))
      (unless (zerop (nth-value 2 (uiop:run-program args :ignore-error-status t)))
        (run-privileged args)))))

(defun set-file-owner (path owner group)
  "chown PATH to OWNER:GROUP. Tries as the invoking user first (which
will simply fail if OWNER/GROUP isn't you, as Unix requires); escalates
via sudo only if that plain attempt fails."
  (when (or owner group)
    (let ((args (list "chown" (format nil "~a:~a" (or owner "") (or group "")) (namestring path))))
      (unless (zerop (nth-value 2 (uiop:run-program args :ignore-error-status t)))
        (run-privileged args)))))

(defun resolve-owner (action)
  "Per spec: :owner defaults to the calling (non-root) user, even under sudo."
  (or (getf action :owner) (uiop:getenv "SUDO_USER") (uiop:getenv "USER")))

(defun resolve-group (action)
  (or (getf action :group)
      (ignore-errors
       (string-trim '(#\Newline)
                     (uiop:run-program (list "id" "-gn") :output '(:string :stripped t))))))

(defun apply-file-ownership (path action)
  (set-file-mode path (getf action :mode))
  (set-file-owner path (resolve-owner action) (resolve-group action)))

(defun shell-ok-p (command)
  "T if COMMAND exits zero when run through /bin/sh, without emitting its
output to the terminal. Used for :only-if / :unless idempotency checks and
backend-detection probes."
  (zerop (nth-value 2 (uiop:run-program (list "sh" "-c" command) :ignore-error-status t))))

(defun which (program)
  "T if PROGRAM is found on PATH."
  (shell-ok-p (format nil "command -v ~a >/dev/null 2>&1" program)))

(defmacro report (status &rest kvs)
  "Build a uniform executor return value: a plist with :status plus extras."
  `(list :status ,status ,@kvs))
