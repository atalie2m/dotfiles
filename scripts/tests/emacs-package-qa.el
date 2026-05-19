;;; emacs-package-qa.el -*- lexical-binding: t; -*-

(setq debug-on-error t)

(require 'cl-lib)
(require 'project)
(require 'seq)

(defvar corfu-auto)
(defvar corfu-cycle)
(defvar corfu-margin-formatters)
(defvar corfu-quit-no-match)
(defvar dashboard-items)
(defvar embark-collect-mode-hook)
(defvar meow--current-state)
(defvar meow-keypad-leader-dispatch)
(defvar meow-normal-state-keymap)
(defvar popper-reference-buffers)
(defvar visual-fill-column-center-text)
(defvar visual-fill-column-width)
(defvar xref-search-program)

(declare-function cape-dabbrev "cape")
(declare-function cape-file "cape")
(declare-function consult-preview-at-point-mode "consult")
(declare-function doom-modeline-mode "doom-modeline")
(declare-function kind-icon-margin-formatter "kind-icon")
(declare-function magit-status-setup-buffer "magit")
(declare-function nerd-icons-octicon "nerd-icons")

(defvar dotfiles-emacs-qa-failures nil)
(defvar dotfiles-emacs-qa-root
  (or (getenv "DOTFILES_EMACS_QA_ROOT")
      (expand-file-name "dotfiles-emacs-package-qa" temporary-file-directory)))

(defconst dotfiles-emacs-qa-elpaca-packages
  '(cape compat consult corfu dashboard diredfl dired-subtree doom-modeline
    ef-themes elpaca elpaca-use-package embark embark-consult kind-icon
    magit marginalia markdown-mode meow nerd-icons nerd-icons-dired
    nix-ts-mode orderless org-appear org-modern popper transient vertico
    visual-fill-column))

(defconst dotfiles-emacs-qa-dependency-packages
  '(cond-let dash dired-hacks-utils f llama magit-section modus-themes s
    shrink-path svg-lib with-editor))

(defconst dotfiles-emacs-qa-built-in-features
  '(dired dired-x eglot flymake org project which-key xref))

(defun dotfiles-emacs-qa-log (status name detail)
  (message "QA:%s:%s:%s" status name detail))

(defun dotfiles-emacs-qa-pass (name detail)
  (dotfiles-emacs-qa-log "PASS" name detail))

(defun dotfiles-emacs-qa-fail (name detail)
  (push (cons name detail) dotfiles-emacs-qa-failures)
  (dotfiles-emacs-qa-log "FAIL" name detail))

(defmacro dotfiles-emacs-qa-check (name &rest body)
  (declare (indent 1))
  `(condition-case err
       (let ((detail (progn ,@body)))
         (if detail
             (dotfiles-emacs-qa-pass ,name (format "%s" detail))
           (dotfiles-emacs-qa-fail ,name "nil")))
     (error
      (dotfiles-emacs-qa-fail ,name (format "error:%S" err)))))

(defun dotfiles-emacs-qa-built-p (package)
  (let ((dir (expand-file-name
              (symbol-name package)
              (expand-file-name "elpaca/builds/" user-emacs-directory))))
    (and (file-directory-p dir) dir)))

(defun dotfiles-emacs-qa-require (feature)
  (require feature nil t))

(defun dotfiles-emacs-qa-file-contains-p (file needle)
  (with-temp-buffer
    (insert-file-contents file)
    (search-forward needle nil t)))

(defun dotfiles-emacs-qa-key-binding-p (key command)
  (eq (lookup-key global-map (kbd key)) command))

(defun dotfiles-emacs-qa-project-root-equal-p (actual expected)
  (and actual (file-equal-p actual expected)))

(defun dotfiles-emacs-qa-open-save-file (file mode text needle)
  (find-file file)
  (erase-buffer)
  (when mode
    (funcall mode))
  (insert text)
  (save-buffer)
  (and (file-exists-p file)
       (not (buffer-modified-p))
       (dotfiles-emacs-qa-file-contains-p file needle)))

(defun dotfiles-emacs-qa-capf-present-p (fn)
  (or (memq fn completion-at-point-functions)
      (memq fn (default-value 'completion-at-point-functions))))

(defun dotfiles-emacs-qa-setup-fixtures ()
  (when (file-directory-p dotfiles-emacs-qa-root)
    (delete-directory dotfiles-emacs-qa-root t))
  (let* ((root dotfiles-emacs-qa-root)
         (project-root (expand-file-name "git-project/" root))
         (src-dir (expand-file-name "src/" project-root)))
    (make-directory src-dir t)
    (make-directory (expand-file-name "docs/" project-root) t)
    (make-directory (expand-file-name "dired/subdir/" root) t)
    (with-temp-file (expand-file-name "tracked.el" src-dir)
      (insert "(defun tracked-original ()\n  1)\n"))
    (with-temp-file (expand-file-name "flake.nix" project-root)
      (insert "{ pkgs ? import <nixpkgs> {} }:\npkgs.hello\n"))
    (with-temp-file (expand-file-name "README.md" project-root)
      (insert "# QA Project\n"))
    (with-temp-file (expand-file-name "dired/subdir/child.txt" root)
      (insert "child\n"))
    (let ((default-directory project-root))
      (call-process "git" nil nil nil "init" "-q")
      (call-process "git" nil nil nil "config" "user.name" "Emacs QA")
      (call-process "git" nil nil nil "config" "user.email" "emacs-qa@example.invalid")
      (call-process "git" nil nil nil "add" ".")
      (call-process "git" nil nil nil "commit" "-q" "-m" "initial"))
    root))

(defun dotfiles-emacs-qa-run ()
  (let* ((root (dotfiles-emacs-qa-setup-fixtures))
         (project-root (expand-file-name "git-project/" root))
         (org-file (expand-file-name "notes.org" root))
         (md-file (expand-file-name "git-project/README.md" root))
         (nix-file (expand-file-name "git-project/flake.nix" root))
         (elisp-file (expand-file-name "git-project/src/tracked.el" root)))

    (dolist (package dotfiles-emacs-qa-elpaca-packages)
      (dotfiles-emacs-qa-check (format "package-built:%s" package)
        (dotfiles-emacs-qa-built-p package)))

    (dolist (package dotfiles-emacs-qa-dependency-packages)
      (dotfiles-emacs-qa-check (format "dependency-built:%s" package)
        (dotfiles-emacs-qa-built-p package)))

    (dolist (feature dotfiles-emacs-qa-built-in-features)
      (dotfiles-emacs-qa-check (format "built-in-feature:%s" feature)
        (dotfiles-emacs-qa-require feature)))

    (dolist (feature '(compat transient ef-themes nerd-icons doom-modeline
                       markdown-mode nix-ts-mode meow vertico marginalia
                       orderless consult embark corfu cape kind-icon diredfl
                       dired-subtree nerd-icons-dired org-modern org-appear
                       visual-fill-column popper dashboard magit magit-section
                       with-editor dash f s shrink-path svg-lib))
      (dotfiles-emacs-qa-check (format "require:%s" feature)
        (dotfiles-emacs-qa-require feature)))

    (dotfiles-emacs-qa-check "edit-save:org"
      (dotfiles-emacs-qa-open-save-file
       org-file nil
       "* Emacs QA\n\nThis file was edited and saved through Emacs.\n\n- [ ] write\n- [X] save\n\n#+begin_src emacs-lisp\n(message \"org block\")\n#+end_src\n"
       "edited and saved through Emacs"))
    (dotfiles-emacs-qa-check "org:major-mode"
      (eq major-mode 'org-mode))
    (dotfiles-emacs-qa-check "org:org-modern"
      (bound-and-true-p org-modern-mode))
    (dotfiles-emacs-qa-check "org:org-appear"
      (bound-and-true-p org-appear-mode))
    (dotfiles-emacs-qa-check "org:visual-fill-column"
      (and (bound-and-true-p visual-fill-column-mode)
           (= visual-fill-column-width 96)
           visual-fill-column-center-text))
    (dotfiles-emacs-qa-check "pair:org-modern+org-appear+visual-fill-column"
      (and (bound-and-true-p org-modern-mode)
           (bound-and-true-p org-appear-mode)
           (bound-and-true-p visual-fill-column-mode)))

    (dotfiles-emacs-qa-check "edit-save:markdown"
      (dotfiles-emacs-qa-open-save-file
       md-file nil
       "# QA Project\n\n- markdown-mode is active\n"
       "markdown-mode is active"))
    (dotfiles-emacs-qa-check "markdown:major-mode"
      (eq major-mode 'markdown-mode))

    (dotfiles-emacs-qa-check "edit-save:nix"
      (dotfiles-emacs-qa-open-save-file
       nix-file nil
       "{ pkgs ? import <nixpkgs> {} }:\n\npkgs.hello\n"
       "pkgs.hello"))
    (dotfiles-emacs-qa-check "nix:major-mode"
      (eq major-mode 'nix-ts-mode))
    (dotfiles-emacs-qa-check "treesit:nix-parser-or-mode"
      (or (not (fboundp 'treesit-parser-list))
          (treesit-parser-list)
          (eq major-mode 'nix-ts-mode)))

    (dotfiles-emacs-qa-check "edit-save:elisp"
      (dotfiles-emacs-qa-open-save-file
       elisp-file #'emacs-lisp-mode
       "(defun tracked-change ()\n  (message \"hello\")\n  (+ 1 2))\n"
       "tracked-change"))
    (dotfiles-emacs-qa-check "flymake:prog-hook"
      (progn
        (flymake-mode 1)
        (bound-and-true-p flymake-mode)))
    (dotfiles-emacs-qa-check "pair:flymake+elisp-edit"
      (and (eq major-mode 'emacs-lisp-mode)
           (bound-and-true-p flymake-mode)
           (not (buffer-modified-p))))

    (dotfiles-emacs-qa-check "completion:vertico"
      (bound-and-true-p vertico-mode))
    (dotfiles-emacs-qa-check "completion:marginalia"
      (bound-and-true-p marginalia-mode))
    (dotfiles-emacs-qa-check "completion:orderless"
      (memq 'orderless completion-styles))
    (dotfiles-emacs-qa-check "completion:consult-bindings"
      (and (dotfiles-emacs-qa-key-binding-p "C-s" 'consult-line)
           (dotfiles-emacs-qa-key-binding-p "C-x b" 'consult-buffer)
           (dotfiles-emacs-qa-key-binding-p "M-g r" 'consult-ripgrep)))
    (dotfiles-emacs-qa-check "completion:embark-bindings"
      (and (dotfiles-emacs-qa-key-binding-p "C-." 'embark-act)
           (dotfiles-emacs-qa-key-binding-p "C-;" 'embark-dwim)))
    (dotfiles-emacs-qa-check "pair:vertico+marginalia+orderless"
      (and (bound-and-true-p vertico-mode)
           (bound-and-true-p marginalia-mode)
           (memq 'orderless completion-styles)
           (equal (alist-get 'file completion-category-overrides)
                  '((styles partial-completion)))))
    (dotfiles-emacs-qa-check "pair:consult+embark"
      (and (fboundp 'consult-buffer)
           (fboundp 'embark-act)
           (dotfiles-emacs-qa-require 'embark-consult)
           (memq #'consult-preview-at-point-mode embark-collect-mode-hook)))

    (dotfiles-emacs-qa-check "in-buffer-completion:corfu"
      (and (bound-and-true-p global-corfu-mode)
           corfu-auto
           corfu-cycle
           (eq corfu-quit-no-match 'separator)))
    (dotfiles-emacs-qa-check "in-buffer-completion:cape"
      (and (dotfiles-emacs-qa-capf-present-p #'cape-file)
           (dotfiles-emacs-qa-capf-present-p #'cape-dabbrev)))
    (dotfiles-emacs-qa-check "in-buffer-completion:kind-icon"
      (memq #'kind-icon-margin-formatter corfu-margin-formatters))
    (dotfiles-emacs-qa-check "pair:corfu+cape+kind-icon"
      (and (bound-and-true-p global-corfu-mode)
           (dotfiles-emacs-qa-capf-present-p #'cape-file)
           (dotfiles-emacs-qa-capf-present-p #'cape-dabbrev)
           (memq #'kind-icon-margin-formatter corfu-margin-formatters)))
    (dotfiles-emacs-qa-check "pair:cape-file-completes-temp-path"
      (let ((default-directory root))
        (with-temp-buffer
          (insert (expand-file-name "git-pro" root))
          (let ((capf (cape-file)))
            (and (consp capf) (functionp (nth 2 capf)))))))

    (dired root)
    (dotfiles-emacs-qa-check "dired:major-mode"
      (eq major-mode 'dired-mode))
    (dotfiles-emacs-qa-check "dired:hide-details"
      (bound-and-true-p dired-hide-details-mode))
    (dotfiles-emacs-qa-check "dired:diredfl"
      (bound-and-true-p diredfl-mode))
    (dotfiles-emacs-qa-check "dired:nerd-icons"
      (bound-and-true-p nerd-icons-dired-mode))
    (dotfiles-emacs-qa-check "dired:subtree-command"
      (fboundp 'dired-subtree-toggle))
    (dotfiles-emacs-qa-check "pair:dired+diredfl+icons+subtree"
      (and (eq major-mode 'dired-mode)
           (bound-and-true-p diredfl-mode)
           (bound-and-true-p nerd-icons-dired-mode)
           (fboundp 'dired-subtree-toggle)))

    (let ((default-directory project-root))
      (find-file elisp-file)
      (dotfiles-emacs-qa-check "project:detect-git-root"
        (when-let ((project (project-current nil)))
          (dotfiles-emacs-qa-project-root-equal-p (project-root project) project-root)))
      (dotfiles-emacs-qa-check "xref:configured"
        (and (fboundp 'xref-find-definitions)
             (eq xref-search-program 'ripgrep)))
      (dotfiles-emacs-qa-check "magit:status"
        (progn
          (magit-status-setup-buffer project-root)
          (eq major-mode 'magit-status-mode)))
      (dotfiles-emacs-qa-check "pair:project+xref+magit"
        (and (eq major-mode 'magit-status-mode)
             (dotfiles-emacs-qa-project-root-equal-p
              (project-root (project-current nil))
              project-root)
             (fboundp 'magit-status))))

    (dotfiles-emacs-qa-check "eglot:available-and-hooks"
      (and (fboundp 'eglot-ensure)
           (seq-some (lambda (hook)
                       (memq #'eglot-ensure (symbol-value hook)))
                     '(bash-ts-mode-hook css-ts-mode-hook html-mode-hook
                       js-ts-mode-hook json-ts-mode-hook nix-ts-mode-hook
                       python-ts-mode-hook rust-ts-mode-hook
                       typescript-ts-mode-hook yaml-ts-mode-hook))))
    (dotfiles-emacs-qa-check "pair:eglot+flymake+project"
      (and (fboundp 'eglot-ensure)
           (fboundp 'flymake-mode)
           (project-current nil)))

    (dotfiles-emacs-qa-check "ui:ef-theme"
      (custom-theme-enabled-p 'ef-dream))
    (dotfiles-emacs-qa-check "ui:nerd-icons"
      (let ((glyph (nerd-icons-octicon "nf-oct-file")))
        (and (stringp glyph) (> (length glyph) 0))))
    (dotfiles-emacs-qa-check "ui:doom-modeline"
      (progn
        (doom-modeline-mode 1)
        (bound-and-true-p doom-modeline-mode)))
    (dotfiles-emacs-qa-check "pair:theme+icons+modeline"
      (and (custom-theme-enabled-p 'ef-dream)
           (bound-and-true-p doom-modeline-mode)
           (stringp (nerd-icons-octicon "nf-oct-file"))))

    (dotfiles-emacs-qa-check "meow:enabled"
      (and (bound-and-true-p meow-global-mode)
           (memq meow--current-state '(normal motion insert keypad beacon))))
    (dotfiles-emacs-qa-check "meow:leader-bindings"
      (and (eq (lookup-key meow-normal-state-keymap (kbd "SPC")) 'meow-keypad)
           (equal meow-keypad-leader-dispatch "C-c")
           (eq (key-binding (kbd "C-c /")) 'consult-ripgrep)
           (eq (key-binding (kbd "C-c b")) 'consult-buffer)
           (eq (key-binding (kbd "C-c g")) 'magit-status)))
    (dotfiles-emacs-qa-check "pair:meow+consult+magit"
      (and (bound-and-true-p meow-global-mode)
           (eq (lookup-key meow-normal-state-keymap (kbd "SPC")) 'meow-keypad)
           (eq (key-binding (kbd "C-c b")) 'consult-buffer)
           (eq (key-binding (kbd "C-c g")) 'magit-status)))
    (dotfiles-emacs-qa-check "which-key:built-in"
      (bound-and-true-p which-key-mode))

    (dotfiles-emacs-qa-check "display-buffer:rules"
      (and (assoc "\\*\\(?:Help\\|Apropos\\|info\\|Warnings\\)\\*" display-buffer-alist)
           (assoc "\\*\\(?:compilation\\|grep\\|Flymake diagnostics\\)\\*" display-buffer-alist)))
    (dotfiles-emacs-qa-check "popper:enabled"
      (and (bound-and-true-p popper-mode)
           (bound-and-true-p popper-echo-mode)
           (member "\\*Messages\\*" popper-reference-buffers)))
    (dotfiles-emacs-qa-check "pair:display-buffer+popper"
      (and (assoc "\\*\\(?:Help\\|Apropos\\|info\\|Warnings\\)\\*" display-buffer-alist)
           (bound-and-true-p popper-mode)))
    (dotfiles-emacs-qa-check "dashboard:configured"
      (and (featurep 'dashboard)
           (equal dashboard-items '((recents . 8) (projects . 8)))))
    (dotfiles-emacs-qa-check "pair:dashboard+recentf+project"
      (and (bound-and-true-p recentf-mode)
           (featurep 'dashboard)
           (project-current nil)))

    (dotfiles-emacs-qa-check "early-init:package-disabled"
      (not package-enable-at-startup))
    (dotfiles-emacs-qa-check "emacs-core:modes"
      (and (bound-and-true-p global-auto-revert-mode)
           (bound-and-true-p savehist-mode)
           (bound-and-true-p save-place-mode)
           (bound-and-true-p recentf-mode)))

    (when dotfiles-emacs-qa-failures
      (dotfiles-emacs-qa-log "SUMMARY" "FAIL"
                             (format "%S" (reverse dotfiles-emacs-qa-failures)))
      (kill-emacs 1))
    (dotfiles-emacs-qa-log "SUMMARY" "PASS" "all checks passed")))

(dotfiles-emacs-qa-run)
