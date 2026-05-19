;;; early-init.el -*- lexical-binding: t; -*-

(setq package-enable-at-startup nil)
(setq inhibit-startup-screen t)
(setq frame-inhibit-implied-resize t)
(setq native-comp-async-report-warnings-errors 'silent)

(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)

(setq gc-cons-threshold most-positive-fixnum)
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 64 1024 1024))))
