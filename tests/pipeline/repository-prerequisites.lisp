;;;; tests/pipeline/repository-prerequisites.lisp
;;;;
;;;; Tests for RESOLVE-REPOSITORY-PREREQUISITES -- the resolve-time injector
;;;; that turns a :repositories catalog entry into a first-class :repository
;;;; action ordered ahead of the :package that needs it.
;;;;
;;;; Scope: pure resolution, no executor side effects. Facts are bound
;;;; directly on *FACTS*, and catalog entries registered per test then
;;;; cleaned up, so nothing leaks into other suites.

(in-package #:linacs-tests)

(def-suite pipeline-repository-prerequisites
  :in linacs-tests
  :description "Tests for resolve-repository-prerequisites (distro repositories as package prerequisites)")
(in-suite pipeline-repository-prerequisites)

(defun repositories-catalog-table ()
  "The :repositories catalog hash table, or NIL. Accessed via FIND-SYMBOL
since *CATALOGS* is not exported from :linacs.core."
  (let ((catalogs (symbol-value (find-symbol "*CATALOGS*" (find-package :linacs.core)))))
    (and catalogs (gethash :repositories catalogs))))

(defun clear-repositories-catalog ()
  "Drop every :repositories catalog entry."
  (let ((table (repositories-catalog-table)))
    (when table (clrhash table))))

(defmacro with-repo-catalog (entries &body body)
  "Register every (:canonical (:distro spec ...)) ENTRY into the
:repositories catalog for the duration of BODY, then clear the catalog."
  `(unwind-protect
        (progn
          ,@(mapcar (lambda (e)
                      `(linacs.core:register-catalog :repositories ,(car e)
                                                     ',(cdr e)))
                    entries)
          ,@body)
     (clear-repositories-catalog)))

(defun resolve-fixture-actions (actions &key (os :fedora))
  "Run RESOLVE-REPOSITORY-PREREQUISITES over ACTIONS with *FACTS* bound to OS."
  (let ((linacs.core:*facts* (list :os os)))
    (linacs.core:resolve-repository-prerequisites actions)))

(def-test injects-repository-action-for-system-package ()
  "A :package via :system whose canonical target has a :repositories entry
gains a :repository action ordered before it, plus a :depends-on edge."
  (with-repo-catalog ((:wezterm (:fedora (:method :dnf-copr :id "@wez/wezterm"))))
    (let* ((pkg (list :action :package :target :wezterm :via :system))
           (result (resolve-fixture-actions (list pkg))))
      (is (= 2 (length result)))
      (let* ((repo (find :repository result :key #'linacs.core:action-type))
             (pkg-prime (find :package result :key #'linacs.core:action-type)))
        (is (not (null repo)) "a :repository action should be injected")
        (is (equal "@wez/wezterm" (linacs.core:action-target repo)))
        (is (eq :dnf-copr (getf repo :method)))
        (is (equal (list '(:repository :dnf-copr . "@wez/wezterm"))
                   (getf pkg-prime :depends-on))
            "the package should depend on the injected repository")))))

(def-test no-injection-when-catalog-entry-absent ()
  "A package with no :repositories entry is untouched -- the catalog's
string fallback is treated as 'no repository needed', so behavior is
exactly as before."
  (let* ((pkg (list :action :package :target :emacs :via :system))
         (result (resolve-fixture-actions (list pkg))))
    (is (equal (list pkg) result))
    (is (null (getf pkg :depends-on)))))

(def-test no-injection-for-non-system-vias ()
  "Flatpak/pip/npm packages manage their own remotes; the injector only
applies to :via :system."
  (with-repo-catalog ((:wezterm (:fedora (:method :dnf-copr :id "@wez/wezterm"))))
    (dolist (via '(:flatpak :pip :npm))
      (let* ((pkg (list :action :package :target :wezterm :via via))
             (result (resolve-fixture-actions (list pkg))))
        (is (= 1 (length result)) "no injection for :via ~a" via)
        (is (null (getf pkg :depends-on)))))))

(def-test no-injection-for-string-targets ()
  "The :repositories catalog is keyed by canonical keyword; a string target
like (package \"wezterm\") is skipped."
  (with-repo-catalog ((:wezterm (:fedora (:method :dnf-copr :id "@wez/wezterm"))))
    (let* ((pkg (list :action :package :target "wezterm" :via :system))
           (result (resolve-fixture-actions (list pkg))))
      (is (= 1 (length result)))
      (is (null (getf pkg :depends-on))))))

(def-test existing-depends-on-is-preserved ()
  "A provider/user :depends-on edge on the package is preserved -- the
repository identity is appended, not clobbered."
  (with-repo-catalog ((:wezterm (:fedora (:method :dnf-copr :id "@wez/wezterm"))))
    (let* ((pkg (list :action :package :target :wezterm :via :system
                      :depends-on '((:ensure-dir . "~/.config/wezterm/"))))
           (result (resolve-fixture-actions (list pkg))))
      (is (equal (list '(:ensure-dir . "~/.config/wezterm/")
                       '(:repository :dnf-copr . "@wez/wezterm"))
                 (getf pkg :depends-on))))))

(def-test shared-repository-injects-one-per-package ()
  "Two packages needing the same repository each get an injected
:repository action -- emitted per package by the injector, all carrying
the same identity so dedup-actions (covered in the executor suite) can
later collapse them into one. Both packages depend on that identity."
  (with-repo-catalog ((:fish (:fedora (:method :dnf-copr :id "@wez/wezterm")))
                      (:starship (:fedora (:method :dnf-copr :id "@wez/wezterm"))))
    (let* ((a (list :action :package :target :fish :via :system))
           (b (list :action :package :target :starship :via :system))
           (result (resolve-fixture-actions (list a b))))
      (is (= 4 (length result)))
      (is (= 2 (count :repository result :key #'linacs.core:action-type)))
      (let* ((repos (remove :package result :key #'linacs.core:action-type))
             (repo (first repos)))
        (is (equal '(:repository :dnf-copr . "@wez/wezterm")
                   (linacs.core:action-identity repo)))
        (dolist (repo2 (rest repos))
          (is (equal (linacs.core:action-identity repo)
                     (linacs.core:action-identity repo2))
              "all injected repository actions share one identity"))
        (is (equal (list '(:repository :dnf-copr . "@wez/wezterm"))
                   (getf a :depends-on)))
        (is (equal (list '(:repository :dnf-copr . "@wez/wezterm"))
                   (getf b :depends-on)))))))

(def-test injector-ignores-distro-absence ()
  "A :repositories entry present only for :ubuntu does not inject on a
:fedora machine -- distribution variation is the catalog's job."
  (with-repo-catalog ((:fish (:ubuntu (:method :apt-ppa :id "ppa:fish-shell/release-3"))))
    (let* ((pkg (list :action :package :target :fish :via :system))
           (result (resolve-fixture-actions (list pkg) :os :fedora)))
      (is (= 1 (length result)))
      (is (null (getf pkg :depends-on))))))