(in-package #:linacs-tests)

(def-suite action-plan
  :in linacs-tests
  :description "ActionPlan objects (REFACTOR.org Action 5)")
(in-suite action-plan)

(defun make-plan-fixture ()
  "A plan with three actions, two of which share the same identity (the
duplicate :package action), plus live provenance/results tables."
  (linacs.core:make-action-plan
   :actions (list '(:action :copy-file :to "~/.a" :from "a")
                  '(:action :package :target :emacs :via :system)
                  '(:action :package :target :emacs :via :system))
   :provenance (make-hash-table :test 'equal)
   :results (make-hash-table :test 'equal)))

(def-test make-action-plan-basics ()
  "MAKE-ACTION-PLAN carries the action list and tables it was given."
  (let ((plan (make-plan-fixture)))
    (is (typep plan 'linacs.core:action-plan))
    (is (= 3 (length (linacs.core:plan-actions plan))))
    (is (typep (linacs.core:plan-provenance plan) 'hash-table))
    (is (typep (linacs.core:plan-results plan) 'hash-table))))

(def-test action-by-identity-finds-actions ()
  "ACTION-BY-IDENTITY matches on the canonical identity, falling back to
the (type . target) default for types without a registered identity fn."
  (let ((plan (make-plan-fixture)))
    (is (equal (linacs.core:action-by-identity plan '(:copy-file . "~/.a"))
               '(:action :copy-file :to "~/.a" :from "a")))
    (is (null (linacs.core:action-by-identity plan '(:copy-file . "~/.nope"))))))

(def-test add-action-prepends ()
  "ADD-ACTION pushes onto the plan's action list and returns the action."
  (let* ((plan (linacs.core:make-action-plan :actions nil))
         (added (linacs.core:add-action '(:action :x :target "t") plan)))
    (is (eq added '(:action :x :target "t")))
    (is (= 1 (length (linacs.core:plan-actions plan))))
    (is (equal (first (linacs.core:plan-actions plan)) '(:action :x :target "t")))))

(def-test deduplicate-plan-returns-deduped-copy ()
  "DEDUPLICATE-PLAN runs the action list through DEDUP-ACTIONS (the two
identical :package actions collapse) without mutating the original plan."
  (let* ((plan (make-plan-fixture))
         (deduped (linacs.core:deduplicate-plan plan)))
    (is (= 2 (length (linacs.core:plan-actions deduped)))
        "the duplicate :package action was dropped")
    (is (= 3 (length (linacs.core:plan-actions plan)))
        "the original plan is untouched (pure operation)")))

(def-test order-plan-returns-ordered-copy ()
  "ORDER-PLAN topologically sorts the action list over :depends-on edges,
putting the dependency first."
  (let* ((plan (linacs.core:make-action-plan
                :actions (list '(:action :copy-file :to "~/.zshrc" :from "zshrc"
                                        :depends-on ((:copy-file . "~/.zshenv")))
                               '(:action :copy-file :to "~/.zshenv" :from "zshenv"))))
         (ordered (linacs.core:order-plan plan)))
    (is (= 2 (length (linacs.core:plan-actions ordered))))
    (is (equal (getf (first (linacs.core:plan-actions ordered)) :to) "~/.zshenv")
        "the dependency is ordered before its dependent")
    (is (= 2 (length (linacs.core:plan-actions plan)))
        "the original plan is untouched (pure operation)")))

(def-test plan-status-reads-results-table ()
  "PLAN-STATUS / PLAN-RESULT read the ACTION-RESULT recorded for an
identity out of the plan's results table."
  (let* ((results (make-hash-table :test 'equal))
         (plan (linacs.core:make-action-plan
                :actions (list '(:action :copy-file :to "~/.a" :from "a"))
                :results results)))
    (setf (gethash '(:copy-file . "~/.a") results)
          (linacs.core:make-action-result :status :applied))
    (is (eq (linacs.core:plan-status plan '(:copy-file . "~/.a")) :applied))
    (is (typep (linacs.core:plan-result plan '(:copy-file . "~/.a"))
               'linacs.core:action-result))
    (is (null (linacs.core:plan-status plan '(:copy-file . "~/.b"))))))