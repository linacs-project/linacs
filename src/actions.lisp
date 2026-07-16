;;;; src/actions.lisp
;;;;
;;;; Action identity, deduplication, topological ordering, and dispatch. An
;;;; action is a plist (:action <type> :target <t> ...opts); every type has
;;;; exactly one built-in executor (see action-types/) responsible for
;;;; probing and correcting real system state in a single idempotent step --
;;;; there's no separate "current state" model kept anywhere to diff against.
;;;;
;;;; Usage:
;;;;   Executing one action directly (mainly useful for debugging or testing an
;;;;   executor in isolation -- see docs/how-to-debug.md):
;;;;
;;;;     (execute-action '(:action :copy-file :target "/tmp/x" :from "x") :mode :check)

(in-package :linacs.core)

(defvar *action-types* (make-hash-table :test 'eq)
  "Maps action type keyword -> executor function of (action &key mode).")

(defvar *action-type-descriptions* (make-hash-table :test 'eq)
  "Maps action type keyword -> a one-line human-readable description, for
`linacs list` and similar reporting. Purely documentation; never consulted
by resolution or execution.")

(defun register-action-type (type executor-fn &key description)
  (setf (gethash type *action-types*) executor-fn)
  (when description (setf (gethash type *action-type-descriptions*) description)))

(defun action-type-description (type)
  (or (gethash type *action-type-descriptions*) ""))

(defun find-executor (type)
  (or (gethash type *action-types*)
      (error 'execution-failure :action-type type :target nil
             :underlying (format nil "No executor registered for action type ~a" type))))

(defun action-type (action) (getf action :action))
(defun action-target (action) (or (getf action :target) (getf action :to)))

(defun action-identity (action)
  "Compute the canonical identity for ACTION: a 2-element (type . target)
cons for most types, or a qualified identity for types whose mechanism or
content matters beyond the bare target:
  - :package        (:package via . target) -- :via :system and :via :pip
                     installs of the same name are different actions.
  - :config-lines    qualified by its :ensure/:remove content, so multiple
                     :config-lines actions against the same file are
                     additive rather than conflicting.
  - :authorized-key  qualified by the key material, so multiple keys for
                     the same user don't collide.
  - :firewall        qualified by :protocol, so the same port number can
                     have independent tcp and udp rules."
  (let ((type (action-type action)))
    (cond
      ((eq type :package)
       (list* :package (getf action :via) (getf action :target)))
      ((eq type :config-lines)
       (list :config-lines
             (list (cons :ensure (getf action :ensure))
                   (cons :remove (getf action :remove)))
             (action-target action)))
      ((eq type :authorized-key)
       (list :authorized-key (action-target action) (getf action :key)))
      ((eq type :firewall)
       (list* :firewall (getf action :protocol "tcp") (action-target action)))
      (t (cons type (action-target action))))))

(defun action-source-label (action)
  "Human-readable label of where ACTION came from, for conflict reports."
  (or (getf action :source) "unspecified"))

(defun same-action-content-p (a b)
  "Two actions are content-equal if their plists are EQUAL once :source,
:priority, and identity-irrelevant bookkeeping keys are stripped."
  (flet ((strip (a) (let ((c (copy-list a)))
                       (remf c :source)
                       (remf c :priority)
                       c)))
    (equal (strip a) (strip b))))

(defun dedup-actions (actions)
  "Deduplicate ACTIONS by identity. :priority :user (highest) beats
:priority :provider. :force t wins any tie regardless of priority. Two
actions of the same priority with the same identity but different content
signal ACTION-CONFLICT. For :config-lines, duplicates at the same priority
only warn and both survive (they're additive by identity construction, so
true duplicates here mean literally identical ensure/remove sets)."
  (let ((by-identity (make-hash-table :test 'equal))
        (result '()))
    (dolist (action actions)
      (let* ((id (action-identity action))
             (existing (gethash id by-identity)))
        (cond
          ((null existing)
           (setf (gethash id by-identity) action)
           (push action result))
          ((getf action :force)
           (setf result (substitute action existing result))
           (setf (gethash id by-identity) action))
          ((getf existing :force)
           nil) ; existing already forced; keep it, drop new
          ((same-action-content-p action existing)
           nil) ; identical, drop the duplicate silently
          ((eq (action-type action) :config-lines)
           (linacs.log:warn* "Duplicate :config-lines identity for ~a; keeping first, continuing."
                             (action-target action)))
          (t
           (let ((pa (or (getf action :priority) :provider))
                 (pe (or (getf existing :priority) :provider)))
             (cond
               ((and (eq pa :user) (eq pe :provider))
                (setf result (substitute action existing result))
                (setf (gethash id by-identity) action))
               ((and (eq pa :provider) (eq pe :user))
                nil) ; existing user-level def wins, drop provider action
               (t
                (restart-case
                    (error 'action-conflict :identity id
                           :def-a (action-source-label existing)
                           :def-b (action-source-label action))
                  (use-first () :report "Keep definition A (the existing action)"
                             nil) ; existing is already in result/by-identity; nothing to do
                  (use-second () :report "Keep definition B (the new action)"
                              (setf result (substitute action existing result))
                              (setf (gethash id by-identity) action))))))))))
    (nreverse result)))

(defun order-actions (actions)
  "Topologically order ACTIONS using explicit :depends-on identity edges,
refining declaration order. Signals DEPENDENCY-CYCLE on cycles and simply
ignores :depends-on edges that reference an identity not present in ACTIONS
(a missing dependency is not itself an error at this layer)."
  (let* ((id->action (make-hash-table :test 'equal))
         (visited (make-hash-table :test 'equal))
         (visiting (make-hash-table :test 'equal))
         (result '()))
    (dolist (a actions) (setf (gethash (action-identity a) id->action) a))
    (labels ((visit (action path)
               (let ((id (action-identity action)))
                 (cond
                   ((gethash id visited) nil)
                   ((gethash id visiting)
                    (error 'dependency-cycle :cycle (reverse (cons id path))))
                   (t
                    (setf (gethash id visiting) t)
                    (dolist (dep-id (getf action :depends-on))
                      (let ((dep (gethash dep-id id->action)))
                        (when dep (visit dep (cons id path)))))
                    (remhash id visiting)
                    (setf (gethash id visited) t)
                    (push action result))))))
      (dolist (a actions) (visit a nil)))
    (nreverse result)))

(defun execute-action (action &key (mode :apply))
  "Dispatch ACTION to its registered executor under MODE (:apply or :check)."
  (let ((executor (find-executor (action-type action))))
    (with-linacs-restarts ()
      (handler-case (funcall executor action :mode mode)
        (linacs-error (e) (error e))
        (error (e)
          (error 'execution-failure
                 :action-type (action-type action)
                 :target (action-target action)
                 :underlying e))))))
