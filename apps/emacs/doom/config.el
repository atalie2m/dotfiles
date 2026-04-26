;;; config.el -*- lexical-binding: t; -*-

;; macOS modifiers: Command=Super, Left Option=None, Right Option=Meta.
(setq ns-command-modifier 'super
      ns-alternate-modifier 'none
      ns-right-alternate-modifier 'meta)

(let ((name (getenv "GIT_AUTHOR_NAME"))
      (mail (getenv "GIT_AUTHOR_EMAIL")))
  (when (and name (not (string= name "")))
    (setq user-full-name name))
  (when (and mail (not (string= mail "")))
    (setq user-mail-address mail)))

(setq doom-theme 'doom-one
      doom-font (font-spec :family "JetBrainsMono Nerd Font" :size 14)
      doom-variable-pitch-font (font-spec :family "Roboto" :size 15)
      display-line-numbers-type 'relative)

(setq confirm-kill-emacs nil
      auto-save-default t
      make-backup-files nil
      create-lockfiles nil)

(setq-default tab-width 4
              indent-tabs-mode nil
              fill-column 100)

(global-subword-mode 1)
(save-place-mode 1)

(defun my/add-exec-path (path)
  "Add PATH to `exec-path' and the process environment when it exists."
  (when (file-directory-p path)
    (add-to-list 'exec-path path)
    (setenv "PATH" (concat path ":" (or (getenv "PATH") "")))))

(dolist (path (list "/run/current-system/sw/bin"
                    (expand-file-name "~/.nix-profile/bin")
                    (expand-file-name "~/.local/state/nix/profile/bin")))
  (my/add-exec-path path))

;; macOS/BSD ls does not support GNU ls --dired markers.
(setq dired-use-ls-dired nil)

(after! meow
  (dolist (mode '(magit-status-mode
                  magit-log-mode
                  magit-diff-mode
                  magit-revision-mode
                  forge-topic-mode
                  dired-mode
                  dirvish-mode
                  org-agenda-mode
                  help-mode
                  helpful-mode
                  Info-mode
                  special-mode
                  compilation-mode
                  grep-mode
                  eat-mode
                  eshell-mode
                  term-mode
                  vterm-mode
                  pdf-view-mode))
    (add-to-list 'meow-mode-state-list `(,mode . emacs)))

  (dolist (mode '(org-mode markdown-mode text-mode))
    (add-to-list 'meow-expand-exclude-mode-list mode)))

(after! vertico
  (setq vertico-cycle t
        vertico-resize nil))

(after! orderless
  (setq completion-styles '(orderless basic)
        completion-category-defaults nil
        completion-category-overrides '((file (styles partial-completion)))))

(after! consult
  (setq consult-preview-key '(:debounce 0.2 any)))

(after! corfu
  (setq corfu-auto t
        corfu-auto-delay 0.12
        corfu-auto-prefix 2
        corfu-cycle t
        corfu-preselect 'prompt
        corfu-preview-current nil
        corfu-on-exact-match nil))

(after! cape
  (add-to-list 'completion-at-point-functions #'cape-file)
  (add-to-list 'completion-at-point-functions #'cape-dabbrev)
  (add-to-list 'completion-at-point-functions #'cape-keyword))

(after! eglot
  (setq eglot-autoshutdown t
        eglot-events-buffer-size 0
        eglot-send-changes-idle-time 0.3))

(after! flymake
  (setq flymake-no-changes-timeout 0.5
        flymake-start-on-save-buffer t
        flymake-start-on-flymake-mode t))

(after! eldoc
  (setq eldoc-idle-delay 0.2
        eldoc-echo-area-use-multiline-p nil))

(after! apheleia
  (apheleia-global-mode +1)
  (dolist (mode '(org-mode markdown-mode text-mode))
    (add-to-list '+format-on-save-disabled-modes mode)))

(after! magit
  (setq magit-save-repository-buffers 'dontask
        magit-display-buffer-function
        #'magit-display-buffer-same-window-except-diff-v1))

(map! :leader
      (:prefix ("g" . "git")
       "g" #'magit-status
       "b" #'magit-blame-addition
       "l" #'magit-log-current
       "f" #'magit-file-dispatch))

(use-package! dirvish
  :commands (dirvish dirvish-dwim)
  :init
  (dirvish-override-dired-mode)
  :config
  (setq dirvish-attributes
        '(vc-state subtree-state nerd-icons collapse git-msg file-time file-size)))

(map! :leader
      (:prefix ("f" . "file")
       "d" #'dirvish
       "j" #'dired-jump))

(map! :leader
      (:prefix ("s" . "search")
       "s" #'consult-line
       "S" #'consult-ripgrep
       "b" #'consult-buffer
       "i" #'consult-imenu
       "p" #'consult-project-buffer))

(map! :leader
      (:prefix ("j" . "jump")
       "j" #'avy-goto-char-timer
       "l" #'avy-goto-line
       "w" #'avy-goto-word-1))

(use-package! vundo
  :commands vundo
  :config
  (setq vundo-glyph-alist vundo-unicode-symbols
        vundo-compact-display t))

(use-package! expand-region
  :commands er/expand-region)

(use-package! whole-line-or-region
  :hook (doom-first-buffer . whole-line-or-region-global-mode))

(use-package! crux
  :commands (crux-duplicate-current-line-or-region
             crux-smart-open-line
             crux-kill-whole-line))

(use-package! pulsar
  :hook (doom-first-buffer . pulsar-global-mode)
  :config
  (setq pulsar-pulse t
        pulsar-delay 0.055))

(map! :leader
      (:prefix ("," . "edit")
       "e" #'er/expand-region
       "d" #'crux-duplicate-current-line-or-region
       "o" #'crux-smart-open-line
       "u" #'vundo
       (:prefix ("a" . "ai")
        "a" #'gptel
        "s" #'gptel-send
        "m" #'gptel-menu
        "g" #'gptel-agent
        "d" #'aidermacs-transient-menu)))

(use-package! eat
  :commands (eat eat-project))

(map! :leader
      (:prefix ("o" . "open")
       "t" #'eat
       "T" #'eat-project))

(after! org
  (setq org-directory "~/org/"
        org-agenda-files '("~/org/")
        org-log-done 'time
        org-startup-indented t
        org-hide-emphasis-markers t
        org-return-follows-link t
        org-todo-keywords
        '((sequence "TODO(t)" "NEXT(n)" "WAIT(w)" "|" "DONE(d)" "CANCEL(c)"))))

(after! org-roam
  (setq org-roam-directory "~/org/roam/")
  (make-directory org-directory t)
  (make-directory org-roam-directory t)
  (org-roam-db-autosync-mode 1))

(map! :leader
      (:prefix ("n" . "notes")
       "f" #'org-roam-node-find
       "i" #'org-roam-node-insert
       "c" #'org-capture
       "a" #'org-agenda))

(use-package! gptel
  :commands (gptel gptel-send gptel-menu)
  :config
  (setq gptel-default-mode 'org-mode
        gptel-use-tools nil
        gptel-include-reasoning nil))

(use-package! gptel-agent
  :after gptel
  :commands gptel-agent)

(use-package! aidermacs
  :commands (aidermacs-run aidermacs-transient-menu)
  :config
  (setq aidermacs-backend 'comint))
