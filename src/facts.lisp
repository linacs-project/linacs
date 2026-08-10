;;;; src/facts.lisp
;;;;
;;;; Fact prober registration and probing. A Fact is a probed or
;;;; profile-overridden truth about the current machine (:os, :hostname,
;;;; :laptop-p, :display-server, and anything a provider author adds);
;;;; *FACTS* holds the resolved plist for the current run.
;;;;
;;;; Usage:
;;;;   Reading a fact, from inside a home definition or a provider:
;;;;
;;;;     (fact :laptop-p)
;;;;
;;;;   Registering a new one, typically from a project's providers/ file:
;;;;
;;;;     (register-fact-prober :gpu (lambda () (if (probe-file "...") :nvidia :unknown)))
;;;;
;;;; Every built-in prober below reads /proc or /sys directly (or shells
;;;; out to a read-only command like `uname`) -- never requires root, and
;;;; never depends on a specific distro's tooling. Two facts a first draft
;;;; of this list wanted -- :secure-boot-p and :product-uuid -- are
;;;; deliberately NOT here: reading either one for real (the EFI
;;;; SecureBoot efivar's value; /sys/class/dmi/id/product_uuid) requires
;;;; root on every mainstream distro's default permissions, and this file
;;;; never asks for that. (Their sibling attributes that stop short of
;;;; the actually-sensitive bytes -- :uefi-p, which only checks whether
;;;; /sys/firmware/efi exists, and :product-name/:sys-vendor, whose sysfs
;;;; files are left world-readable by the kernel -- are fine and stay.)
;;;;
;;;; This file intentionally does not call anything defined in
;;;; src/action-types/ (e.g. WHICH, READ-FILE-STRING): those load after
;;;; this file, and referencing them here would trade a working forward
;;;; reference for a spurious compile-time style-warning. Where a probe
;;;; needs a file read or a subprocess call, it uses UIOP's library
;;;; functions directly and keeps a couple of tiny local helpers below.

(in-package :linacs.core)

(defvar *fact-probers* (make-hash-table :test 'eq)
  "Maps fact key -> (prober-function . registrant-name).")

(defvar *facts* nil
  "Plist of resolved facts, populated by PROBE-ALL-FACTS and merged with
a profile's overrides. Read via FACT.")

(defvar *facts-read* (make-hash-table :test 'eq)
  "Set of fact keys read during the current provider invocation. Populated
by FACT* and reset before each provider call. Used for provenance tracking
so the :facts-snapshot only includes facts the provider actually consulted.")

(defvar *fact-metadata* (make-hash-table :test 'eq)
  "Maps fact key -> plist with :type (CL type specifier) and :doc (string).
Populated by REGISTER-FACT-PROBER when :type and/or :doc are supplied.")

(defun register-fact-prober (key prober-fn &optional (registrant (package-name *package*))
                             &key type doc)
  "Register a fact prober for KEY. If a different registrant already
registered a prober for the same KEY, signal FACT-PROBER-CONFLICT and abort
startup -- there is no implicit first-one-wins resolution.

Optional keyword arguments:
  :TYPE -- a CL type specifier checked at probe time (via TYPEP) for
           informative warnings when the prober returns an unexpected value.
  :DOC  -- a human-readable description shown by `linacs list`."
  (let ((existing (gethash key *fact-probers*)))
    (when (and existing (not (string= (cdr existing) registrant)))
      (error 'fact-prober-conflict
             :fact-key key
             :registrants (list (cdr existing) registrant)))
    (setf (gethash key *fact-probers*) (cons prober-fn registrant)))
  (when (or type doc)
    (setf (gethash key *fact-metadata*)
          (append (when type (list :type type))
                  (when doc (list :doc doc)))))
  key)

(defun declare-fact (key &key type doc)
  "Document a fact key that has no prober -- e.g. a profile-only fact like
:work-p or :languages -- without registering one. Populates *FACT-METADATA*
so `linacs list` shows the fact and APPLY-PROFILE does not warn on it as a
possible typo. Same metadata keywords as REGISTER-FACT-PROBER: :TYPE (a CL
type specifier) and :DOC (a human-readable description)."
  (setf (gethash key *fact-metadata*)
        (append (when type (list :type type))
                (when doc (list :doc doc))))
  key)

(defun default-fact-probers ()
  "Register the built-in facts LINACS always probes, with type metadata."
  (register-fact-prober :os #'probe-os "linacs-core"
    :type '(member :fedora :arch :debian :ubuntu :unknown)
    :doc "Linux distribution identifier")
  (register-fact-prober :hostname (lambda () (or (uiop:hostname) "unknown")) "linacs-core"
    :type '(or string (member :unknown))
    :doc "System hostname")
  (register-fact-prober :laptop-p #'probe-laptop-p "linacs-core"
    :type '(member t nil)
    :doc "T if any battery is present")
  (register-fact-prober :display-server #'probe-display-server "linacs-core"
    :type '(or (member :wayland :x11) null)
    :doc "Active display server; nil in headless/SSH environments")
  (register-fact-prober :gpu-vendor #'probe-gpu-vendor "linacs-core"
    :type 'list
    :doc "List of keyword GPU vendor identifiers found via DRM")
  (register-fact-prober :vm-p #'probe-vm-p "linacs-core"
    :type '(member t nil)
    :doc "T if running inside a VM or hypervisor")
  (register-fact-prober :cpu-arch #'probe-cpu-arch "linacs-core"
    :type 'keyword
    :doc "CPU architecture from uname -m (e.g. :x86-64, :aarch64)")
  (register-fact-prober :package-manager #'probe-package-manager "linacs-core"
    :type '(member :pacman :dnf :yum :apt :zypper :apk :xbps :portage :unknown)
    :doc "Installed system package manager binary")
  (register-fact-prober :wifi-p #'probe-wifi-p "linacs-core"
    :type '(member t nil)
    :doc "T if a wireless network interface is present")
  (register-fact-prober :bluetooth-p #'probe-bluetooth-p "linacs-core"
    :type '(member t nil)
    :doc "T if a Bluetooth adapter is present")
  (register-fact-prober :touchpad-p #'probe-touchpad-p "linacs-core"
    :type '(member t nil)
    :doc "T if a touchpad input device is present")
  (register-fact-prober :ram-gb #'probe-ram-gb "linacs-core"
    :type '(or integer (member :unknown))
    :doc "Total system RAM in gigabytes")
  (register-fact-prober :cpu-cores #'probe-cpu-cores "linacs-core"
    :type '(or integer (member :unknown))
    :doc "Number of logical CPU threads")
  (register-fact-prober :uefi-p #'probe-uefi-p "linacs-core"
    :type '(member t nil)
    :doc "T if booted in UEFI mode (/sys/firmware/efi exists)")
  (register-fact-prober :init-system #'probe-init-system "linacs-core"
    :type '(member :systemd :openrc :runit :sysvinit :unknown)
    :doc "Init system managing PID 1")
  (register-fact-prober :root-disk-type #'probe-root-disk-type "linacs-core"
    :type '(member :nvme :ssd :hdd :unknown)
    :doc "Root filesystem backing disk type")
  (register-fact-prober :fingerprint-p #'probe-fingerprint-p "linacs-core"
    :type '(member t nil)
    :doc "T if a USB fingerprint reader is present")
  (register-fact-prober :container-p #'probe-container-p "linacs-core"
    :type '(member t nil)
    :doc "T if running inside a container")
  (register-fact-prober :toolbox-p #'probe-toolbox-p "linacs-core"
    :type '(member t nil)
    :doc "T if toolbox or podman binary is on PATH (containerised CLI tools)")
  (register-fact-prober :in-toolbox-p #'probe-in-toolbox-p "linacs-core"
    :type '(member t nil)
    :doc "T if running inside a toolbox container ($TOOLBOX_PATH is set)")
  (register-fact-prober :flatpak-p #'probe-flatpak-p "linacs-core"
    :type '(member t nil)
    :doc "T if flatpak binary is on PATH")
  (register-fact-prober :podman-p #'probe-podman-p "linacs-core"
    :type '(member t nil)
    :doc "T if podman binary is on PATH (rootless containers)")
  (register-fact-prober :appimage-p #'probe-appimage-p "linacs-core"
    :type '(member t nil)
    :doc "T if FUSE is available (AppImages can execute)")
  (register-fact-prober :sys-vendor #'probe-sys-vendor "linacs-core"
    :type '(or string (member :unknown))
    :doc "System vendor string from DMI")
  (register-fact-prober :product-name #'probe-product-name "linacs-core"
    :type '(or string (member :unknown))
    :doc "Product name string from DMI"))

;;; --- Small local helpers, self-contained on purpose (see file header) ---

(defun fact-read-string (path)
  "First line of PATH, trimmed; NIL if the path is missing, unreadable
\(including \"exists but root-only\", which several /sys attributes are\),
or empty."
  (ignore-errors
    (with-open-file (f path)
      (let ((line (string-trim '(#\Newline #\Space #\Tab) (read-line f nil ""))))
        (and (plusp (length line)) line)))))

(defun fact-read-whole-file (path)
  (ignore-errors (uiop:read-file-string path)))

(defun fact-subdir-names (dir)
  "Bare directory names (not full paths) immediately under DIR, or NIL if
DIR doesn't exist -- never signals."
  (mapcar (lambda (p) (car (last (pathname-directory p))))
          (or (ignore-errors (uiop:subdirectories dir)) nil)))

(defun fact-command-available-p (name)
  "A tiny, deliberately-local PATH check -- see the file header for why
this doesn't just call action-types/helpers.lisp's WHICH."
  (ignore-errors
    (zerop (nth-value 2
                      (uiop:run-program (list "sh" "-c" (format nil "command -v ~a" name))
                                        :output nil :error-output nil :ignore-error-status t)))))

(defun fact-string-contains-any-p (haystack needles)
  (let ((h (string-downcase haystack)))
    (some (lambda (n) (search n h)) needles)))

;;; --- :os, :hostname, :laptop-p, :display-server (pre-existing) ---------

(defun probe-os ()
  (cond
    ((probe-file "/etc/fedora-release") :fedora)
    ((probe-file "/etc/arch-release") :arch)
    ((probe-file "/etc/debian_version") :debian)
    ((probe-file "/etc/os-release")
     (handler-case
         (with-open-file (f "/etc/os-release")
           (loop for line = (read-line f nil nil)
                 while line
                 when (and (>= (length line) 3) (string= line "ID=" :end1 3))
                 do (return (intern (string-upcase (string-trim "\"" (subseq line 3))) :keyword))
                 finally (return :unknown)))
       (error () :unknown)))
    (t :unknown)))

(defun probe-laptop-p ()
  "T if any battery is present. Globs BAT* rather than hardcoding BAT0 --
some machines (multi-battery Thinkpads among them) only expose BAT1."
  (and (some (lambda (name) (and (>= (length name) 3) (string= name "BAT" :end1 3)))
             (fact-subdir-names "/sys/class/power_supply/"))
       t))

(defun probe-display-server ()
  (cond
    ((uiop:getenv "WAYLAND_DISPLAY") :wayland)
    ((uiop:getenv "DISPLAY") :x11)
    (t nil)))

;;; --- :gpu-vendor ---------------------------------------------------------

(defun gpu-vendor-id->keyword (id)
  (cond ((string-equal id "0x10de") :nvidia)
        ((string-equal id "0x1002") :amd)
        ((string-equal id "0x8086") :intel)
        (t nil)))

(defun probe-gpu-vendor ()
  "Every distinct GPU vendor found under /sys/class/drm/card*/device/vendor,
as a list of keywords -- e.g. (:intel :nvidia) on a hybrid-graphics
laptop, so `(member :nvidia (fact :gpu-vendor))` answers \"is there an
NVIDIA card at all\" regardless of whether it's the only one. Empty list
if no DRM cards are found (headless VM, minimal container, or a GPU
driver simply isn't loaded) -- treat that as \"can't tell\", not \"no GPU\"."
  (let (vendors)
    (dolist (name (fact-subdir-names "/sys/class/drm/"))
      (when (and (>= (length name) 5) (string= name "card" :end1 4)
                 (every #'digit-char-p (subseq name 4)))
        (let* ((id (fact-read-string (format nil "/sys/class/drm/~a/device/vendor" name)))
               (v (and id (gpu-vendor-id->keyword id))))
          (when (and v (not (member v vendors))) (push v vendors)))))
    (nreverse vendors)))

;;; --- :vm-p -----------------------------------------------------------------

(defparameter *vm-markers*
  '("qemu" "vmware" "virtualbox" "innotek" "bochs" "xen" "kvm" "virtual machine"
    "google compute engine" "amazon ec2")
  "Case-insensitive substrings of DMI sys_vendor/product_name that reliably
indicate a hypervisor, not real hardware.")

(defun cpuinfo-hypervisor-flag-p ()
  "T if /proc/cpuinfo's `flags` line lists `hypervisor` (x86-specific;
harmless no-op elsewhere -- just returns NIL)."
  (let ((cpuinfo (fact-read-whole-file "/proc/cpuinfo")))
    (and cpuinfo
         (some (lambda (line)
                 (and (>= (length line) 5) (string= line "flags" :end1 5)
                      (search " hypervisor" line)))
               (uiop:split-string cpuinfo :separator '(#\Newline))))))

(defun probe-vm-p ()
  "Best-effort: checks DMI sys_vendor/product_name for known hypervisor
signatures, falling back to x86's cpuinfo hypervisor flag. On DMI-less
hardware (most ARM SBCs) this can under-detect -- there's no root-free
signal left to check in that case."
  (let ((vendor (or (fact-read-string "/sys/class/dmi/id/sys_vendor") ""))
        (product (or (fact-read-string "/sys/class/dmi/id/product_name") "")))
    (and (or (fact-string-contains-any-p vendor *vm-markers*)
             (fact-string-contains-any-p product *vm-markers*)
             (cpuinfo-hypervisor-flag-p))
         t)))

;;; --- :cpu-arch ---------------------------------------------------------

(defun probe-cpu-arch ()
  "uname -m, as a keyword with underscores turned to hyphens (:x86-64,
:aarch64, :armv7l, ...) to match the rest of LINACS's keyword style."
  (let ((out (ignore-errors
               (string-trim '(#\Newline #\Space)
                            (uiop:run-program '("uname" "-m") :output '(:string :stripped t))))))
    (if (and out (plusp (length out)))
        (intern (string-upcase (substitute #\- #\_ out)) :keyword)
        :unknown)))

;;; --- :package-manager ----------------------------------------------------

(defparameter *package-manager-binaries*
  '(("pacman" . :pacman) ("dnf" . :dnf) ("yum" . :yum) ("apt-get" . :apt)
    ("zypper" . :zypper) ("apk" . :apk) ("xbps-install" . :xbps) ("emerge" . :portage))
  "Checked in this order; the first binary found on PATH wins. Detecting
the actual installed tool rather than mapping from :os means a distro
:os doesn't recognize by name -- any Arch/Debian/Fedora derivative --
still resolves correctly.")

(defun probe-package-manager ()
  (loop for (binary . key) in *package-manager-binaries*
        when (fact-command-available-p binary)
        return key
        finally (return :unknown)))

;;; --- :wifi-p, :bluetooth-p -------------------------------------------------

(defun probe-wifi-p ()
  (and (some (lambda (name) (uiop:directory-exists-p (format nil "/sys/class/net/~a/wireless/" name)))
             (fact-subdir-names "/sys/class/net/"))
       t))

(defun probe-bluetooth-p ()
  "Checks for an actual adapter subdirectory, not just the /sys/class/
bluetooth class node -- that node can exist (module loaded generically by
the distro) with zero adapters present."
  (and (fact-subdir-names "/sys/class/bluetooth/") t))

;;; --- :touchpad-p ---------------------------------------------------------

(defun probe-touchpad-p ()
  (and (ignore-errors
         (with-open-file (f "/proc/bus/input/devices")
           (loop for line = (read-line f nil nil)
                 while line
                 thereis (and (>= (length line) 2) (string= line "N:" :end1 2)
                              (search "touchpad" (string-downcase line))))))
       t))

;;; --- :ram-gb, :cpu-cores -------------------------------------------------

(defun probe-ram-gb ()
  (or (ignore-errors
        (with-open-file (f "/proc/meminfo")
          (loop for line = (read-line f nil nil)
                while line
                when (and (>= (length line) 9) (string= line "MemTotal:" :end1 9))
                do (return (round (parse-integer (remove-if-not #'digit-char-p line))
                                  (* 1024 1024))))))
      :unknown))

(defun probe-cpu-cores ()
  "Logical CPUs (threads), matching what `nproc` and most build-parallelism
flags (-j) mean by \"cores\" -- not physical core count."
  (or (ignore-errors
        (with-open-file (f "/proc/cpuinfo")
          (loop for line = (read-line f nil nil)
                while line
                count (and (>= (length line) 9) (string= line "processor" :end1 9)))))
      :unknown))

;;; --- :uefi-p, :init-system -------------------------------------------------

(defun probe-uefi-p ()
  (and (uiop:directory-exists-p "/sys/firmware/efi/") t))

(defun probe-init-system ()
  "Best-effort. systemd is unambiguous (/run/systemd/system is only
created by systemd itself); the rest fall back to a couple of
distinguishing marker paths, since PID 1's /proc/1/comm is often just
\"init\" regardless of which init system that actually is."
  (cond
    ((uiop:directory-exists-p "/run/systemd/system/") :systemd)
    ((uiop:directory-exists-p "/run/openrc/") :openrc)
    ((let ((comm (fact-read-string "/proc/1/comm"))) (and comm (search "runit" comm))) :runit)
    ((uiop:file-exists-p "/etc/init.d/rcS") :sysvinit)
    (t :unknown)))

;;; --- :root-disk-type -------------------------------------------------------

(defun root-mount-device ()
  "The device field of /proc/mounts' entry for \"/\", or NIL."
  (ignore-errors
    (with-open-file (f "/proc/mounts")
      (loop for line = (read-line f nil nil)
            while line
            do (let ((fields (remove "" (uiop:split-string line :separator '(#\Space)) :test #'string=)))
                 (when (and (>= (length fields) 2) (string= (second fields) "/"))
                   (return (first fields))))))))

(defun block-device-name (path)
  "\"/dev/nvme0n1p2\" -> \"nvme0n1p2\", following one level of symlink
resolution first (LUKS/LVM mapper names, /dev/disk/by-* paths)."
  (let* ((resolved (or (ignore-errors (namestring (truename path))) path))
         (slash (position #\/ resolved :from-end t)))
    (if slash (subseq resolved (1+ slash)) resolved)))

(defun block-device-slaves (name)
  (fact-subdir-names (format nil "/sys/class/block/~a/slaves/" name)))

(defun resolve-leaf-block-device (name &optional (depth 0))
  "Follows device-mapper stacking (LUKS on LVM on a partition, etc.) down
to a real disk-backed block device. Bails out after a few levels rather
than risk looping forever on an unusual setup."
  (if (>= depth 5)
      name
      (let ((slaves (block-device-slaves name)))
        (if slaves (resolve-leaf-block-device (first slaves) (1+ depth)) name))))

(defun strip-partition-suffix (name)
  "nvme0n1p3 -> nvme0n1, mmcblk0p1 -> mmcblk0, sda2 -> sda, vda1 -> vda."
  (flet ((strip-trailing-pN (s)
           (let ((p (position #\p s :from-end t)))
             (if (and p (< p (1- (length s))) (every #'digit-char-p (subseq s (1+ p))))
                 (subseq s 0 p)
                 s))))
    (cond
      ((and (>= (length name) 4) (string= name "nvme" :end1 4)) (strip-trailing-pN name))
      ((and (>= (length name) 6) (string= name "mmcblk" :end1 6)) (strip-trailing-pN name))
      (t (string-right-trim "0123456789" name)))))

(defun probe-root-disk-type ()
  "Resolves the block device backing / (through device-mapper/LVM/LUKS
stacking, best-effort) and reads its rotational flag. :nvme for anything
under an nvme controller (always non-rotational, worth distinguishing
since it needs no separate I/O-scheduler tuning), :ssd / :hdd from the
rotational flag otherwise, :unknown if any step can't be resolved."
  (or (ignore-errors
        (let* ((device (root-mount-device)))
          (when device
            (let* ((leaf (resolve-leaf-block-device (block-device-name device)))
                   (disk (strip-partition-suffix leaf)))
              (cond
                ((and (>= (length disk) 4) (string= disk "nvme" :end1 4)) :nvme)
                (t (let ((rotational (fact-read-string (format nil "/sys/block/~a/queue/rotational" disk))))
                     (cond ((equal rotational "0") :ssd)
                           ((equal rotational "1") :hdd)
                           (t :unknown)))))))))
      :unknown))

;;; --- :fingerprint-p, :container-p ------------------------------------------

(defun probe-fingerprint-p ()
  "Heuristic: scans /sys/bus/usb/devices/*/product for \"fingerprint\" in
the USB product string. Covers the common case (a dedicated USB
fingerprint reader identifying itself); won't catch a reader wired in
some other way (e.g. some laptops expose one over an internal SPI/I2C
bus with a less descriptive name)."
  (and (some (lambda (name)
               (let ((product (fact-read-string (format nil "/sys/bus/usb/devices/~a/product" name))))
                 (and product (search "fingerprint" (string-downcase product)))))
             (fact-subdir-names "/sys/bus/usb/devices/"))
       t))

(defun probe-container-p ()
  (and (or (uiop:file-exists-p "/.dockerenv")
           (uiop:file-exists-p "/run/.containerenv")
           (let ((c (uiop:getenv "container"))) (and c (plusp (length c))))
           (let ((cgroup (fact-read-whole-file "/proc/1/cgroup")))
             (and cgroup (or (search "docker" cgroup) (search "lxc" cgroup) (search "kubepods" cgroup)))))
       t))

;;; --- :toolbox-p, :in-toolbox-p, :flatpak-p, :podman-p, :appimage-p ----------

(defun probe-toolbox-p ()
  (or (which "toolbox") (which "podman")))

(defun probe-in-toolbox-p ()
  (uiop:getenvp "TOOLBOX_PATH"))

(defun probe-flatpak-p ()
  (which "flatpak"))

(defun probe-podman-p ()
  (which "podman"))

(defun probe-appimage-p ()
  (which "fusermount"))

;;; --- :sys-vendor, :product-name --------------------------------------------
;;;
;;; Both /sys/class/dmi/id/sys_vendor and .../product_name are left
;;; world-readable by the kernel; their siblings product_uuid and
;;; product_serial are not (0400, root-only) -- which is exactly why
;;; those two aren't probed here. See the file header.

(defun probe-sys-vendor ()
  (or (fact-read-string "/sys/class/dmi/id/sys_vendor") :unknown))

(defun probe-product-name ()
  (or (fact-read-string "/sys/class/dmi/id/product_name") :unknown))

;;; --------------------------------------------------------------------------

(defun probe-all-facts ()
  "Run every registered fact prober once and populate *FACTS*.
Validates each probed value against its declared :type in *FACT-METADATA*
(if one exists), logging a warning on mismatch via `linacs.log:warn*`."
  (let ((result '()))
    (maphash (lambda (key entry)
               (let ((value (funcall (car entry))))
                 (let ((meta (gethash key *fact-metadata*)))
                   (when (and meta (getf meta :type))
                     (unless (typep value (getf meta :type))
                       (linacs.log:warn* "Fact ~s returned ~s (type ~s), which does not match declared type ~s"
                                         key value (type-of value) (getf meta :type)))))
                 (setf result (list* key value result))))
             *fact-probers*)
    (setf *facts* result)))

(defun fact (key)
  "Read a fact by keyword. Reflects probed values merged with any
profile override -- the home definition cannot distinguish the two.
Returns NIL for both \"key probed with value NIL\" and \"key never
probed\"; use FACT-KNOWN-P to distinguish."
  (getf *facts* key))

(defun fact-known-p (key)
  "T if KEY exists in *FACTS* (was probed or profile-overridden),
regardless of its value.  Returns NIL if KEY was never probed
(e.g. a misspelling or a prober that was never registered)."
  (let ((sentinel (make-symbol "FACT-NOT-FOUND")))
    (not (eq sentinel (getf *facts* key sentinel)))))

(defun fact* (key)
  "Like FACT but also records KEY in *FACTS-READ* for provenance tracking.
Provider authors should use this instead of FACT when the provider wants
its fact dependencies to appear in the :facts-snapshot provenance field.
Using plain FACT is still fine for internal code that shouldn't appear
in provenance traces."
  (setf (gethash key *facts-read*) t)
  (getf *facts* key))

(defun reset-facts-read ()
  "Clear *FACTS-READ*. Called before each provider invocation."
  (clrhash *facts-read*))

(defun snapshot-facts-read ()
  "Return the list of fact keys read since the last RESET-FACTS-READ,
suitable for embedding in a :facts-snapshot provenance plist."
  (loop for k being the hash-key of *facts-read* collect k))
