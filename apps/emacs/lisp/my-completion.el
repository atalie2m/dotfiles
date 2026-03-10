;;; my-completion.el --- completion UI  -*- lexical-binding: t; -*-

(use-package vertico
  :init
  (vertico-mode 1))

(use-package vertico-multiform
  :after vertico
  :ensure nil
  :init
  (vertico-multiform-mode 1)
  :config
  (setq vertico-multiform-commands
        '((consult-line buffer)
          (consult-ripgrep buffer)
          (consult-git-grep buffer))))

(use-package vertico-buffer
  :after vertico
  :ensure nil
  :custom
  (vertico-buffer-display-action
   '(display-buffer-in-side-window
     (side . bottom) (slot . 0)
     (window-height . 0.33))))

(use-package orderless
  :init
  (setq completion-styles '(orderless basic)
        completion-category-defaults nil
        completion-category-overrides '((file (styles partial-completion)))))

(use-package consult
  :bind (("C-s" . consult-line)
         ("C-x b" . consult-buffer)
         ("C-c g" . consult-ripgrep)))

(use-package marginalia
  :init
  (marginalia-mode 1))

(use-package embark
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim)
         ("C-h B" . embark-bindings))
  :init
  (setq prefix-help-command #'embark-prefix-help-command))

(use-package which-key
  :init
  (which-key-mode 1))

(use-package corfu
  :init
  (global-corfu-mode 1))

(use-package cape
  :init
  (add-to-list 'completion-at-point-functions #'cape-file)
  (add-to-list 'completion-at-point-functions #'cape-dabbrev))

(use-package tempel
  :bind (("M-+" . tempel-complete))
  :init
  (defun my/tempel-setup-capf ()
    "Make `tempel-expand' the first CAPF in the current buffer."
    (let ((capfs (copy-sequence completion-at-point-functions)))
      (setq-local completion-at-point-functions
                  (cons #'tempel-expand
                        (delq #'tempel-expand capfs)))))
  (dolist (hook '(prog-mode-hook text-mode-hook conf-mode-hook))
    (add-hook hook #'my/tempel-setup-capf)))

(provide 'my-completion)
;;; my-completion.el ends here
