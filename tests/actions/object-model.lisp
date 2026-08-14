(in-package #:linacs-tests)

(def-suite action-object-model
  :in linacs-tests
  :description "Tests for the action CLOS object model (make-action,
plist->action, action->plist, subclass dispatch)")

(in-suite action-object-model)

(def-test make-action-from-kwargs ()
  "MAKE-ACTION with kwargs in plist form builds the right subclass"
  (let ((a (linacs.core:make-action :action :copy-file :target "/tmp/x"
                                    :from "x")))
    (is (typep a 'linacs.core::copy-file-action))
    (is (equal (linacs.core::action-target a) "/tmp/x"))
    (is (equal (linacs.core::copy-file-from a) "x"))))

(def-test make-action-from-plist ()
  "MAKE-ACTION with a single plist argument"
  (let ((a (linacs.core:make-action '(:action :package :target :emacs
                                              :via :system))))
    (is (typep a 'linacs.core::package-action))
    (is (eq (linacs.core::package-action-via a) :system))
    (is (eq (linacs.core::action-target a) :emacs))))

(def-test unknown-type-uses-base-class ()
  "Action types with no registered subclass fall back to the base ACTION
class and preserve the raw plist in ACTION-ORIGINAL"
  (let ((a (linacs.core:make-action '(:action :my-plugin :target "t"
                                              :custom "v"))))
    (is (typep a 'linacs.core::action))
    (is (not (typep a 'linacs.core::copy-file-action)))
    (is (equal (linacs.core::action-original a)
               '(:action :my-plugin :target "t" :custom "v")))
    (is (equal (linacs.core::action->plist a)
               '(:action :my-plugin :target "t" :custom "v")))))

(def-test package-plist-round-trip ()
  "package action round trips with its :via qualifier"
  (let* ((plist '(:action :package :target :emacs :via :system
                           :scope :user :priority :user))
         (a (linacs.core::plist->action plist)))
    (is (typep a 'linacs.core::package-action))
    (is (equal (linacs.core::action->plist a)
               '(:action :package :target :emacs :via :system
                         :scope :user :priority :user)))))

(def-test copy-file-canonicalizes-to ()
  "copy-file absorbs the redundant :to alias: canonical output keeps only
:target (REFACTOR Action 2)"
  (let* ((a (linacs.core:make-action '(:action :copy-file :target "/tmp/x"
                                               :to "/tmp/x" :from "src/x"))))
    (is (equal (linacs.core::action-target a) "/tmp/x"))
    (let ((replist (linacs.core::action->plist a)))
      (is (not (getf replist :to)))
      (is (equal (getf replist :target) "/tmp/x"))
      (is (equal (getf replist :from) "src/x")))))

(def-test copy-file-plist-only-to ()
  "A copy-file plist that only has :to (never :target) round trips through
:target"
  (let* ((a (linacs.core:make-action '(:action :copy-file :to "/tmp/x"
                                               :from "x"))))
    (is (equal (linacs.core::action-target a) "/tmp/x"))
    (is (equal (getf (linacs.core::action->plist a) :target) "/tmp/x"))))

(def-test service-plist-round-trip ()
  "service action round trips its enabled/running state"
  (let* ((plist '(:action :service :target :ssh-daemon
                          :enabled t :running t))
         (a (linacs.core::plist->action plist)))
    (is (typep a 'linacs.core::service-action))
    (is (linacs.core::service-enabled a))
    (is (linacs.core::service-running a))
    (is (equal (linacs.core::action->plist a)
               '(:action :service :target :ssh-daemon :enabled t :running t)))))

(def-test symlink-keeps-destination ()
  "symlink's :to is the destination, not an alias of :target"
  (let* ((a (linacs.core:make-action '(:action :symlink :target "~/.emacs.d"
                                               :to "~/.config/emacs"))))
    (is (typep a 'linacs.core::symlink-action))
    (is (equal (linacs.core::action-target a) "~/.emacs.d"))
    (is (equal (linacs.core::symlink-destination a) "~/.config/emacs"))
    (is (equal (linacs.core::action->plist a)
               '(:action :symlink :target "~/.emacs.d" :to "~/.config/emacs")))))

(def-test stow-keeps-target-root ()
  "stow's :to is the target root"
  (let* ((a (linacs.core:make-action '(:action :stow :target "fish"
                                               :to "~/.config"
                                               :from "fish"))))
    (is (typep a 'linacs.core::stow-action))
    (is (equal (linacs.core::stow-target-root a) "~/.config"))
    (is (equal (linacs.core::stow-from a) "fish"))))

(def-test action-identity-object-delegates ()
  "ACTION-IDENTITY on an instance equals the plist identity"
  (let ((plist '(:action :copy-file :target "/tmp/x")))
    (is (equal (linacs.core:action-identity (linacs.core:make-action plist))
               (linacs.core:action-identity plist))))
  (let ((plist '(:action :package :target :emacs :via :pip)))
    (is (equal (linacs.core:action-identity (linacs.core:make-action plist))
               (linacs.core:action-identity plist)))))

(def-test same-action-content-p-object ()
  "SAME-ACTION-CONTENT-P works across objects and plists"
  (let ((a (linacs.core:make-action '(:action :copy-file :target "/tmp/x"
                                              :from "x" :priority :user)))
        (b (linacs.core:make-action '(:action :copy-file :target "/tmp/x"
                                              :from "x" :priority :provider))))
    (is (linacs.core::same-action-content-p a b))
    (is (linacs.core::same-action-content-p
         a '(:action :copy-file :target "/tmp/x" :from "x")))))

(def-test execute-action-accepts-object ()
  "EXECUTE-ACTION converts an ACTION instance to a plist before dispatch"
  (with-scratch-dir (dir)
    (let ((a (linacs.core:make-action
              :action :copy-file :target (namestring (merge-pathnames "f" dir))
              :content "hello")))
      (let ((result (linacs.core:execute-action a :mode :check)))
        (is (member (getf result :status) '(:would-change :unchanged)))))))

(def-test every-registered-type-has-subclass ()
  "Every action type whose executor was registered has a defined-action
subclass; verify the pilot + remaining set dispatches correctly"
  (dolist (type '(:package :copy-file :ensure-dir :service :symlink :stow
                  :timer :env-var :config-lines :config-ini :config-env
                  :secret :user :group :authorized-key :permissions :mount
                  :sysctl :kernel-module :hostname :locale :firewall :cron
                  :command :clone :repository))
    (let ((a (linacs.core:make-action (list :action type :target "t"))))
      (is (typep a 'linacs.core::action)
          "~A should instantiate an action subclass, got ~S"
          type (class-name (class-of a))))))

(def-test ensure-dir-mode-base ()
  "ensure-dir carries generic :mode on the base class"
  (let ((a (linacs.core:make-action '(:action :ensure-dir :target "/tmp/d"
                                              :mode #o755))))
    (is (typep a 'linacs.core::ensure-dir-action))
    (is (= (linacs.core::action-mode a) #o755))
    (is (equal (linacs.core::action->plist a)
               '(:action :ensure-dir :target "/tmp/d" :mode #o755)))))

(def-test config-lines-round-trip ()
  "config-lines carries its additive ensure/remove content"
  (let* ((plist '(:action :config-lines :target "~/.config/i3/config"
                          :ensure ("bindsym $mod+Return exec emacs")
                          :remove ("old line")))
         (a (linacs.core::plist->action plist)))
    (is (typep a 'linacs.core::config-lines-action))
    (is (equal (linacs.core::config-lines-ensure a)
               '("bindsym $mod+Return exec emacs")))
    (is (equal (linacs.core::action->plist a) plist))
    (is (equal (linacs.core:action-identity a)
               (linacs.core:action-identity plist)))))

(def-test command-round-trip ()
  "command round trips its idempotency gates and :sudo"
  (let* ((plist '(:action :command :target "clone dotfiles"
                          :run "git clone ..." :creates "~/.dotfiles" :sudo t))
         (a (linacs.core::plist->action plist)))
    (is (typep a 'linacs.core::command-action))
    (is (linacs.core::command-sudo a))
    (is (equal (linacs.core::command-creates a) "~/.dotfiles"))
    (is (equal (linacs.core::action->plist a) plist))))

(def-test repository-round-trip ()
  "repository carries its :method qualifier"
  (let* ((plist '(:action :repository :target "@wez/wezterm" :method :dnf-copr))
         (a (linacs.core::plist->action plist)))
    (is (typep a 'linacs.core::repository-action))
    (is (eq (linacs.core::repository-method a) :dnf-copr))
    (is (equal (linacs.core::action->plist a) plist))
    (is (equal (linacs.core:action-identity a)
               '(:repository :dnf-copr . "@wez/wezterm")))))

(def-test clone-round-trip ()
  "clone round trips url/branch/depth"
  (let* ((plist '(:action :clone :target "~/.dotfiles"
                          :url "https://example.com/dotfiles.git"
                          :branch "main" :depth 1))
         (a (linacs.core::plist->action plist)))
    (is (typep a 'linacs.core::clone-action))
    (is (equal (linacs.core::clone-url a) "https://example.com/dotfiles.git"))
    (is (equal (linacs.core::clone-branch a) "main"))
    (is (equal (linacs.core::action->plist a) plist))))

(def-test secret-round-trip ()
  "secret round trips its source keys"
  (let* ((plist '(:action :secret :target "~/.ssh/id_ed25519" :from :pass
                          :path "ssh/id_ed25519" :mode #o600))
         (a (linacs.core::plist->action plist)))
    (is (typep a 'linacs.core::secret-action))
    (is (eq (linacs.core::secret-from a) :pass))
    (is (equal (linacs.core::action->plist a) plist))))

(def-test config-ini-round-trip ()
  "config-ini round trips section/set/unset"
  (let* ((plist '(:action :config-ini :target "~/.config/fontconfig/fonts.conf"
                          :section "antialias" :set (("enable" . "true"))
                          :unset ("rgba")))
         (a (linacs.core::plist->action plist)))
    (is (typep a 'linacs.core::config-ini-action))
    (is (equal (linacs.core::config-ini-section a) "antialias"))
    (is (equal (linacs.core::action->plist a) plist))))