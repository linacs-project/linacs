;;;; src/domain/execution/provenance.lisp
;;;;
;;;; ACTION-PROVENANCE: the object stored in the provenance table for each
;;;; action identity, describing where the action came from -- the feature
;;;; and provider that produced it, or the user-level source -- plus the
;;;; facts snapshot read while it was produced (REFACTOR.org Action 5).
;;;; Typed replacement for the historic (:feature ... :provider ...)
;;;; plists; the PROVENANCE-* readers accept either an ACTION-PROVENANCE
;;;; or a plist.

(in-package :linacs.core)

(defclass action-provenance ()
  ((source         :initarg :source         :initform nil
                   :documentation "The origin: \"provider <p> for feature
<f>\" for provider actions, or the user-level :source (else \"user\").")
   (feature        :initarg :feature        :initform nil
                   :documentation "The feature keyword that produced this
action, for provider actions.")
   (provider       :initarg :provider       :initform nil
                   :documentation "The provider keyword used for the
feature, for provider actions.")
   (facts-snapshot :initarg :facts-snapshot :initform nil
                   :documentation "The fact keys read while this action
was produced (SNAPSHOT-FACTS-READ).")
   (location       :initarg :location       :initform nil
                   :documentation "For user actions, the source location
(:location stamped by the DSL, e.g. \"home.lisp:12\").")))

(defun make-action-provenance (&key source feature provider facts-snapshot location)
  "Construct an ACTION-PROVENANCE. All slots default to NIL."
  (make-instance 'action-provenance
                 :source source :feature feature :provider provider
                 :facts-snapshot facts-snapshot :location location))

(defun make-action-provenance-from-plist (provenance)
  "Normalize a historic (:feature ... :provider ... :source ...) plist
into an ACTION-PROVENANCE. Returns NIL for NIL."
  (if provenance
      (make-action-provenance :source (getf provenance :source)
                              :feature (getf provenance :feature)
                              :provider (getf provenance :provider)
                              :facts-snapshot (getf provenance :facts-snapshot)
                              :location (getf provenance :location))
      nil))

(defgeneric provenance-source (provenance)
  (:documentation "The :source field of PROVENANCE (an ACTION-PROVENANCE
or a plist), else NIL."))
(defmethod provenance-source ((provenance action-provenance)) (slot-value provenance 'source))
(defmethod provenance-source ((provenance list)) (getf provenance :source))
(defmethod provenance-source (provenance) (declare (ignore provenance)) nil)

(defgeneric provenance-feature (provenance)
  (:documentation "The :feature field of PROVENANCE (an ACTION-PROVENANCE
or a plist), else NIL."))
(defmethod provenance-feature ((provenance action-provenance)) (slot-value provenance 'feature))
(defmethod provenance-feature ((provenance list)) (getf provenance :feature))
(defmethod provenance-feature (provenance) (declare (ignore provenance)) nil)

(defgeneric provenance-provider (provenance)
  (:documentation "The :provider field of PROVENANCE (an ACTION-PROVENANCE
or a plist), else NIL."))
(defmethod provenance-provider ((provenance action-provenance)) (slot-value provenance 'provider))
(defmethod provenance-provider ((provenance list)) (getf provenance :provider))
(defmethod provenance-provider (provenance) (declare (ignore provenance)) nil)

(defgeneric provenance-facts-snapshot (provenance)
  (:documentation "The :facts-snapshot field of PROVENANCE (an
ACTION-PROVENANCE or a plist), else NIL."))
(defmethod provenance-facts-snapshot ((provenance action-provenance))
  (slot-value provenance 'facts-snapshot))
(defmethod provenance-facts-snapshot ((provenance list)) (getf provenance :facts-snapshot))
(defmethod provenance-facts-snapshot (provenance) (declare (ignore provenance)) nil)

(defgeneric provenance-location (provenance)
  (:documentation "The :location field of PROVENANCE (an ACTION-PROVENANCE
or a plist), else NIL."))
(defmethod provenance-location ((provenance action-provenance)) (slot-value provenance 'location))
(defmethod provenance-location ((provenance list)) (getf provenance :location))
(defmethod provenance-location (provenance) (declare (ignore provenance)) nil)

(defun provenance->plist (provenance)
  "Serialize PROVENANCE to the historic (:source ... :feature ...)
plist shape. The inverse is MAKE-ACTION-PROVENANCE-FROM-PLIST."
  (when provenance
    (list :source (provenance-source provenance)
          :feature (provenance-feature provenance)
          :provider (provenance-provider provenance)
          :facts-snapshot (provenance-facts-snapshot provenance)
          :location (provenance-location provenance))))