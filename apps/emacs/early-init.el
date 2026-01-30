;; early-init.el --- early init

;; Increase GC threshold for perceived startup speed.
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

;; Prevent package.el from starting automatically (managed in init.el)
(setq package-enable-at-startup nil)
