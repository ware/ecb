;;; ecb-speedbar.el --- 

;; $Id: ecb-speedbar.el,v 1.29 2002/12/19 18:01:58 berndl Exp $

;; Copyright (C) 2000-2003 Free Software Foundation, Inc.
;; Copyright (C) 2000-2003 Kevin A. Burton (burton@openprivacy.org)

;; Author: Kevin A. Burton (burton@openprivacy.org)
;; Maintainer: Kevin A. Burton (burton@openprivacy.org)
;; Location: http://relativity.yi.org
;; Keywords: 
;; Version: 1.1.

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

;; This package provide speedbar integration for the ECB.
;;
;; This allows you to:
;;
;; - Sync up to the speedbar with the current buffer.
;;
;; - Files opened with the speedbar are displayed in the ecb source window.
;;
;; Note that this is tested with recent speedbars >= 0.14beta2. If the
;; speedbar implementation changes a lot this could break.
;;
;; TODO: Klaus Berndl <klaus.berndl@sdm.de>: IMHO the following WARNING is not
;; necessary anymore because IMHO we need no patched speedbar at least not
;; when 0.14beta4 is used.

;; WARNING: currently ecb-speedbar depends on patches to the speedbar which I
;; sent to the author.  Without these patches ecb-speedbar will work but your
;; source buffer may recenter itself when you change buffers.  Fully functionaly
;; but very annoying.  Hopefully these patches will make it into a 0.14beta3.
;;
;;   - UPDATE:  the patches are in his queue but have not made it in yet.

