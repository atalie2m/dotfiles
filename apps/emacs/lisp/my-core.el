;;; my-core.el --- core settings  -*- lexical-binding: t; -*-

;; macOS modifiers: Command=Super, Left Option=None, Right Option=Meta.
(setq ns-command-modifier 'super
      ns-alternate-modifier 'none
      ns-right-alternate-modifier 'meta)

;; Keep Customize writes out of the read-only Nix store.
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file)
  (load custom-file nil t))

;; Skip the startup screen so you can type immediately in *scratch*.
(setq inhibit-startup-screen t
      inhibit-startup-message t
      initial-scratch-message nil)

;; Built-in quality-of-life modes.
(savehist-mode 1)
(recentf-mode 1)
(global-auto-revert-mode 1)
(electric-pair-mode 1)
(winner-mode 1)
(repeat-mode 1)
(setq tab-bar-show nil)

;; meow-tree-sitter references Meow internals that trigger noisy native-comp
;; warnings. Keep it bytecode-only to avoid startup warning spam.
(let ((deny-pattern "meow-tree-sitter\\.el\\'"))
  (when (boundp 'native-comp-jit-compilation-deny-list)
    (add-to-list 'native-comp-jit-compilation-deny-list deny-pattern))
  (when (boundp 'native-comp-deferred-compilation-deny-list)
    (add-to-list 'native-comp-deferred-compilation-deny-list deny-pattern)))

;; Restore GC thresholds after startup for steady-state performance.
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 64 1024 1024)
                  gc-cons-percentage 0.1)
            (garbage-collect)))

;; Put backups and autosaves under ~/.emacs.d/cache/.
(let* ((cache-dir (expand-file-name "cache/" user-emacs-directory))
       (backup-dir (expand-file-name "backups/" cache-dir))
       (autosave-dir (expand-file-name "autosave/" cache-dir)))
  (dolist (dir (list cache-dir backup-dir autosave-dir))
    (unless (file-directory-p dir)
      (make-directory dir t)))
  (setq backup-directory-alist `(("." . ,backup-dir))
        auto-save-file-name-transforms `((".*" ,autosave-dir t))
        auto-save-list-file-prefix (expand-file-name "saves-" autosave-dir)))

;; Quit behavior on macOS: keep safety prompts for unsaved buffers.
(setq confirm-kill-processes t)
(defun my/quit-emacs-immediately ()
  "Quit Emacs without process prompts, but keep buffer save checks."
  (interactive)
  (let ((confirm-kill-processes nil))
    (kill-emacs)))
(global-set-key (kbd "s-q") #'my/quit-emacs-immediately)

;; Ensure Nix binaries are visible to GUI Emacs.
(let ((nix-paths (list "/run/current-system/sw/bin"
                       (expand-file-name "~/.nix-profile/bin")
                       (expand-file-name "~/.local/state/nix/profile/bin"))))
  (dolist (p nix-paths)
    (when (file-directory-p p)
      (add-to-list 'exec-path p)
      (setenv "PATH" (concat p ":" (getenv "PATH"))))))

;; Load ELisp packages installed declaratively by Nix.
(defun my/add-nix-site-lisp-paths ()
  "Add Nix profile site-lisp trees to `load-path'."
  (dolist (root (list (expand-file-name "~/.nix-profile/share/emacs/site-lisp")
                      (expand-file-name "~/.nix-profile/share/emacs/site-lisp/elpa")
                      (expand-file-name "~/.local/state/nix/profile/share/emacs/site-lisp")
                      (expand-file-name "~/.local/state/nix/profile/share/emacs/site-lisp/elpa")
                      "/run/current-system/sw/share/emacs/site-lisp"
                      "/run/current-system/sw/share/emacs/site-lisp/elpa"))
    (when (file-directory-p root)
      (add-to-list 'load-path root)
      (let ((default-directory root))
        (normal-top-level-add-subdirs-to-load-path)))))

(my/add-nix-site-lisp-paths)

;; ------------------------------------------------------------
;; package.el archives for optional manual installs.
(require 'package)
(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))

(defun my/bootstrap-package-keyring ()
  "Ensure package.el keyring exists before verifying signatures."
  (when package-check-signature
    (let ((gnupg-dir package-gnupghome-dir)
          (pubring-kbx (expand-file-name "pubring.kbx" package-gnupghome-dir))
          (pubring-gpg (expand-file-name "pubring.gpg" package-gnupghome-dir)))
      (unless (file-directory-p gnupg-dir)
        (make-directory gnupg-dir t)
        (set-file-modes gnupg-dir #o700))
      (unless (or (file-exists-p pubring-kbx)
                  (file-exists-p pubring-gpg))
        (condition-case err
            (package-import-keyring)
          (error
           (message "package-import-keyring failed: %s"
                    (error-message-string err))))))))

(my/bootstrap-package-keyring)
(unless (bound-and-true-p package--initialized)
  (package-initialize))

;; Prefer use-package from Nix; fallback to package.el if unavailable.
(unless (require 'use-package nil t)
  (unless package-archive-contents
    (package-refresh-contents))
  (package-install 'use-package))
(require 'use-package)
(setq use-package-always-ensure nil)

(provide 'my-core)
;;; my-core.el ends here
