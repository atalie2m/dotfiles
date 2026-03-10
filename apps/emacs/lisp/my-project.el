;;; my-project.el --- project tools  -*- lexical-binding: t; -*-

(use-package treemacs
  :defer t
  :init
  (setq treemacs-width 35)
  :config
  (add-to-list 'display-buffer-alist
               '("\\*Treemacs.*\\*"
                 (display-buffer-in-side-window)
                 (side . left) (slot . 0)
                 (window-width . 35)
                 (window-parameters . ((no-other-window . t)
                                       (no-delete-other-windows . t)
                                       (window-size-fixed . width))))))

(use-package magit
  :bind (("C-x g" . magit-status)))

(use-package eglot
  :ensure nil
  :defer t)

(defvar my/treesit-check-languages
  '(bash c cpp css go html javascript json python rust toml tsx typescript yaml)
  "Languages to check for missing tree-sitter grammars.")

(defun my/treesit-report-missing-grammars ()
  "Report missing grammars from `my/treesit-check-languages'."
  (interactive)
  (cond
   ((not (fboundp 'treesit-available-p))
    (message "This Emacs build does not provide treesit APIs."))
   ((not (treesit-available-p))
    (message "Tree-sitter support is unavailable in this Emacs build."))
   (t
    (let (missing)
      (dolist (lang my/treesit-check-languages)
        (unless (treesit-language-available-p lang)
          (push lang missing)))
      (if missing
          (message "Missing tree-sitter grammars: %s (M-x treesit-install-language-grammar)"
                   (mapconcat #'symbol-name (nreverse missing) ", "))
        (message "All tracked tree-sitter grammars are available."))))))

(use-package treesit-auto
  :if (fboundp 'treesit-available-p)
  :init
  (setq treesit-auto-install nil)
  :config
  (when (treesit-available-p)
    (global-treesit-auto-mode 1)))

(use-package meow-tree-sitter
  :after meow
  :if (fboundp 'treesit-available-p)
  :config
  (when (and (treesit-available-p)
             (fboundp 'meow-tree-sitter-register-defaults))
    (meow-tree-sitter-register-defaults)))

(provide 'my-project)
;;; my-project.el ends here
