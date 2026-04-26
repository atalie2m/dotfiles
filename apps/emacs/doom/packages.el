;;; packages.el -*- no-byte-compile: t; -*-

;; doom-meow expects Meow undo to route through Emacs' built-in undo behavior.
(package! undo-fu :disable t)
(package! undo-fu-session :disable t)

;; File manager
(package! dirvish)

;; Editing QoL
(package! vundo)
(package! jinx)
(package! crux)
(package! whole-line-or-region)
(package! expand-region)
(package! avy)
(package! pulsar)

;; Terminal
(package! eat)

;; Org / notes
(package! org-super-agenda)
(package! org-ql)

;; AI
(package! gptel-agent
  :recipe (:host github
           :repo "karthink/gptel-agent"
           :files ("*.el" "agents")))

;; Optional AI coding assistant. Requires the external aider CLI at runtime.
(package! aidermacs
  :recipe (:host github :repo "MatthewZMD/aidermacs"))
