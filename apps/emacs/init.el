;;; init.el --- minimal modern Emacs + Meow  -*- lexical-binding: t; -*-

(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

(require 'my-core)
(require 'my-ui)
(require 'my-completion)
(require 'my-navigation)
(require 'my-meow)
(require 'my-project)

(provide 'init)
;;; init.el ends here
