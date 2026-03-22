;;; my-ui.el --- UI settings  -*- lexical-binding: t; -*-

;; Hide the toolbar to keep the title bar thin.
(tool-bar-mode -1)
(add-to-list 'default-frame-alist '(tool-bar-lines . 0))

;; Dark theme (built-in).
(load-theme 'modus-vivendi t)

;; ------------------------------------------------------------
;; Layout: side windows, buffer placement, and spacing

;; Keep common utility buffers in fixed locations.
(setq display-buffer-alist
      (append
       '(
         ;; Right side: help/info
         ("\\*\\(Help\\|Apropos\\|info\\)\\*"
          (display-buffer-reuse-window display-buffer-in-side-window)
          (side . right) (slot . 0)
          (window-width . 0.33)
          (window-parameters . ((no-other-window . t))))

         ;; Bottom panel: logs/builds
         ("\\*\\(compilation\\|Warnings\\|Messages\\|Backtrace\\|Occur\\|grep\\)\\*"
          (display-buffer-reuse-window display-buffer-in-side-window)
          (side . bottom) (slot . 0)
          (window-height . 0.25)
          (window-parameters . ((no-other-window . t))))
         )
       display-buffer-alist))

;; Thin dividers and a bit of frame padding.
(setq window-divider-default-places t
      window-divider-default-right-width 1
      window-divider-default-bottom-width 1)
(window-divider-mode 1)
(add-to-list 'default-frame-alist '(internal-border-width . 10))

;; Subtle margins for main editing windows (skip side windows).
(defvar my/window-margin-width 1
  "Margin width for main editing windows.")

(defun my/apply-window-margins ()
  "Apply margins to non-minibuffer, non-side windows."
  (dolist (win (window-list))
    (unless (or (window-minibuffer-p win)
                (window-parameter win 'window-side))
      (let* ((margins (window-margins win))
             (left (car margins))
             (right (cdr margins)))
        (when (or (not (equal left my/window-margin-width))
                  (not (equal right my/window-margin-width)))
          (set-window-margins win my/window-margin-width my/window-margin-width))))))

(add-hook 'after-init-hook #'my/apply-window-margins)
(add-hook 'window-configuration-change-hook #'my/apply-window-margins)

(provide 'my-ui)
;;; my-ui.el ends here
