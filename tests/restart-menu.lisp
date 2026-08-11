(in-package #:linacs-tests)

(def-suite restart-menu
  :in linacs-tests
  :description "Tests for the interactive restart menu (compiled CLI)")
(in-suite restart-menu)

(defmacro with-menu-bindings ((&key input) &body body)
  "Bind the restart-menu controls: scripted *QUERY-IO* (INPUT), force menu
presentation, redirect menu output, and make the abort path throw a tag so
tests can observe it without killing the Lisp image. The *RESTART-MENU-P* and
*LINACS-ABORT-FUNCTION* bindings target linacs.core's specials directly."
  `(let ((*query-io* (make-string-input-stream ,input))
         (*standard-output* (make-string-output-stream))
         (linacs.core:*restart-menu-p* t)
         (linacs.core:*linacs-abort-function*
           (lambda () (throw 'test-abort :aborted))))
     ,@body))

(def-test menu-invokes-retry ()
  "Selecting 0 in the menu runs the RETRY restart's callback."
  (let ((attempts 0))
    (with-menu-bindings (:input (format nil "0~%"))
      (handler-case
          (handler-bind ((linacs.core:linacs-error
                          (lambda (c) (linacs.core:handle-linacs-error-interactively c))))
            (linacs.core:with-linacs-restarts
                (:on-retry (lambda () (incf attempts) :retried)
                 :on-skip (lambda () :skipped)
                 :on-abort (lambda () :aborted))
              (error 'linacs.core:action-conflict
                     :identity '(:copy-file . "~/.gitconfig")
                     :def-a "provider :git-defaults" :def-b "provider :dotfiles-extra")))
        (linacs.core:action-conflict (c) (declare (ignore c))
          (fail "handler-case must not see a condition the menu resolved"))))
    (is (= attempts 1))))

(def-test menu-invokes-skip ()
  "Selecting 1 in the menu runs the SKIP restart's callback."
  (let ((attempts 0))
    (with-menu-bindings (:input (format nil "1~%"))
      (handler-case
          (handler-bind ((linacs.core:linacs-error
                          (lambda (c) (linacs.core:handle-linacs-error-interactively c))))
            (linacs.core:with-linacs-restarts
                (:on-retry (lambda () (incf attempts) :retried)
                 :on-skip (lambda () :skipped)
                 :on-abort (lambda () :aborted))
              (error 'linacs.core:action-conflict
                     :identity '(:copy-file . "~/.gitconfig")
                     :def-a "a" :def-b "b")))
        (linacs.core:action-conflict (c) (declare (ignore c))
          (fail "handler-case must not see a condition the menu resolved"))))
    (is (zerop attempts))))

(def-test menu-invokes-abort-processing ()
  "Selecting 2 in the menu runs the ABORT-PROCESSING restart's callback."
  (let ((aborted nil))
    (with-menu-bindings (:input (format nil "2~%"))
      (catch 'test-abort
        (handler-bind ((linacs.core:linacs-error
                        (lambda (c) (linacs.core:handle-linacs-error-interactively c))))
          (linacs.core:with-linacs-restarts
              (:on-retry (lambda () :retried)
               :on-skip (lambda () :skipped)
               :on-abort (lambda () (setf aborted t) (throw 'test-abort :aborted)))
            (error 'linacs.core:action-conflict
                   :identity '(:copy-file . "~/.gitconfig")
                   :def-a "a" :def-b "b")))))
    (is-true aborted)))

(def-test menu-synthetic-abort-entry ()
  "The trailing synthetic [ABORT] entry calls *LINACS-ABORT-FUNCTION*."
  (let ((result
          (catch 'test-abort
            (with-menu-bindings (:input (format nil "3~%"))
              (handler-bind ((linacs.core:linacs-error
                              (lambda (c) (linacs.core:handle-linacs-error-interactively c))))
                (linacs.core:with-linacs-restarts
                    (:on-retry (lambda () :retried)
                     :on-skip (lambda () :skipped)
                     :on-abort (lambda () :aborted))
                  (error 'linacs.core:action-conflict
                         :identity '(:copy-file . "~/.gitconfig")
                         :def-a "a" :def-b "b")))
              :no-throw))))
    (is (eq result :aborted))))

(def-test menu-invalid-choice-loops ()
  "An out-of-range choice re-prompts rather than proceeding."
  (let ((attempts 0))
    (with-menu-bindings (:input (format nil "99~%0~%"))
      (handler-bind ((linacs.core:linacs-error
                      (lambda (c) (linacs.core:handle-linacs-error-interactively c))))
        (linacs.core:with-linacs-restarts
            (:on-retry (lambda () (incf attempts) :retried)
             :on-skip (lambda () :skipped)
             :on-abort (lambda () :aborted))
          (error 'linacs.core:action-conflict
                 :identity '(:copy-file . "~/.gitconfig")
                 :def-a "a" :def-b "b"))))
    (is (= attempts 1))))

(def-test menu-shows-condition-specific-restarts ()
  "For an ACTION-CONFLICT, USE-FIRST and USE-SECOND are offered and selectable."
  (let ((result
          (with-menu-bindings (:input (format nil "1~%"))
            (handler-bind ((linacs.core:linacs-error
                            (lambda (c) (linacs.core:handle-linacs-error-interactively c))))
              (restart-case
                  (error 'linacs.core:action-conflict
                         :identity '(:copy-file . "~/.gitconfig")
                         :def-a "a" :def-b "b")
                (linacs.core:use-first () :report "Keep definition A (the existing action)" :kept-a)
                (linacs.core:use-second () :report "Keep definition B (the new action)" :kept-b))))))
    (is (eq result :kept-b))))

(def-test non-interactive-falls-through-to-handler-case ()
  "Without an interactive terminal and with the menu forced off, the interactive
  handler returns normally and the enclosing HANDLER-CASE handles the condition
  exactly as it did before the menu existed."
  (let ((*query-io* (make-string-input-stream "not used"))
        (*standard-output* (make-string-output-stream))
        (linacs.core:*restart-menu-p* nil))
    (let ((caught nil))
      (handler-case
          (handler-bind ((linacs.core:linacs-error
                          (lambda (c) (linacs.core:handle-linacs-error-interactively c))))
            (linacs.core:with-linacs-restarts
                (:on-retry (lambda () :retried)
                 :on-skip (lambda () :skipped)
                 :on-abort (lambda () :aborted))
              (error 'linacs.core:action-conflict
                     :identity '(:copy-file . "~/.gitconfig")
                     :def-a "a" :def-b "b")))
        (linacs.core:action-conflict (c) (declare (ignore c)) (setf caught t)))
      (is-true caught))))

(def-test compute-linacs-restarts-filters-ambient-restarts ()
  "COMPUTE-LINACS-RESTARTS returns only LINACS's own restarts, filtering out
  ambient SBCL CONTINUE/EXIT and unrelated restarts."
  (restart-case
      (restart-case
          (linacs.core:with-linacs-restarts
              (:on-retry (lambda () :retried)
               :on-skip (lambda () :skipped)
               :on-abort (lambda () :aborted))
            (let ((names (mapcar #'restart-name (linacs.core:compute-linacs-restarts))))
              (is (equal names
                         (list 'linacs.core:retry
                               'linacs.core:skip
                               'linacs.core:abort-processing)))))
        (continue () nil)
        (exit () nil))
    (abort () nil)))

(def-test execute-action-retry-reruns-executor ()
  "Choosing RETRY in the menu re-runs a failed executor via EXECUTE-ACTION's
  real restart callback."
  (let ((calls 0))
    (linacs.core:register-action-type
     :test-flaky
     (lambda (action &key mode)
       (declare (ignore action mode))
       (incf calls)
       (if (= calls 1)
           (error 'linacs.core:execution-failure
                  :action-type :test-flaky :target "/tmp/flaky" :underlying "boom")
           (list :status :applied)))
     :description "Flaky test executor")
    (with-menu-bindings (:input (format nil "0~%"))
      (handler-bind ((linacs.core:linacs-error
                      (lambda (c) (linacs.core:handle-linacs-error-interactively c))))
        (linacs.core:execute-action '(:action :test-flaky :target "/tmp/flaky")
                                    :mode :apply))
      (is (= calls 2)))))

(def-test execute-action-skip-records-skipped ()
  "Choosing SKIP in the menu records the action as :SKIPPED and moves on."
  (let ((calls 0))
    (linacs.core:register-action-type
     :test-flaky2
     (lambda (action &key mode)
       (declare (ignore action mode))
       (incf calls)
       (error 'linacs.core:execution-failure
              :action-type :test-flaky2 :target "/tmp/flaky2" :underlying "boom"))
     :description "Always-failing test executor")
    (with-menu-bindings (:input (format nil "1~%"))
      (handler-bind ((linacs.core:linacs-error
                      (lambda (c) (linacs.core:handle-linacs-error-interactively c))))
        (linacs.core:execute-action '(:action :test-flaky2 :target "/tmp/flaky2")
                                    :mode :apply))
      (is (= calls 1))
      (is (eq (linacs.core:action-result-status '(:test-flaky2 . "/tmp/flaky2"))
              :skipped)))))
