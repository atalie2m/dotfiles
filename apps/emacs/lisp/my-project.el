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

(provide 'my-project)
;;; my-project.el ends here
