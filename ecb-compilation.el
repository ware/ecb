;;; ecb-compilation.el --- 

;; $Id: ecb-compilation.el,v 1.19 2003/03/05 09:05:27 berndl Exp $

;; Copyright (C) 2000-2003 Free Software Foundation, Inc.
;; Copyright (C) 2000-2003 Kevin A. Burton (burton@openprivacy.org)

;; Author: Kevin A. Burton (burton@openprivacy.org)
;; Maintainer: Kevin A. Burton (burton@openprivacy.org)
;; Location: http://relativity.yi.org
;; Keywords: 
;; Version: 1.0.0

;; This file is [not yet] part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify it under
;; the terms of the GNU General Public License as published by the Free Software
;; Foundation; either version 2 of the License, or any later version.
;;
;; This program is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
;; FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
;; details.
;;
;; You should have received a copy of the GNU General Public License along with
;; this program; if not, write to the Free Software Foundation, Inc., 59 Temple
;; Place - Suite 330, Boston, MA 02111-1307, USA.

;;; Commentary:

;; NOTE: If you enjoy this software, please consider a donation to the EFF
;; (http://www.eff.org)

;;; Code:

(eval-when-compile
  (require 'silentcomp))

(silentcomp-defun comint-check-proc)

(require 'ecb-util)

(defgroup ecb-compilation-content nil
  "Settings for all things displayed in the compile window of ECB."
  :group 'ecb
  :prefix "ecb-compilation-")

(defcustom ecb-compilation-buffer-names `(("*Calculator*" . nil)
                                          ("*vc*" . nil)
                                          ("*vc-diff*" . nil)
                                          ("*Apropos*" . nil)
                                          ,(if ecb-running-xemacs
                                               '("\\*Help.*\\*" . t)
                                              '("*Help*" . nil))
                                          ("*Backtrace*" . nil)
                                          ("*shell*" . nil)
                                          ("*bsh*" . nil)
                                          (,(if ecb-running-xemacs
                                               " *Message-Log*"
                                             "*Messages*") . nil))
  "*Additional buffer names that should be displayed in the compilation
window of ECB even if `compilation-buffer-p' says nil."
  :group 'ecb-compilation-content
  :group 'ecb-layout
  :type '(repeat (cons (string :tag "Buffer name")
                       (boolean :tag "Handled as regexp"))))

(defvar ecb-compilation-buffer-names-internal nil
  "This variable is for ECB internal use and can be used by ECB to add
buffer-names to the set displayed in the compile-window. Type is the same as
of option `ecb-compilation-buffer-names'")

(defun ecb-compilation-buffer-names ()
  "Return the set of buffer names which should be displayed in the
compile-window of ECB."
  (append ecb-compilation-buffer-names
          ecb-compilation-buffer-names-internal))

(defun ecb-compilation-registered-buffer-p (name)
  "Check if name belongs to the set of buffers returned by
`ecb-compilation-buffer-names'. If yes returns NAME."
  (catch 'exit
    (dolist (b (ecb-compilation-buffer-names))
      (if (null (cdr b))
          (if (string= name (car b))
              (throw 'exit name))
        (save-match-data
          (if (string-match (car b) name)
              (throw 'exit name))))
      nil)))

(defcustom ecb-compilation-major-modes (list 'eshell-mode 'compilation-mode)
  "*Additional major-mode that should be displayed in the compilation
window of ECB even if `compilation-buffer-p' says nil."
  :group 'ecb-compilation-content
  :group 'ecb-layout
  :type '(repeat (symbol :tag "major-mode name")))

(defvar ecb-compilation-major-modes-internal nil
  "This variable is for ECB internal use and can be used by ECB to add
  major-mode symbols to the set displayed in the compile-window.")

(defun ecb-compilation-major-modes ()
  "Return all major-mode symbols which should be displayed in the
compile-window."
  (append ecb-compilation-major-modes
          ecb-compilation-major-modes-internal))

(defun ecb-compilation-get-buffers()
  "Get all known compilation buffer names.  See `ecb-compilation-buffer-p'."

  (let((buffer-names '())
       (buffer-list (buffer-list))
       (index 0))

    (setq buffer-list (sort buffer-list (lambda(first second)
                                          (string-lessp (buffer-name first)
                                                        (buffer-name second)))))

    (dolist(buffer buffer-list)

      (when (ecb-compilation-buffer-p buffer)

        (setq buffer-names
              (append buffer-names
                      (list (cons (buffer-name buffer) index))))
        
        (setq index (1+ index))))

    buffer-names))

;; (ecb-compilation-registered-buffer-p "*Help: insert*")

(defun ecb-compilation-buffer-p(buffer-or-name)
  "Test if the given buffer is a compilation buffer. Note that in this case we
define 'compilation buffer' as a buffer that should ideally be displayed in the
`ecb-compile-window'. This means that in some situations this might not be the
result of a `compile-internal'. A good example would be the *Help* buffer or the
`ecb-eshell-buffer-name'.

BUFFER can be the name of a buffer or a buffer-objekt.

This function is non-nil if the name of BUFFER is either contained in the list
returned by the function `ecb-compilation-buffer-names', or its `major-mode'
is contained in the list returned by the function
`ecb-compilation-major-modes', or if `compilation-buffer-p' returns true."

  ;;determine the best valid for the buffer.
  (let ((buffer (cond ((stringp buffer-or-name)
                       (get-buffer buffer-or-name))
                      ((bufferp buffer-or-name)
                       buffer-or-name)
                      (t
                       nil))))

    (when buffer

      ;;test if this is a valid buffer by name.
      (if (ecb-compilation-registered-buffer-p (buffer-name buffer))
          t
        ;;else test if this is a valid buffer by mode
        (if (save-excursion
              (set-buffer buffer)
              (member major-mode (ecb-compilation-major-modes)))
            t
          ;;else test if this is a regular compilation buffer
          (if (compilation-buffer-p buffer)
              t
            ;;else check if this is a comint buffer
            (if (and (fboundp 'comint-check-proc)
                     (comint-check-proc buffer))
                t
              ;;else it isn't a complication buffer
              nil)))))))

;; Klaus Berndl <klaus.berndl@sdm.de>: The following mechanism is necessary to
;; avoid eating up whole CPU for updating the menu-entries for the
;; compilation-buffers. Especially if you have opened a lot of buffers this
;; can slow down Emacs/ECB dramatically. Now we add an idle-times
;; check-function `ecb-compilation-buffer-list-changed-p' which checks if the
;; buffer-list has changed. If yes, then the variable
;; `ecb-compilation-update-menu-p' is set to t. Only if this variable if not
;; nil the menu-bar-update-hook `ecb-compilation-update-menu' updates the
;; ECB-menu.

(defvar ecb-compilation-update-menu-p nil)
(defvar ecb-compilation-buffer-list-cache nil)
(defvar ecb-compilation-update-idle-time 0.25)

(defun ecb-compilation-buffer-list-init ()
  "Initialize the compilation buffer list cache."
  (setq ecb-compilation-update-menu-p nil)
  (setq ecb-compilation-buffer-list-cache nil)
  (ecb-compilation-buffer-list-changed-p))

(defun ecb-compilation-buffer-list-changed-p ()
  "Check if current active buffer list has changed - i.e. if a new buffer has
been created or a buffer has been deleted. If yes then
`ecb-compilation-update-menu-p' is set to not nil and the cache is updated."
  (let ((new-buffer-list (buffer-list)))
    (when (not (equal new-buffer-list
                      ecb-compilation-buffer-list-cache))
      (setq ecb-compilation-buffer-list-cache new-buffer-list)
      ;; Nowhere else this variable will be set to t.
      (setq ecb-compilation-update-menu-p t))))

(defun ecb-compilation-update-menu()
  "Create an install a menu that allows the user to navigate buffers that are
valid ECB compilation buffers. This is only done if
`ecb-compilation-update-menu-p' is not nil; see
`ecb-compilation-buffer-list-changed-p'. For more information about
compilation buffers see `ecb-compilation-buffer-p'."

  (when ecb-compilation-update-menu-p
    (let ((submenu nil)
          (buffers (ecb-compilation-get-buffers)))
      (condition-case nil
          (progn
            (setq ecb-compilation-update-menu-p nil)
            (dolist(buffer buffers)
              (setq submenu
                    (append submenu
                            (list (vector (car buffer)
                                          `(funcall (if (ecb-compile-window-live-p)
                                                        'switch-to-buffer
                                                      'switch-to-buffer-other-window)
                                                  ,(car buffer))
                                          :active t)))))
            
            ;;TODO: Klaus Berndl <klaus.berndl@sdm.de>: Seems not to work with
            ;;Emacs 20.X
            (easy-menu-change (list ecb-menu-name)
                              "Compilation Buffers"
                              submenu
                              "Navigate")
            t)
        (error nil)))))
      


(silentcomp-provide 'ecb-compilation)

;;; ecb-compilation.el ends here