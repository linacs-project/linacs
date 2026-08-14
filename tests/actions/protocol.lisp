(in-package #:linacs-tests)

(def-suite action-protocol
  :in linacs-tests
  :description "Tests for the generic action protocol (REFACTOR.org Action 3):
execute-action as a generic, action-description, action-dedup-behavior, the
state generics, and the unified status vocabulary")

(in-suite action-protocol)

(defun copy-file-fixture (dst content)
  "A copy-file action with inline :content (no asset-root dependency)."
  (list :action :copy-file :target dst :content content))

(def-test execute-action-accepts-object-and-plist ()
  "EXECUTE-ACTION as a generic: an ACTION instance and its plist must
dispatch to the same executor and return the same :check result."
  (with-scratch-dir (dir)
    (let* ((dst (namestring (merge-pathnames "dst.txt" dir)))
           (plist (copy-file-fixture dst "content"))
           (obj (linacs.core:make-action plist)))
      (let ((from-list (linacs.core:execute-action plist :mode :check))
            (from-obj (linacs.core:execute-action obj :mode :check)))
        (is (eq (getf from-list :status) :would-change))
        (is (equal from-list from-obj)
            "object dispatch must match plist dispatch, list=~s obj=~s"
            from-list from-obj)))))

(def-test action-description-plist-and-object ()
  "ACTION-DESCRIPTION delegates to the registered type description and
works on both plists and ACTION instances."
  (let ((desc "Copy or render a file to a target path"))
    (is (string= (linacs.core:action-description '(:action :copy-file :target "/tmp/x"))
                 desc))
    (is (string= (linacs.core:action-description
                  (linacs.core:make-action '(:action :copy-file :target "/tmp/x")))
                 desc)))
  (is (string= (linacs.core:action-description '(:action :no-such-type :target "x"))
               "")
      "types with no registered description report the empty string"))

(def-test action-dedup-behavior-plist-and-object ()
  "ACTION-DEDUP-BEHAVIOR delegates to *ACTION-TYPE-DEDUP-BEHAVIOR*: :additive
for :config-lines, :conflict by default, on both plists and instances."
  (is (eq (linacs.core:action-dedup-behavior '(:action :config-lines :target "/tmp/x"))
          :additive))
  (is (eq (linacs.core:action-dedup-behavior
           (linacs.core:make-action '(:action :config-lines :target "/tmp/x")))
          :additive))
  (is (eq (linacs.core:action-dedup-behavior '(:action :copy-file :target "/tmp/x"))
          :conflict)))

(def-test dedup-actions-accepts-instances ()
  "DEDUP-ACTIONS must work on ACTION instances after the generic swap:
same-identity :config-lines instances (additive) both survive."
  (let ((a (linacs.core:make-action '(:action :config-lines :target "/tmp/cfg"
                                              :ensure ("x = 1"))))
        (b (linacs.core:make-action '(:action :config-lines :target "/tmp/cfg"
                                              :ensure ("y = 2")))))
    (is (= (length (linacs.core:dedup-actions (list a b))) 2))))

(def-test current-state-default-is-nil ()
  "CURRENT-STATE defaults to NIL -- today's executors conflate probing and
applying, so there is no separate probe to report."
  (is (null (linacs.core:current-state '(:action :copy-file :target "/tmp/x"))))
  (is (null (linacs.core:current-state
             (linacs.core:make-action '(:action :copy-file :target "/tmp/x"))))))

(def-test desired-state-returns-plist ()
  "DESIRED-STATE defaults to the action's own plist -- the declared intent
IS the desired state today."
  (let ((plist '(:action :copy-file :target "/tmp/x" :content "hi")))
    (is (equal (linacs.core:desired-state plist) plist))
    (is (equal (linacs.core:desired-state (linacs.core:make-action plist))
               (linacs.core:action->plist (linacs.core:make-action plist))))))

(def-test diff-state-delegates-to-check ()
  "DIFF-STATE default delegates to the executor in :check mode, reporting
what WOULD change. Works on plists and instances alike."
  (with-scratch-dir (dir)
    (let* ((dst (namestring (merge-pathnames "dst.txt" dir)))
           (plist (copy-file-fixture dst "content"))
           (obj (linacs.core:make-action plist)))
      (is (eq (getf (linacs.core:diff-state plist) :status) :would-change))
      (is (eq (getf (linacs.core:diff-state obj) :status) :would-change)))))

(def-test apply-state-canonicalizes-status ()
  "APPLY-STATE default delegates to the executor in :apply mode and
canonicalizes the reported status to the execution spelling: :changed ->
:applied on first apply, :unchanged -> :already-met when already satisfied."
  (with-scratch-dir (dir)
    (let* ((dst (namestring (merge-pathnames "dst.txt" dir)))
           (plist (copy-file-fixture dst "content")))
      (is (eq (getf (linacs.core:apply-state plist) :status) :applied)
          "first apply of a missing target should canonicalize to :applied")
      (is (eq (getf (linacs.core:apply-state plist) :status) :already-met)
          "second apply (already matching) should canonicalize to :already-met"))))

(def-test remove-state-delegates-to-remove-mode ()
  "REMOVE-STATE default delegates to the executor in :remove mode and
reports :removed."
  (with-scratch-dir (dir)
    (let* ((dst (namestring (merge-pathnames "dst.txt" dir)))
           (plist (copy-file-fixture dst "content")))
      (linacs.core:apply-state plist)
      (is (probe-file dst) "fixture file should exist before removal")
      (is (eq (getf (linacs.core:remove-state plist) :status) :removed))
      (is (null (probe-file dst)) "fixture file should be gone after removal"))))

(def-test executor-status-mapping ()
  "EXECUTOR-STATUS unifies the two status families: :check passes executor
statuses through verbatim; :apply translates change-detection spellings to
execution spellings."
  (dolist (s '(:would-change :unchanged :changed :removed :missing))
    (is (eq (linacs.core:executor-status s :mode :check) s)
        ":check must pass ~s through unchanged" s))
  (is (eq (linacs.core:executor-status :would-change :mode :apply) :applied))
  (is (eq (linacs.core:executor-status :unchanged :mode :apply) :already-met))
  (is (eq (linacs.core:executor-status :changed :mode :apply) :applied))
  (is (eq (linacs.core:executor-status :removed :mode :apply) :removed))
  (is (eq (linacs.core:executor-status nil :mode :apply) :applied)
      "an executor that reports no status becomes :applied"))

(def-test action-statuses-covers-both-families ()
  "The canonical *ACTION-STATUSES* vocabulary includes both the
change-detection family and the execution/pipeline family."
  (is (subsetp '(:would-change :unchanged :changed :removed :missing
                 :applied :already-met :failed :skipped)
               linacs.core:*action-statuses*)))