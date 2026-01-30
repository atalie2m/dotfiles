;;; my-meow.el --- modal editing with Meow  -*- lexical-binding: t; -*-

(use-package meow
  :config
  (defun my/meow-setup ()
    (setq meow-cheatsheet-layout meow-cheatsheet-layout-qwerty)

    ;; MOTION state
    (meow-motion-overwrite-define-key
     '("j" . meow-next)
     '("k" . meow-prev)
     '("<escape>" . ignore))

    ;; LEADER (Keypad)
    (meow-leader-define-key
     '("?" . meow-cheatsheet)
     '("x" . execute-extended-command)
     '("f" . find-file)
     '("b" . switch-to-buffer)
     '("s" . save-buffer)
     '("k" . kill-current-buffer)
     '("t" . treemacs))

    ;; NORMAL state: Minimal Vim-like set
    (meow-normal-define-key
     '("i" . meow-insert)
     '("a" . meow-append)
     '("A" . meow-open-below)
     '("I" . meow-open-above)
     '("h" . meow-left)
     '("j" . meow-next)
     '("k" . meow-prev)
     '("l" . meow-right)
     '("w" . meow-next-word)
     '("b" . meow-back-word)
     '("0" . meow-beginning-of-thing)
     '("$" . meow-end-of-thing)
     '("x" . meow-delete)
     '("y" . meow-save)
     '("p" . meow-yank)
     '("v" . meow-visit)
     '("V" . meow-line)
     '("<escape>" . ignore)))

  (my/meow-setup)
  (meow-global-mode 1))

;; Shortcut for cheatsheet
(global-set-key (kbd "C-h M") #'meow-cheatsheet)

(provide 'my-meow)
;;; my-meow.el ends here
