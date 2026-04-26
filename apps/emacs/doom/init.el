;;; init.el -*- lexical-binding: t; -*-

(custom-set-faces
 '(warning ((t (:foreground "#ECBE7B")))))

(doom! :input
       japanese

       :completion
       (vertico +icons)
       (corfu +icons +orderless +dabbrev)

       :ui
       doom
       doom-dashboard
       hl-todo
       modeline
       icons
       nav-flash
       ophints
       (popup +defaults)
       unicode
       vc-gutter
       window-select
       workspaces

       :editor
       (meow +qwerty)
       file-templates
       fold
       snippets
       (format +onsave)

       :emacs
       dired
       electric
       ibuffer
       vc

       :checkers
       (syntax +flymake)
       spell

       :tools
       direnv
       editorconfig
       (eval +overlay)
       llm
       lookup
       (lsp +eglot)
       (magit +forge)
       tree-sitter

       :os
       macos
       tty

       :term
       eshell

       :lang
       emacs-lisp
       markdown
       (org +roam2)
       (python +lsp +tree-sitter)
       (rust +lsp +tree-sitter)
       (javascript +lsp +tree-sitter)
       (web +lsp +tree-sitter)
       (nix +lsp +tree-sitter)
       sh
       yaml
       json

       :config
       (default +bindings +smartparens))
