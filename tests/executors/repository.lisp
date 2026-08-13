;;;; tests/executors/repository.lisp
;;;;
;;;; Tests for the :repository action executor and its method registry.
;;;;
;;;; The executor is tested through the REGISTER-REPOSITORY-METHOD seam with
;;;; fixture methods (pure functions, no real repos touched): :check-mode
;;;; must report :would-change/:unchanged without side effects, :apply runs
;;;; ENSURE only when the repo is absent, :remove runs REMOVE only when it
;;;; is present, and an unregistered method is a config error in every mode
;;;; (so `linacs check` catches a missing distro plugin before apply).

(in-package #:linacs-tests)

(def-suite executor-repository
  :in linacs-tests
  :description "Tests for the :repository executor")
(in-suite executor-repository)

(defun fixture-repo-action ()
  (list :action :repository :target "@wez/wezterm" :method :dnf-copr))

(def-test repository-action-identity ()
  "The :repository identity includes the :method qualifier plus the target,
so two packages needing the same repository collapse into one action."
  (is (equal (linacs.core:action-identity (fixture-repo-action))
             '(:repository :dnf-copr . "@wez/wezterm"))))

(defmacro with-fixture-method (&body body)
  "Register a controllable :fixture-method (PRESENT-P toggles a lexical
PRESENT variable; ENSURE/REMOVE bump counters) for the duration of BODY.
Uses REMHASH after, so it cannot leak into other suites. The flet names
are prefixed FIXTURE- to avoid shadowing CL:REMOVE/CL:ENSURE."
  `(let ((present nil) (ensure-count 0) (remove-count 0))
     (flet ((fixture-present-p (action) (declare (ignore action)) present)
            (fixture-ensure   (action) (declare (ignore action)) (incf ensure-count))
            (fixture-remove   (action) (declare (ignore action)) (incf remove-count)))
       (unwind-protect
            (progn
              (linacs.core:register-repository-method :fixture-method
                :present-p #'fixture-present-p
                :ensure    #'fixture-ensure
                :remove    #'fixture-remove)
              ,@body)
         (remhash :fixture-method linacs.core:*repository-methods*)))))

(def-test repository-check-reports-would-change ()
  "In :check mode the executor reports :would-change when the repository is
not yet configured, without running ENSURE."
  (with-fixture-method
    (let* ((action (list :action :repository :target "repo" :method :fixture-method))
           (result (linacs.core:execute-action action :mode :check)))
      (is (eq :would-change (getf result :status)))
      (is (zerop ensure-count))
      (is (zerop remove-count)))))

(def-test repository-check-reports-unchanged ()
  "In :check mode the executor reports :unchanged when the repository is
already configured."
  (with-fixture-method
    (setf present t)
    (let* ((action (list :action :repository :target "repo" :method :fixture-method))
           (result (linacs.core:execute-action action :mode :check)))
      (is (eq :unchanged (getf result :status)))
      (is (zerop ensure-count)))))

(def-test repository-apply-ensures-when-absent ()
  "In :apply mode the executor runs ENSURE and reports :changed when the
repository is absent."
  (with-fixture-method
    (let* ((action (list :action :repository :target "repo" :method :fixture-method))
           (result (linacs.core:execute-action action :mode :apply)))
      (is (eq :changed (getf result :status)))
      (is (= 1 ensure-count)))))

(def-test repository-apply-skips-when-present ()
  "In :apply mode the executor does not re-run ENSURE over an already
configured repository -- idempotency by construction."
  (with-fixture-method
    (setf present t)
    (let* ((action (list :action :repository :target "repo" :method :fixture-method))
           (result (linacs.core:execute-action action :mode :apply)))
      (is (eq :unchanged (getf result :status)))
      (is (zerop ensure-count)))))

(def-test repository-remove-runs-remove ()
  "In :remove mode the executor runs REMOVE and reports :removed."
  (with-fixture-method
    (setf present t)
    (let* ((action (list :action :repository :target "repo" :method :fixture-method))
           (result (linacs.core:execute-action action :mode :remove)))
      (is (eq :removed (getf result :status)))
      (is (= 1 remove-count)))))

(def-test repository-unregistered-method-is-config-error ()
  "An action whose :method has no registered implementation signals
EXECUTION-FAILURE in every mode -- the distro plugin that provides it was
not loaded, and `linacs check` must surface that before apply."
  (let* ((action (list :action :repository :target "@wez/wezterm" :method :dnf-copr)))
    (dolist (mode '(:check :apply :remove))
      (let ((signaled nil))
        (handler-case (linacs.core:execute-action action :mode mode)
          (linacs.core:execution-failure (e)
            (setf signaled e)))
        (is (typep signaled 'linacs.core:execution-failure)
            "unregistered method ~a should signal execution-failure, not return" mode)))))

(def-test repository-dedup-collapses-shared-repos ()
  "Two actions for the same method+target deduplicate to a single action
(the textbook PPA/COPR shared by several packages)."
  (let ((a (list :action :repository :target "@wez/wezterm" :method :dnf-copr))
        (b (list :action :repository :target "@wez/wezterm" :method :dnf-copr)))
    (is (= 1 (length (linacs.core:dedup-actions (list a b)))))))

(def-test repository-registered-as-action-type ()
  "The :repository action type is registered with its description, so
`linacs list` reports it."
  (is (not (null (linacs.core:find-executor :repository))))
  (let ((describe (symbol-function (find-symbol "ACTION-TYPE-DESCRIPTION"
                                                (find-package :linacs.core)))))
    (is (plusp (length (funcall describe :repository))))))