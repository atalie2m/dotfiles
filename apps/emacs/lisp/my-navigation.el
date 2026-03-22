;;; my-navigation.el --- navigation and transient buffers  -*- lexical-binding: t; -*-

(use-package avy
  :bind (("C-:" . avy-goto-char-timer)))

(use-package ace-window
  :bind (("M-o" . ace-window))
  :custom
  (aw-keys '(?a ?s ?d ?f ?g ?h ?j ?k ?l)))

(use-package popper
  :bind (("C-`" . popper-toggle)
         ("M-`" . popper-cycle))
  :init
  (setq popper-reference-buffers
        '("\\*Messages\\*"
          "\\*Warnings\\*"
          "\\*compilation\\*"
          "\\*Backtrace\\*"
          "\\*Help\\*"
          "\\*Embark Collect.*\\*"
          "\\*Async Shell Command\\*"
          "\\*eshell\\*"
          "\\*shell\\*"
          "\\*vterm\\*"
          help-mode
          compilation-mode))
  :config
  (popper-mode 1)
  (popper-echo-mode 1))

(use-package vundo
  :bind (("C-x u" . vundo)))

(provide 'my-navigation)
;;; my-navigation.el ends here
