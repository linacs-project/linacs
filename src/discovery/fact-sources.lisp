;;;; src/discovery/fact-sources.lisp
;;;;
;;;; Registration of the built-in facts LINACS always probes (REFACTOR.org
;;;; Thought 23 / Action 18). Each call wires a PROBE-* implementation from
;;;; probers.lisp to its fact key with type metadata; the registry that
;;;; stores these lives in registry.lisp.
;;;;
;;;; Loaded after probers.lisp (it references the probe functions) and
;;;; after registry.lisp (it references REGISTER-FACT-SOURCE).

(in-package :linacs.core)

(defun default-fact-sources ()
  "Register the built-in facts LINACS always probes, with type metadata."
  (register-fact-source :os #'probe-os "linacs-core"
    :type '(member :fedora :arch :debian :ubuntu :unknown)
    :doc "Linux distribution identifier")
  (register-fact-source :hostname (lambda () (or (uiop:hostname) "unknown")) "linacs-core"
    :type '(or string (member :unknown))
    :doc "System hostname")
  (register-fact-source :laptop-p #'probe-laptop-p "linacs-core"
    :type '(member t nil)
    :doc "T if any battery is present")
  (register-fact-source :display-server #'probe-display-server "linacs-core"
    :type '(or (member :wayland :x11) null)
    :doc "Active display server; nil in headless/SSH environments")
  (register-fact-source :desktop #'probe-desktop-environment "linacs-core"
    :type '(or null (member :gnome :kde :xfce :sway :hyprland :i3 :other))
    :doc "Desktop environment from $XDG_CURRENT_DESKTOP, or nil if headless/SSH")
  (register-fact-source :os-version #'probe-os-version "linacs-core"
    :type '(or string null)
    :doc "Distro version identifier from /etc/os-release VERSION_ID")
  (register-fact-source :gpu-vendor #'probe-gpu-vendor "linacs-core"
    :type 'list
    :doc "List of keyword GPU vendor identifiers found via DRM")
  (register-fact-source :vm-p #'probe-vm-p "linacs-core"
    :type '(member t nil)
    :doc "T if running inside a VM or hypervisor")
  (register-fact-source :cpu-arch #'probe-cpu-arch "linacs-core"
    :type 'keyword
    :doc "CPU architecture from uname -m (e.g. :x86-64, :aarch64)")
  (register-fact-source :package-manager #'probe-package-manager "linacs-core"
    :type '(member :pacman :dnf :yum :apt :zypper :apk :xbps :portage :unknown)
    :doc "Installed system package manager binary")
  (register-fact-source :wifi-p #'probe-wifi-p "linacs-core"
    :type '(member t nil)
    :doc "T if a wireless network interface is present")
  (register-fact-source :bluetooth-p #'probe-bluetooth-p "linacs-core"
    :type '(member t nil)
    :doc "T if a Bluetooth adapter is present")
  (register-fact-source :touchpad-p #'probe-touchpad-p "linacs-core"
    :type '(member t nil)
    :doc "T if a touchpad input device is present")
  (register-fact-source :ram-gb #'probe-ram-gb "linacs-core"
    :type '(or integer (member :unknown))
    :doc "Total system RAM in gigabytes")
  (register-fact-source :cpu-cores #'probe-cpu-cores "linacs-core"
    :type '(or integer (member :unknown))
    :doc "Number of logical CPU threads")
  (register-fact-source :uefi-p #'probe-uefi-p "linacs-core"
    :type '(member t nil)
    :doc "T if booted in UEFI mode (/sys/firmware/efi exists)")
  (register-fact-source :init-system #'probe-init-system "linacs-core"
    :type '(member :systemd :openrc :runit :sysvinit :unknown)
    :doc "Init system managing PID 1")
  (register-fact-source :root-disk-type #'probe-root-disk-type "linacs-core"
    :type '(member :nvme :ssd :hdd :unknown)
    :doc "Root filesystem backing disk type")
  (register-fact-source :fingerprint-p #'probe-fingerprint-p "linacs-core"
    :type '(member t nil)
    :doc "T if a USB fingerprint reader is present")
  (register-fact-source :container-p #'probe-container-p "linacs-core"
    :type '(member t nil)
    :doc "T if running inside a container")
  (register-fact-source :toolbox-p #'probe-toolbox-p "linacs-core"
    :type '(member t nil)
    :doc "T if toolbox or podman binary is on PATH (containerised CLI tools)")
  (register-fact-source :in-toolbox-p #'probe-in-toolbox-p "linacs-core"
    :type '(member t nil)
    :doc "T if running inside a toolbox container ($TOOLBOX_PATH is set)")
  (register-fact-source :flatpak-p #'probe-flatpak-p "linacs-core"
    :type '(member t nil)
    :doc "T if flatpak binary is on PATH")
  (register-fact-source :podman-p #'probe-podman-p "linacs-core"
    :type '(member t nil)
    :doc "T if podman binary is on PATH (rootless containers)")
  (register-fact-source :appimage-p #'probe-appimage-p "linacs-core"
    :type '(member t nil)
    :doc "T if FUSE is available (AppImages can execute)")
  (register-fact-source :sys-vendor #'probe-sys-vendor "linacs-core"
    :type '(or string (member :unknown))
    :doc "System vendor string from DMI")
  (register-fact-source :product-name #'probe-product-name "linacs-core"
    :type '(or string (member :unknown))
    :doc "Product name string from DMI"))
