(in-package #:linacs-tests)

(def-suite action-result
  :in linacs-tests
  :description "ActionResult objects (REFACTOR.org Action 5)")
(in-suite action-result)

(defun register-result-probe ()
  "Register a trivial executor that reports a plain status, so tests can
assert EXECUTE-ACTION stores an ACTION-RESULT object rather than a plist."
  (linacs.core:register-action-type
   :result-probe
   (lambda (action &key mode)
     (declare (ignore action))
     (list :status (case mode (:check :unchanged) (otherwise :applied))))))

(def-test make-action-result-basics ()
  "MAKE-ACTION-RESULT constructs an ACTION-RESULT with the expected slots."
  (let ((r (linacs.core:make-action-result :action '(:action :x :target "t")
                                            :status :applied)))
    (is (typep r 'linacs.core:action-result))
    (is (eq (linacs.core:result-status r) :applied))
    (is (null (linacs.core:result-error r)))
    (is (eq (linacs.core:result-mode r) :apply))))

(def-test result-status-accepts-plists-and-nil ()
  "RESULT-STATUS reads the :status keyword off an ACTION-RESULT, a historic
plist, or NIL -- so mixed call sites keep working during migration."
  (is (eq (linacs.core:result-status '(:status :unchanged)) :unchanged))
  (is (null (linacs.core:result-status nil)))
  (is (null (linacs.core:result-status "not-a-result"))))

(def-test result-plist-round-trip ()
  "RESULT->PLIST then PLIST->RESULT preserves the status, error, and mode."
  (let* ((orig (linacs.core:make-action-result :action '(:action :x :target "t")
                                               :status :failed :error 'boom
                                               :mode :remove))
         (back (linacs.core:plist->result (linacs.core:result->plist orig))))
    (is (eq (linacs.core:result-status back) :failed))
    (is (eq (linacs.core:result-error back) 'boom))
    (is (eq (linacs.core:result-mode back) :remove))
    (is (equal (linacs.core:result-action back) '(:action :x :target "t")))))

(def-test execute-action-records-action-result-object ()
  "EXECUTE-ACTION in :apply mode stores an ACTION-RESULT (not a plist) in
the results table, carrying the executor's status."
  (reset-project-registries)
  (register-result-probe)
  (clrhash linacs.core:*action-results*)
  (let ((result (linacs.core:execute-action '(:action :result-probe :target "x")
                                            :mode :apply)))
    (is (eq (getf result :status) :applied))
    (let ((recorded (gethash '(:result-probe . "x") linacs.core:*action-results*)))
      (is (typep recorded 'linacs.core:action-result)
          "the results table stores an ACTION-RESULT, not a plist")
      (is (eq (linacs.core:result-status recorded) :applied)))))

(def-test failed-execution-records-failed-action-result ()
  "A failing executor records an ACTION-RESULT with :failed status and the
condition object as its error (as read back via ACTION-RESULT-STATUS)."
  (reset-project-registries)
  (linacs.core:register-action-type
   :always-fail-result-probe
   (lambda (action &key mode)
     (declare (ignore action mode))
     (error 'linacs.core:execution-failure :action-type :always-fail-result-probe
            :target "/tmp/x" :underlying "boom"))
   :description "always-failing test executor")
  (clrhash linacs.core:*action-results*)
  (handler-case
      (linacs.core:execute-action '(:action :always-fail-result-probe :target "/tmp/x")
                                  :mode :apply)
    (linacs.core:linacs-error () nil))
  (let ((recorded (gethash '(:always-fail-result-probe . "/tmp/x")
                           linacs.core:*action-results*)))
    (is (typep recorded 'linacs.core:action-result))
    (is (eq (linacs.core:result-status recorded) :failed))
    (is (typep (linacs.core:result-error recorded) 'linacs.core:linacs-error))
    (is (eq (linacs.core:action-result-status '(:always-fail-result-probe . "/tmp/x"))
            :failed))))

(def-test skipped-action-records-skipped-action-result ()
  "The SKIP restart on a failing executor records an ACTION-RESULT with
:skipped status."
  (reset-project-registries)
  (linacs.core:register-action-type
   :always-fail-skip-probe
   (lambda (action &key mode)
     (declare (ignore action mode))
     (error 'linacs.core:execution-failure :action-type :always-fail-skip-probe
            :target "/tmp/skip" :underlying "boom"))
   :description "always-failing test executor")
  (clrhash linacs.core:*action-results*)
  (handler-bind ((linacs.core:linacs-error
                  (lambda (c) (declare (ignore c)) (invoke-restart 'linacs.core:skip))))
    (linacs.core:execute-action '(:action :always-fail-skip-probe :target "/tmp/skip")
                                :mode :apply))
  (let ((recorded (gethash '(:always-fail-skip-probe . "/tmp/skip")
                           linacs.core:*action-results*)))
    (is (typep recorded 'linacs.core:action-result))
    (is (eq (linacs.core:result-status recorded) :skipped))))
