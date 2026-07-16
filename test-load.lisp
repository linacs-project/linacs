;; Try loading everything with MAKE-PATHNAME
(setf asdf:*central-registry* nil)

;; Add paths using MAKE-PATHNAME
(push (make-pathname :directory '(:absolute "home" "echjansen" "Projects" "codeberg" "linacs-project" "linacs"))
      asdf:*central-registry*)
(push (make-pathname :directory '(:absolute "home" "echjansen" "Projects" "codeberg" "linacs-project" "linacs-tests"))
      asdf:*central-registry*)

(format t "Registry: ~a~%" asdf:*central-registry*)

;; Load ASDF
(format t "Loading ASDF...~%")
(ql:quickload :asdf)
(format t "ASDF loaded~%")

;; Load linacs
(format t "Loading linacs.asd...~%")
(load "linacs.asd")
(format t "linacs.asd loaded~%")

;; Load linacs system
(format t "Loading linacs system...~%")
(asdf:load-system :linacs)
(format t "linacs system loaded!~%")
