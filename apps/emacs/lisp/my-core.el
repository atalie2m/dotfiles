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

;; ------------------------------------------------------------
;; package.el: GNU + NonGNU (Meow is on NonGNU)
(require 'package)
(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))
(unless (bound-and-true-p package--initialized)
  (package-initialize))

(defun my/ensure-package (pkg)
  "Install PKG if not installed."
  (unless (package-installed-p pkg)
    (unless package-archive-contents
      (package-refresh-contents))
    (package-install pkg)))

;; use-package is bundled in recent Emacs, but ensure it exists.
(my/ensure-package 'use-package)
(require 'use-package)
(setq use-package-always-ensure t)

(provide 'my-core)
;;; my-core.el ends here