;; If you enjoy this software, please consider a donation to the EFF
;; (http://www.eff.org)

;;; Design:

;; There are two major issues we have with the speedbar-frame variable.
;;
;;TODO: Klaus Berndl <klaus.berndl@sdm.de>: Not an issue anymore, at
;;least IMHO
;; 1. If we set this value to the (selected-frame), when set change buffers,
;; the current buffers point is reset to (point-min)
;;
;;TODO: Klaus Berndl <klaus.berndl@sdm.de>: Not an alternative anymore, at
;;least IMHO
;; 2. If we set this to a newly created frame, say an invisible frame, we have
;; the following problems:
;;
;;   - all the glphys in the speedbar window are NOT set.
;;
;;   - if we hit [ENTER] in the speedbar window the invisible frame is made
;;     visible  :(

;;; History:
;;
;; - Thu DEc 19 2002 6:54 PM (klaus.berndl@sdm.de): Full integrated in ECB and
;;   fixed some bugs. Now the speedbar integration seems to work very well.
;;
;; - Sat Dec 15 2001 03:10 AM (burton@openprivacy.org): only sync up the eshell
;; if the current file is in a different dir than the speedbar.
;;
;; - Fri Dec 14 2001 10:11 PM (burton@openprivacy.org): when we hit <ENTER> on a
;; file in the speedbar window, a new window is created.
;;
;; - Sun Nov 18 2001 01:46 AM (burton@openprivacy.org): BUG: we need to set
;; dframe-activate-frame to the current frame and NOT use an invisible frame.
;; This is important because when I select a buffer in ECB it can't use the
;; invisible frame.  :(
;;
;; Sat Nov 10 2001 09:30 PM (burton@openprivacy.org): implementation of
;; ecb-delete-other-windows-in-editwindow-20

;;

;;; TODO:

;; - BUG: when I sync to a buffer in the ECB frame, the speedbar will show the
;;   correct directory.  Then, when I open another frame, and change to a buffer
;;   there, the buffer in the new frame will be synched with the speedbar.  This
;;   needs to stay in synch with the file currently open in the ECB.
;;
;; TODO: Klaus Berndl <klaus.berndl@sdm.de>: Seems to be fixed already!
;; - BUG: for some reason if we hit <ENTER> in the ecb-speedbar window,
;;   sometimes a new frame will come up.
;;
;;   - this only comes up the FIRST time I select a buffer.  Could some variable
;;     be changed?  Maybe the `dframe-attached-frame' or
;;     `speedbar-attached-frame' needs to be setup correctly.
;;
;;   - Actually it seems to be a problem if we have one ECB frame and then I
;;     create another frame.
;;
;; TODO: Klaus Berndl <klaus.berndl@sdm.de>: Seems to be gone at least with
;;       speedbar 0.14beta4 which i'm using.
;; - BUG: bug in speedbar.  Need a feature so that the speedbar doesn't require
;;   that we HAVE to have the speedbar in a frame.  If we try to run (speedbar)
;;   when ecb-speedbar is active the ecb-frame will go away :(

;; (speedbar-current-frame) doesn't seem to work right..
;; 

;;; Code:

(eval-when-compile
  (require 'silentcomp))

(require 'speedbar)

(silentcomp-defvar speedbar-attached-frame)
(silentcomp-defvar dframe-attached-frame)
(silentcomp-defvar speedbar-select-frame-method)

(defconst ecb-speedbar-adviced-functions '(speedbar-click)
  "This functions of speedbar are always adviced if ECB is active.")

(defadvice speedbar-click (around ecb)
  "Makes the function compatible with ECB. If ECB is active and the window of
`ecb-speedbar-buffer-name' is visible \(means a layouts uses the
speedbar-integration) the advice acts like the original version but it
performs not the final `dframe-quick-mouse' which keeps the point positioned
in the ECB-window. So the edit-window is selected after clicking onto a
filename in the speedbar."
  (if (and (equal (selected-frame) ecb-frame)
           (window-live-p (get-buffer-window ecb-speedbar-buffer-name)))
      (let ((speedbar-power-click dframe-power-click))
        (speedbar-do-function-pointer))      
    ad-do-it))

(defun ecb-speedbar-enable-advices ()
  (dolist (elem ecb-speedbar-adviced-functions)
    (ad-enable-advice elem 'around 'ecb)
    (ad-activate elem)))

(defun ecb-speedbar-disable-advices ()
  (dolist (elem ecb-speedbar-adviced-functions)
    (ad-disable-advice elem 'around 'ecb)
    (ad-activate elem)))

(defvar ecb-speedbar-buffer-name " SPEEDBAR"
  "Name of the ECB speedbar buffer.")

(defun ecb-set-speedbar-buffer()
  "Set the speedbar buffer within ECB."
  (ecb-speedbar-activate)
  (set-window-dedicated-p (selected-window) nil)
  (set-window-buffer (selected-window) (get-buffer-create ecb-speedbar-buffer-name))
  (set-window-dedicated-p (selected-window) t)
  (if ecb-running-emacs-21
      (set (make-local-variable 'automatic-hscrolling) nil)))


(defvar ecb-speedbar-verbosity-level-old nil)
(defvar ecb-speedbar-select-frame-method-old nil)

(defun ecb-speedbar-activate()
  "Make sure the speedbar is running. WARNING: This could be dependend on the
current speedbar implementation but normally it sould be work with recent
speedbar versions >= 0.14beta2. But be aware: If the speedbar impl is changed
this could break."

  ;; enable the advices for speedbar
  (ecb-speedbar-enable-advices)
  
  ;;disable automatic speedbar updates... let the ECB handle this with
  ;;ecb-current-buffer-sync
  (speedbar-disable-update)

  ;;always stay in the current frame
  ;; save the old value but only first time!
  (if (null ecb-speedbar-select-frame-method-old)
      (setq ecb-speedbar-select-frame-method-old speedbar-select-frame-method))
  (setq speedbar-select-frame-method 'attached)

  (when (not (buffer-live-p speedbar-buffer))
    (save-excursion
      (setq speedbar-buffer (get-buffer-create ecb-speedbar-buffer-name))
      (set-buffer speedbar-buffer)
      (speedbar-mode)))

  ;;Start up the timer
  (speedbar-reconfigure-keymaps)
  (speedbar-update-contents)
  (speedbar-set-timer 1)

  ;;Set the frame that the speedbar should use.  This should be the selected
  ;;frame.  AKA the frame that ECB is running in.
  (setq speedbar-frame ecb-frame)
  (setq speedbar-attached-frame ecb-frame)
  (setq dframe-attached-frame ecb-frame)
  
  ;;this needs to be 0 because we can't have the speedbar too chatty in the
  ;;current frame because this will mean that the minibuffer will be updated too
  ;;much.
  ;; save the old value but only first time!
  (if (null ecb-speedbar-verbosity-level-old)
      (setq ecb-speedbar-verbosity-level-old speedbar-verbosity-level))
  (setq speedbar-verbosity-level 0)

  (add-hook 'ecb-current-buffer-sync-hook
            'ecb-speedbar-current-buffer-sync)
  
  ;;reset the selection variable
  (setq speedbar-last-selected-file nil))

(defun ecb-speedbar-deactivate ()
  "Reset things as before activating speedbar by ECB"
  (ecb-speedbar-disable-advices)
  
  (setq speedbar-frame nil)
  (setq speedbar-attached-frame nil)
  (setq dframe-attached-frame nil)

  (speedbar-enable-update)
  
  (if ecb-speedbar-select-frame-method-old
      (setq speedbar-select-frame-method ecb-speedbar-select-frame-method-old))
  (setq ecb-speedbar-select-frame-method-old nil)

  (if ecb-speedbar-verbosity-level-old
      (setq speedbar-verbosity-level ecb-speedbar-verbosity-level-old))
  (setq ecb-speedbar-verbosity-level-old nil)
  
  (remove-hook 'ecb-current-buffer-sync-hook
               'ecb-speedbar-current-buffer-sync)

  (when (and speedbar-buffer
             (buffer-live-p speedbar-buffer))
    (kill-buffer speedbar-buffer)
    (setq speedbar-buffer nil)))


(defun ecb-speedbar-current-buffer-sync()
  "Update the speedbar so that we sync up with the current file."
  (interactive)

  ;;only operate if the current frame is the ECB frame and the
  ;;ecb-speedbar-buffer is visible!
  (when (and (equal (selected-frame) ecb-frame)
             (window-live-p (get-buffer-window ecb-speedbar-buffer-name)))
    
    (save-excursion
      (let(speedbar-default-directory ecb-default-directory)

        (setq ecb-default-directory default-directory)

        (save-excursion
      
          (set-buffer ecb-speedbar-buffer-name)
        
          (setq speedbar-default-directory default-directory))

        (when (and (not (string-equal speedbar-default-directory
                                      ecb-default-directory))
                   ecb-minor-mode
                   speedbar-buffer
                   (buffer-live-p speedbar-buffer))

            (speedbar-update-contents))))))

(silentcomp-provide 'ecb-speedbar)

;;; ecb-speedbar.el ends here