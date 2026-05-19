;;; init.el -*- lexical-binding: t; -*-

(setq user-full-name "Atalie"
      inhibit-startup-screen t
      initial-scratch-message nil
      ring-bell-function #'ignore
      use-short-answers t
      read-process-output-max (* 1024 1024)
      custom-file (expand-file-name "custom.el" user-emacs-directory)
      backup-directory-alist `(("." . ,(expand-file-name "backups/" user-emacs-directory)))
      auto-save-file-name-transforms `((".*" ,(expand-file-name "auto-save/" user-emacs-directory) t)))

(when (file-exists-p custom-file)
  (load custom-file nil t))

(defvar elpaca-installer-version 0.12)
(defvar elpaca-directory (expand-file-name "elpaca/" user-emacs-directory))
(defvar elpaca-builds-directory (expand-file-name "builds/" elpaca-directory))
(defvar elpaca-sources-directory (expand-file-name "sources/" elpaca-directory))
(defvar elpaca-order
  '(elpaca :repo "https://github.com/progfolio/elpaca.git"
           :ref nil
           :depth 1
           :inherit ignore
           :files (:defaults "elpaca-test.el" (:exclude "extensions"))
           :build (:not elpaca-activate)))
(let* ((repo (expand-file-name "elpaca/" elpaca-sources-directory))
       (build (expand-file-name "elpaca/" elpaca-builds-directory))
       (order (cdr elpaca-order))
       (default-directory repo))
  (add-to-list 'load-path repo)
  (when (file-exists-p build)
    (add-to-list 'load-path build))
  (unless (file-exists-p repo)
    (make-directory repo t)
    (when (< emacs-major-version 28)
      (error "Elpaca requires Emacs 28 or newer"))
    (unless (zerop (call-process "git" nil "*elpaca-bootstrap*" t
                                 "clone" "--depth" "1"
                                 (plist-get order :repo) repo))
      (error "Elpaca bootstrap failed; see *elpaca-bootstrap*")))
  (unless (file-exists-p build)
    (make-directory build t)
    (let ((default-directory repo))
      (unless (zerop (call-process emacs nil "*elpaca-bootstrap*" t
                                   "-Q" "--batch" "-L" "." "--eval"
                                   "(byte-recompile-directory \".\" 0 'force)"))
        (error "Elpaca build failed; see *elpaca-bootstrap*"))))
  (unless (require 'elpaca-autoloads nil t)
    (require 'elpaca)
    (elpaca-generate-autoloads "elpaca" repo)
    (let ((load-source-file-function nil))
      (load (expand-file-name "elpaca-autoloads.el" repo) nil t)))
  (add-hook 'after-init-hook #'elpaca-process-queues)
  (elpaca (elpaca :repo "https://github.com/progfolio/elpaca.git"
                  :ref nil
                  :depth 1
                  :inherit ignore
                  :files (:defaults "elpaca-test.el" (:exclude "extensions"))
                  :build (:not elpaca-activate))))

(elpaca elpaca-use-package
  (elpaca-use-package-mode))
(setq use-package-always-ensure t)
(elpaca-wait)

(use-package emacs
  :ensure nil
  :init
  (setq-default indent-tabs-mode nil
                tab-width 2
                fill-column 100)
  (setq enable-recursive-minibuffers t
        read-extended-command-predicate #'command-completion-default-include-p
        completion-ignore-case t
        read-file-name-completion-ignore-case t
        read-buffer-completion-ignore-case t)
  :config
  (global-auto-revert-mode 1)
  (savehist-mode 1)
  (save-place-mode 1)
  (recentf-mode 1)
  (which-key-mode 1)
  (setq which-key-idle-delay 0.35)
  (when-let ((grammar-dir (getenv "EMACS_TREE_SITTER_GRAMMAR_DIR")))
    (when (file-directory-p grammar-dir)
      (add-to-list 'treesit-extra-load-path grammar-dir)))
  (when (executable-find "gls")
    (setq insert-directory-program "gls"))
  (setq major-mode-remap-alist
        '((bash-mode . bash-ts-mode)
          (css-mode . css-ts-mode)
          (js-mode . js-ts-mode)
          (js-json-mode . json-ts-mode)
          (python-mode . python-ts-mode)
          (rust-mode . rust-ts-mode)
          (typescript-mode . typescript-ts-mode)
          (yaml-mode . yaml-ts-mode))))

(use-package compat
  :ensure (:wait t))

(use-package transient
  :ensure (:wait t))

(use-package ef-themes
  :ensure (:host github
           :repo "protesilaos/ef-themes"
           :files ("*.el" "themes/*.el"))
  :config
  (setq ef-themes-to-toggle '(ef-dream ef-light)
        ef-themes-mixed-fonts t
        ef-themes-variable-pitch-ui t)
  (load-theme 'ef-dream t))

(use-package nerd-icons)

(use-package doom-modeline
  :hook (after-init . doom-modeline-mode)
  :custom
  (doom-modeline-icon t)
  (doom-modeline-major-mode-icon t)
  (doom-modeline-buffer-file-name-style 'truncate-with-project))

(use-package markdown-mode
  :mode (("\\.md\\'" . markdown-mode)
         ("\\.markdown\\'" . markdown-mode)))

(use-package nix-ts-mode
  :mode "\\.nix\\'")

(use-package meow
  :demand t
  :custom
  (meow-use-clipboard t)
  (meow-keypad-leader-dispatch "C-c")
  :config
  (defun dotfiles-meow-setup ()
    (setq meow-cheatsheet-layout meow-cheatsheet-layout-qwerty)
    (meow-motion-overwrite-define-key
     '("j" . meow-next)
     '("k" . meow-prev)
     '("<escape>" . ignore))
    (meow-leader-define-key
     '("SPC" . execute-extended-command)
     '("/" . consult-ripgrep)
     '("." . find-file)
     '("b" . consult-buffer)
     '("f" . find-file)
     '("g" . magit-status)
     '("p" . project-prefix-map)
     '("x" . execute-extended-command))
    (meow-normal-define-key
     '("0" . meow-expand-0)
     '("9" . meow-expand-9)
     '("8" . meow-expand-8)
     '("7" . meow-expand-7)
     '("6" . meow-expand-6)
     '("5" . meow-expand-5)
     '("4" . meow-expand-4)
     '("3" . meow-expand-3)
     '("2" . meow-expand-2)
     '("1" . meow-expand-1)
     '("-" . negative-argument)
     '(";" . meow-reverse)
     '("," . meow-inner-of-thing)
     '("." . meow-bounds-of-thing)
     '("[" . meow-beginning-of-thing)
     '("]" . meow-end-of-thing)
     '("a" . meow-append)
     '("A" . meow-open-below)
     '("b" . meow-back-word)
     '("B" . meow-back-symbol)
     '("c" . meow-change)
     '("d" . meow-delete)
     '("D" . meow-backward-delete)
     '("e" . meow-next-word)
     '("E" . meow-next-symbol)
     '("f" . meow-find)
     '("g" . meow-cancel-selection)
     '("G" . meow-grab)
     '("h" . meow-left)
     '("H" . meow-left-expand)
     '("i" . meow-insert)
     '("I" . meow-open-above)
     '("j" . meow-next)
     '("J" . meow-next-expand)
     '("k" . meow-prev)
     '("K" . meow-prev-expand)
     '("l" . meow-right)
     '("L" . meow-right-expand)
     '("m" . meow-join)
     '("n" . meow-search)
     '("o" . meow-block)
     '("O" . meow-to-block)
     '("p" . meow-yank)
     '("q" . meow-quit)
     '("Q" . meow-goto-line)
     '("r" . meow-replace)
     '("R" . meow-swap-grab)
     '("s" . meow-kill)
     '("t" . meow-till)
     '("u" . meow-undo)
     '("U" . meow-undo-in-selection)
     '("v" . meow-visit)
     '("w" . meow-mark-word)
     '("W" . meow-mark-symbol)
     '("x" . meow-line)
     '("X" . meow-goto-line)
     '("y" . meow-save)
     '("Y" . meow-sync-grab)
     '("z" . meow-pop-selection)
     '("'" . repeat)
     '("<escape>" . ignore)))
  (dotfiles-meow-setup)
  (meow-global-mode 1))

(use-package vertico
  :init
  (vertico-mode 1))

(use-package marginalia
  :after vertico
  :init
  (marginalia-mode 1))

(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles partial-completion)))))

(use-package consult
  :bind (("C-s" . consult-line)
         ("C-x b" . consult-buffer)
         ("M-y" . consult-yank-pop)
         ("M-g g" . consult-goto-line)
         ("M-g i" . consult-imenu)
         ("M-g r" . consult-ripgrep)))

(use-package embark
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim)
         ("C-h B" . embark-bindings))
  :init
  (setq prefix-help-command #'embark-prefix-help-command))

(use-package embark-consult
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))

(use-package corfu
  :init
  (global-corfu-mode 1)
  :custom
  (corfu-auto t)
  (corfu-cycle t)
  (corfu-preview-current nil)
  (corfu-quit-no-match 'separator))

(use-package cape
  :init
  (add-to-list 'completion-at-point-functions #'cape-file)
  (add-to-list 'completion-at-point-functions #'cape-dabbrev))

(use-package kind-icon
  :after corfu
  :custom
  (kind-icon-default-face 'corfu-default)
  :config
  (add-to-list 'corfu-margin-formatters #'kind-icon-margin-formatter))

(use-package project
  :ensure nil
  :custom
  (project-switch-commands '((project-find-file "Find file")
                             (project-dired "Dired")
                             (project-eshell "Eshell")
                             (magit-project-status "Magit"))))

(use-package xref
  :ensure nil
  :custom
  (xref-search-program 'ripgrep))

(use-package eglot
  :ensure nil
  :hook ((bash-ts-mode
          css-ts-mode
          html-mode
          js-ts-mode
          json-ts-mode
          nix-ts-mode
          python-ts-mode
          rust-ts-mode
          typescript-ts-mode
          yaml-ts-mode) . eglot-ensure)
  :custom
  (eglot-autoshutdown t)
  (eglot-confirm-server-initiated-edits nil))

(use-package flymake
  :ensure nil
  :hook (prog-mode . flymake-mode))

(use-package dired
  :ensure nil
  :commands (dired dired-jump)
  :custom
  (dired-dwim-target t)
  (dired-listing-switches "-alh --group-directories-first")
  :hook (dired-mode . dired-hide-details-mode))

(use-package dired-x
  :ensure nil
  :after dired)

(use-package diredfl
  :hook (dired-mode . diredfl-mode))

(use-package dired-subtree
  :after dired
  :bind (:map dired-mode-map
              ("TAB" . dired-subtree-toggle)
              ("<backtab>" . dired-subtree-remove)))

(use-package nerd-icons-dired
  :hook (dired-mode . nerd-icons-dired-mode))

(use-package org
  :ensure nil
  :custom
  (org-hide-emphasis-markers t)
  (org-startup-indented t)
  (org-pretty-entities t)
  :hook ((org-mode . visual-line-mode)
         (org-mode . variable-pitch-mode)))

(use-package org-modern
  :hook (org-mode . org-modern-mode))

(use-package org-appear
  :hook (org-mode . org-appear-mode)
  :custom
  (org-appear-autoemphasis t)
  (org-appear-autolinks t)
  (org-appear-autosubmarkers t))

(use-package visual-fill-column
  :hook (org-mode . visual-fill-column-mode)
  :custom
  (visual-fill-column-width 96)
  (visual-fill-column-center-text t))

(setq display-buffer-alist
      '(("\\*\\(?:Help\\|Apropos\\|info\\|Warnings\\)\\*"
         (display-buffer-reuse-window display-buffer-in-side-window)
         (side . right)
         (window-width . 0.35))
        ("\\*\\(?:compilation\\|grep\\|Flymake diagnostics\\)\\*"
         (display-buffer-reuse-window display-buffer-at-bottom)
         (window-height . 0.25))))

(use-package popper
  :bind (("C-`" . popper-toggle)
         ("M-`" . popper-cycle))
  :custom
  (popper-reference-buffers
   '("\\*Messages\\*"
     "\\*Warnings\\*"
     "\\*Help\\*"
     "\\*compilation\\*"
     "\\*Flymake diagnostics.*\\*"
     "^\\*eshell.*\\*$"
     "^\\*shell.*\\*$"))
  :init
  (popper-mode 1)
  (popper-echo-mode 1))

(use-package dashboard
  :custom
  (dashboard-startup-banner 'official)
  (dashboard-center-content t)
  (dashboard-items '((recents . 8)
                     (projects . 8)))
  :config
  (dashboard-setup-startup-hook))

(use-package magit
  :commands (magit-status magit-project-status))

(elpaca-wait)
