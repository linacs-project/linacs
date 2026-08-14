(in-package #:linacs-tests)

(def-suite action-provenance
  :in linacs-tests
  :description "ActionProvenance objects (REFACTOR.org Action 5)")
(in-suite action-provenance)

(def-test register-provenance-normalizes-plist-to-object ()
  "REGISTER-PROVENANCE stores an ACTION-PROVENANCE instance even when given
the historic (:feature ... :provider ... :source ...) plist."
  (reset-project-registries)
  (linacs.core:register-provenance
   '(:p . "t")
   (list :feature :editor :provider :emacs
         :source "provider emacs for feature editor"
         :facts-snapshot '(:os :hostname)))
  (let ((prov (linacs.core:action-provenance '(:p . "t"))))
    (is (typep prov 'linacs.core:action-provenance))
    (is (eq (linacs.core:provenance-feature prov) :editor))
    (is (eq (linacs.core:provenance-provider prov) :emacs))
    (is (equal (linacs.core:provenance-facts-snapshot prov) '(:os :hostname)))
    (is (equal (linacs.core:provenance-source prov) "provider emacs for feature editor"))))

(def-test register-provenance-passes-object-through ()
  "An ACTION-PROVENANCE instance given to REGISTER-PROVENANCE is stored
as-is (no re-wrapping, so identity is preserved)."
  (reset-project-registries)
  (let ((prov (linacs.core:make-action-provenance :source "user" :location "home.lisp:12")))
    (linacs.core:register-provenance '(:q . "u") prov)
    (is (eq (linacs.core:action-provenance '(:q . "u")) prov))
    (is (equal (linacs.core:provenance-location (linacs.core:action-provenance '(:q . "u")))
               "home.lisp:12"))))

(def-test provenance-accessors-accept-plists ()
  "The PROVENANCE-* readers also work on the historic plist shape, so mixed
call sites keep working during migration."
  (let ((prov (list :feature :gpu :provider :nvidia)))
    (is (eq (linacs.core:provenance-feature prov) :gpu))
    (is (eq (linacs.core:provenance-provider prov) :nvidia))
    (is (null (linacs.core:provenance-source prov)))
    (is (null (linacs.core:provenance-facts-snapshot nil)))))

(def-test provenance-plist-round-trip ()
  "PROVENANCE->PLIST then MAKE-ACTION-PROVENANCE-FROM-PLIST preserves every
field."
  (let* ((prov (linacs.core:make-action-provenance :source "user" :feature :dev
                                                    :provider :base
                                                    :facts-snapshot '(:os)
                                                    :location "home.lisp:4"))
         (plist (linacs.core:provenance->plist prov))
         (back (linacs.core:make-action-provenance-from-plist plist)))
    (is (equal (linacs.core:provenance-source back) "user"))
    (is (eq (linacs.core:provenance-feature back) :dev))
    (is (eq (linacs.core:provenance-provider back) :base))
    (is (equal (linacs.core:provenance-facts-snapshot back) '(:os)))
    (is (equal (linacs.core:provenance-location back) "home.lisp:4"))))

(def-test make-action-provenance-from-plist-accepts-nil ()
  "The plist normalizer returns NIL for NIL (defensive, for callers that
conditionally register)."
  (is (null (linacs.core:make-action-provenance-from-plist nil))))