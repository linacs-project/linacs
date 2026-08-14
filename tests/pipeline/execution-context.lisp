(in-package #:linacs-tests)

(def-suite pipeline-execution-context
  :in linacs-tests
  :description "Execution-context isolation (REFACTOR.org Action 4)")
(in-suite pipeline-execution-context)

(defun register-execution-context-probe ()
  "Register a trivial executor that reports a status and echoes back the
facts and roots it observed, so tests can assert the execution context's
state reached the executor call."
  (linacs.core:register-action-type
   :execution-context-probe
   (lambda (action &key mode)
     (declare (ignore action))
     (list :status (case mode (:check :unchanged) (otherwise :applied))
           :facts-seen (copy-list (linacs.core:context-facts))
           :os-seen (linacs.core:fact :os)
           :project-root-seen (linacs.core:context-project-root)
           :asset-root-seen (linacs.core:context-asset-root)))))

(def-test make-execution-context-keeps-supplied-slots ()
  "MAKE-EXECUTION-CONTEXT honors explicitly supplied slots."
  (let* ((res (make-hash-table :test 'equal))
         (ctx (linacs.core:make-execution-context
               :facts '(:os :testos)
               :results res
               :project-root "/prj"
               :asset-root (pathname "/asset/"))))
    (is (equal (linacs.core:execution-context-facts ctx) '(:os :testos)))
    (is (eq (linacs.core:execution-context-results ctx) res))
    (is (equal (linacs.core:execution-context-project-root ctx) "/prj"))
    (is (equal (namestring (linacs.core:execution-context-asset-root ctx))
               "/asset/"))))

(def-test execute-action-with-context-isolates-results ()
  "EXECUTE-ACTION given a context writes results into the context's table
and leaves the global *ACTION-RESULTS* untouched."
  (reset-project-registries)
  (register-execution-context-probe)
  (clrhash linacs.core:*action-results*)
  (let* ((ctx-results (make-hash-table :test 'equal))
         (ctx (linacs.core:make-execution-context :results ctx-results)))
    (linacs.core:execute-action '(:action :execution-context-probe :target "x")
                                :mode :apply :context ctx)
    (is (= 1 (hash-table-count ctx-results))
        "the context's results table received the action result")
    (is (= 0 (hash-table-count linacs.core:*action-results*))
        "the global results table was not written")))

(def-test execute-action-without-context-keeps-legacy-global-behavior ()
  "Without a context, EXECUTE-ACTION writes into the global
*ACTION-RESULTS* exactly as historically."
  (reset-project-registries)
  (register-execution-context-probe)
  (clrhash linacs.core:*action-results*)
  (linacs.core:execute-action '(:action :execution-context-probe :target "x")
                              :mode :apply)
  (is (= 1 (hash-table-count linacs.core:*action-results*))
      "without a context, results go to the global table (historic behavior)"))

(def-test execute-action-context-facts-and-roots-reach-executor ()
  "Facts, project root, and asset root seeded in a context are what the
executor observes (via FACT and the CONTEXT-* combinators), and the
global *FACTS* stays untouched."
  (reset-project-registries)
  (register-execution-context-probe)
  (clrhash linacs.core:*action-results*)
  (let ((result (linacs.core:execute-action
                 '(:action :execution-context-probe :target "x")
                 :mode :check
                 :context (linacs.core:make-execution-context
                           :facts '(:os :testos :laptop-p t)
                           :project-root "/some/project"
                           :asset-root (pathname "/some/asset/")))))
    (is (eq (getf result :status) :unchanged))
    (is (eq (getf (getf result :facts-seen) :os) :testos)
        "executor observed the context's facts")
    (is (eq (getf result :os-seen) :testos)
        "FACT reads the context's facts inside an executor call")
    (is (equal (getf result :project-root-seen) "/some/project")
        "executor observed the context's project root")
    (is (equal (namestring (getf result :asset-root-seen)) "/some/asset/")
        "executor observed the context's asset root"))
  (is (null linacs.core:*facts*)
      "the context run left the global *FACTS* untouched"))

(def-test execute-plan-with-context-isolates-results ()
  "EXECUTE-PLAN given a context records every action's result into the
context's results table and leaves the global *ACTION-RESULTS* untouched."
  (reset-project-registries)
  (register-execution-context-probe)
  (clrhash linacs.core:*action-results*)
  (let* ((ctx-results (make-hash-table :test 'equal))
         (ctx (linacs.core:make-execution-context :results ctx-results))
         (home '(:traits nil))
         (plan (list '(:action :execution-context-probe :target "a")
                     '(:action :execution-context-probe :target "b"))))
    (linacs.core:execute-plan plan home :mode :apply :context ctx)
    (is (= 2 (hash-table-count ctx-results))
        "EXECUTE-PLAN recorded both actions into the context's table")
    (is (= 0 (hash-table-count linacs.core:*action-results*))
        "EXECUTE-PLAN left the global results table untouched")))

(def-test with-execution-context-nil-is-a-no-op ()
  "WITH-EXECUTION-CONTEXT with a NIL context is a no-op: dynamic bindings
and *EXECUTION-CONTEXT* are left exactly as they were."
  (reset-project-registries)
  (let ((linacs.core:*facts* (list :marker t)))
    (linacs.core:with-execution-context nil
      (is (eq (linacs.core:fact :marker) t)
          "inside a NIL-context block the dynamic *FACTS* still apply")
      (is (null linacs.core:*execution-context*)
          "*EXECUTION-CONTEXT* stays NIL"))
    (is (eq (getf linacs.core:*facts* :marker) t)
        "the outer dynamic *FACTS* is untouched after the block")))