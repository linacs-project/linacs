(in-package #:linacs-tests)

(def-suite execution-events
  :in linacs-tests
  :description "Structured execution events (REFACTOR.org Thought 8)")
(in-suite execution-events)

(defun make-event-stub-reporter ()
  "Return a function that records every (action phase &optional data) call,
plus a zero-argument accessor returning the recorded calls. The accessor is
a closure over the same binding the reporter pushes into, so it always sees
the latest contents."
  (let ((calls '()))
    (values (lambda (action phase &optional data)
              (push (list :action action :phase phase :data data) calls))
            (lambda () calls))))

(defun install-event-probe (class probe)
  "Temporarily install PROBE as the REPORT-EVENT method for an event of
CLASS, returning the method object for cleanup via REMOVE-METHOD. Replaces
the default no-op / legacy-adapter method only for the duration of a test.
The SBCL 'redefining' warning from REPLACING the method is muffled."
  (handler-bind ((warning #'muffle-warning))
    (eval `(defmethod linacs.core:report-event ((e ,class)) (funcall ,probe e)))))

(def-test event-constructors-expose-stage-and-payload ()
  "Every event kind carries its own :stage keyword and the payload slots
its name promises."
  (let ((ev (linacs.core:make-action-started :action '(:action :x :target "t"))))
    (is (eq (linacs.core:event-stage ev) :action-started))
    (is (equal (linacs.core:event-action ev) '(:action :x :target "t"))))

  (let ((ev (linacs.core:make-action-completed :action '(:action :x :target "t")
                                               :result (list :status :applied))))
    (is (eq (linacs.core:event-stage ev) :action-completed))
    (is (equal (linacs.core:event-action ev) '(:action :x :target "t")))
    (is (equal (linacs.core:event-result ev) '(:status :applied))))

  (let ((ev (linacs.core:make-action-skipped :action '(:action :x :target "t"))))
    (is (eq (linacs.core:event-stage ev) :action-skipped))
    (is (equal (linacs.core:event-action ev) '(:action :x :target "t"))))

  (handler-case
      (let* ((err (make-condition 'linacs.core:execution-failure
                                  :action-type :x :target "t" :underlying "boom"))
             (ev (linacs.core:make-action-failed :action '(:action :x :target "t")
                                                 :error err)))
        (is (eq (linacs.core:event-stage ev) :action-failed))
        (is (eq (linacs.core:event-error ev) err)))
    (error (e) (fail "could not construct action-failed event: ~a" e)))

  (let ((plan (linacs.core:make-action-plan :actions nil
                                            :provenance (make-hash-table)
                                            :results (make-hash-table))))
    (let ((ev (linacs.core:make-plan-started :plan plan)))
      (is (eq (linacs.core:event-stage ev) :plan-started))
      (is (eq (linacs.core:event-plan ev) plan)))
    (let ((ev (linacs.core:make-plan-completed :plan plan)))
      (is (eq (linacs.core:event-stage ev) :plan-completed))
      (is (eq (linacs.core:event-plan ev) plan))))

  (let ((ev (linacs.core:make-feature-resolved :feature :editor :provider :emacs)))
    (is (eq (linacs.core:event-stage ev) :feature-resolved))
    (is (eq (linacs.core:event-feature ev) :editor))
    (is (eq (linacs.core:event-provider ev) :emacs)))

  (let ((ev (linacs.core:make-action-output :action '(:action :x :target "t")
                                            :stream :stdout :line "hello")))
    (is (eq (linacs.core:event-stage ev) :action-output))
    (is (eq (linacs.core:event-stream ev) :stdout))
    (is (string= (linacs.core:event-line ev) "hello"))))

(defun register-events-probe ()
  "Register a trivial executor that returns :applied, for the legacy
adapter tests below."
  (linacs.core:register-action-type
   :events-probe
   (lambda (action &key mode)
     (declare (ignore action))
     (list :status (case mode (:check :unchanged) (otherwise :applied))))))

(def-test action-started-and-completed-reach-legacy-reporter ()
  "REPORT-EVENT translates the action lifecycle back into the historic
(action phase &optional data) contract: EXECUTE-ACTION emits :BEFORE then
:AFTER (with the result plist) to *PROGRESS-REPORTER* when bound."
  (reset-project-registries)
  (register-events-probe)
  (clrhash linacs.core:*action-results*)
  (multiple-value-bind (reporter calls)
      (make-event-stub-reporter)
    (let ((linacs.core::*progress-reporter* reporter))
      (linacs.core:execute-action '(:action :events-probe :target "internal")
                                  :mode :apply))
    (let ((calls (funcall calls)))
      (is (= (length calls) 2))
      (destructuring-bind (completed started) calls
        (is (eq (getf started :phase) :before))
        (is (equal (getf started :action) '(:action :events-probe :target "internal")))
        (is (eq (getf completed :phase) :after))
        (is (eq (getf (getf completed :data) :status) :applied))))))

(def-test action-failed-reaches-legacy-reporter ()
  "A failing executor emits :FAILED to *PROGRESS-REPORTER* with the
condition as DATA (in addition to recording a :failed result)."
  (reset-project-registries)
  (linacs.core:register-action-type
   :always-fail-events-probe
   (lambda (action &key mode)
     (declare (ignore action mode))
     (error 'linacs.core:execution-failure :action-type :always-fail-events-probe
            :target "/tmp/ev" :underlying "boom"))
   :description "always-failing test executor")
  (clrhash linacs.core:*action-results*)
  (multiple-value-bind (reporter calls)
      (make-event-stub-reporter)
    (let ((linacs.core::*progress-reporter* reporter))
      (handler-case
          (linacs.core:execute-action '(:action :always-fail-events-probe :target "/tmp/ev")
                                      :mode :apply)
        (linacs.core:linacs-error () nil)))
    (let ((calls (funcall calls)))
      (let ((failed (find :failed calls :key (lambda (c) (getf c :phase)))))
        (is (not (null failed)) "the reporter should have received a :failed call")
        (is (typep (getf failed :data) 'linacs.core:linacs-error))))))

(def-test action-skipped-reaches-legacy-reporter ()
  "REPORT-EVENT on an ACTION-SKIPPED event forwards :SKIPPED to
*PROGRESS-REPORTER*."
  (multiple-value-bind (reporter calls)
      (make-event-stub-reporter)
    (let ((linacs.core::*progress-reporter* reporter))
      (linacs.core:report-event
       (linacs.core:make-action-skipped :action '(:action :x :target "t"))))
    (let ((calls (funcall calls)))
      (is (eq (getf (first calls) :phase) :skipped))
      (is (equal (getf (first calls) :action) '(:action :x :target "t"))))))

(def-test events-without-legacy-phase-are-dropped ()
  "Events with no historic phase (plan-started, feature-resolved,
plan-completed, action-output) never reach *PROGRESS-REPORTER* during this
migration -- the structured stream is additive, the legacy contract is
byte-identical."
  (multiple-value-bind (reporter calls)
      (make-event-stub-reporter)
    (let ((linacs.core::*progress-reporter* reporter))
      (linacs.core:report-event
       (linacs.core:make-plan-started :plan nil))
      (linacs.core:report-event
       (linacs.core:make-feature-resolved :feature :editor :provider :emacs))
      (linacs.core:report-event
       (linacs.core:make-plan-completed :plan nil))
      (linacs.core:report-event
       (linacs.core:make-action-output :action nil :stream :stdout :line "x")))
    (is (null (funcall calls))
        "no legacy-reporter call should be made for these events")))

(def-test current-action-is-bound-during-execution ()
  "EXECUTE-ACTION binds *CURRENT-ACTION* for the duration of an executor
call, so the subprocess capture path can tag ACTION-OUTPUT events with the
action that produced them."
  (reset-project-registries)
  (let ((seen nil))
    (linacs.core:register-action-type
     :current-action-probe
     (lambda (action &key mode)
       (declare (ignore action mode))
       (setf seen linacs.core::*current-action*)
       (list :status :applied)))
    (clrhash linacs.core:*action-results*)
    (linacs.core:execute-action '(:action :current-action-probe :target "ctx")
                                :mode :apply)
    (is (equal seen '(:action :current-action-probe :target "ctx")))))

(def-test feature-resolved-emitted-during-collection ()
  "collect-actions-from-features emits one FEATURE-RESOLVED event per
feature, carrying the feature and the provider actually selected."
  (reset-project-registries)
  (linacs.core:define-provider :events-provider :for :events-feature
    (lambda (facts)
      (declare (ignore facts))
      (list (list :action :ensure-dir :target "/tmp/events-out"))))
  (linacs.core:define-feature :events-feature)
  (let ((seen nil))
    (labels ((record (e) (push (list (linacs.core:event-feature e)
                                     (linacs.core:event-provider e))
                               seen)))
      (let ((method (install-event-probe 'linacs.core:feature-resolved #'record)))
        (unwind-protect
             (linacs.core::collect-actions-from-features
              (list (list :feature :events-feature)))
          (remove-method #'linacs.core:report-event method))))
    (is (equal seen '((:events-feature :events-provider))))))

(def-test plan-started-and-completed-emitted-by-run-pipeline ()
  "run-pipeline emits PLAN-STARTED before execution and PLAN-COMPLETED
after it, both carrying the run's ACTION-PLAN."
  (reset-project-registries)
  (let ((*current-home-thunk*
          (lambda ()
            (setf *current-home-name* :events-home)
            (setf *current-home-actions* nil)
            (list :name :events-home :traits nil
                  :use-features nil :actions nil)))
        (plan-started-seen nil)
        (plan-completed-seen nil))
    (labels ((record-started (e) (setf plan-started-seen (linacs.core:event-plan e)))
             (record-completed (e) (setf plan-completed-seen (linacs.core:event-plan e))))
      (let ((ms (install-event-probe 'linacs.core:plan-started #'record-started))
            (mc (install-event-probe 'linacs.core:plan-completed #'record-completed)))
        (unwind-protect
             (run-pipeline :execute-mode :plan-only)
          (remove-method #'linacs.core:report-event ms)
          (remove-method #'linacs.core:report-event mc))))
    (is (not (null plan-started-seen)) "plan-started event should have been emitted")
    (is (eq plan-completed-seen plan-started-seen)
        "plan-started and plan-completed should carry the same action-plan")))

(def-test action-output-event-carrying-data ()
  "A constructed ACTION-OUTPUT event carries its action, stream keyword,
and line, even when the action is NIL (direct capture outside an executor)."
  (let ((ev (linacs.core:make-action-output :action nil :stream :stderr :line "warn")))
    (is (eq (linacs.core:event-stream ev) :stderr))
    (is (string= (linacs.core:event-line ev) "warn"))
    (is (null (linacs.core:event-action ev)))))