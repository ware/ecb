;;; ecb-speedbar.el --- Integration of speedbar into ECB

;; Copyright (C) 2000 - 2003 Jesper Nordenberg,
;;                           Klaus Berndl,
;;                           Kevin A. Burton,
;;                           Free Software Foundation, Inc.

;; Author: Jesper Nordenberg <mayhem@home.se>
;;         Klaus Berndl <klaus.berndl@sdm.de>
;;         Kevin A. Burton <burton@openprivacy.org>
;; Maintainer: Klaus Berndl <klaus.berndl@sdm.de>
;;             Kevin A. Burton <burton@openprivacy.org>
;; Keywords: browser, code, programming, tools
;; Created: 2002

;; This program is free software; you can redistribute it and/or modify it under
;; the terms of the GNU General Public License as published by the Free Software
;; Foundation; either version 2, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
;; FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
;; details.

;; You should have received a copy of the GNU General Public License along with
;; GNU Emacs; see the file COPYING.  If not, write to the Free Software
;; Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

;; $Id: ecb-speedbar.el,v 1.55 2004/02/28 16:14:46 berndl Exp $

;;; Commentary:

;; This package provide speedbar integration and using for the ECB.
;;
;; There are two complete different aspects of integration/using speedbar for
;; ECB:
;;
;; 1. Integration the speedbar itself into the ecb-frame:
;;
;;    This allows you to:
;;    
;;    - Sync up to the speedbar with the current buffer.
;;    
;;    - Files opened with the speedbar are displayed in the ecb source window.
;;
;; 2. Using the speedbar-mechanism for parsing files supported not by semantic
;;    but by imenu and/or etags.
;;
;;    This is not done via the speedbar-display but only the parsing mechanism
;;    of `speedbar-fetch-dynamic-tags' is used and the tags are natively
;;    display in the methods-buffer of ECB!
;;
;; Note that this is tested with recent speedbars >= 0.14beta1. If the
;; speedbar implementation changes a lot this could break.
;;
;; If you enjoy this software, please consider a donation to the EFF
;; (http://www.eff.org)

;;; History:

;; For the ChangeLog of this file see the CVS-repository. For a complete
;; history of the ECB-package see the file NEWS.

;;; Code:

(eval-when-compile
  (require 'silentcomp))

(require 'speedbar)
(require 'ecb-util)
(require 'ecb-semantic-wrapper)

;; imenu
(silentcomp-defvar imenu--rescan-item)
(silentcomp-defvar imenu--index-alist)


(defconst ecb-speedbar-adviced-functions '((speedbar-click . around)
                                           (speedbar-frame-mode . around)
                                           (speedbar-get-focus . around)
                                           ;; we have to fix a bug there
                                           (dframe-mouse-set-point . around))
  "These functions of speedbar are always adviced if ECB is active. Each
element of the list is a cons-cell where the car is the function-symbol and
the cdr the advice-class \(before, around or after). If a function should be
adviced with more than one class \(e.g. with a before and an after-advice)
then for every class a cons must be added to this list.")

(defconst ecb-speedbar-buffer-name " SPEEDBAR"
  "Name of the ECB speedbar buffer.")

(defun ecb-speedbar-buffer-selected ()
  (equal (current-buffer) (get-buffer ecb-speedbar-buffer-name)))

(defadvice speedbar-click (around ecb)
  "Makes the function compatible with ECB. If ECB is active and the window of
`ecb-speedbar-buffer-name' is visible \(means a layouts uses the
speedbar-integration) and the clicked node in speedbar is a file then the
ECB-edit-window is selected at the end. So always the edit-window is selected
after clicking onto a filename in the speedbar."
  ;; Klaus Berndl <klaus.berndl@sdm.de>: We must use an around-advice because
  ;; we need exactly the information if the *clicked* item is a file or not.
  ;; This is only available before the original speedbar-click actions because
  ;; speedbar seems to do some intelligent stuff like autom. using the first
  ;; file if a clicked directory contains any.
  (let ((item (and (fboundp 'speedbar-line-file)
                   (speedbar-line-file))))
    ad-do-it
    (if (and ecb-minor-mode
             (equal (selected-frame) ecb-frame)
             (window-live-p (get-buffer-window ecb-speedbar-buffer-name))
             (and item
                  (file-exists-p item)
                  (not (file-directory-p item))))
        (ecb-select-edit-window))))


(defadvice speedbar-frame-mode (around ecb)
  "During running speedbar within ECB this command is disabled!"
  (if ecb-minor-mode
      (message "This command is disabled during running speedbar within ECB!")
    ad-do-it))


(defadvice speedbar-get-focus (around ecb)
  "During running speedbar within ECB this function behaves like follows:
Change window focus to or from the ECB-speedbar-window. If the selected window
is not speedbar-window, then the speedbar-window is selected. If the
speedbar-window is active, then select the edit-window."
  (if ecb-minor-mode
      (if (ecb-speedbar-buffer-selected)
          (ecb-select-edit-window)
        (ecb-speedbar-select-speedbar-window))
    ad-do-it))

;; Klaus Berndl <klaus.berndl@sdm.de>: This implementation is done to make
;; clear where the bug is fixed...a better impl. can be seen in
;; tree-buffer-mouse-set-point (does the same but better code - IMHO).
(defadvice dframe-mouse-set-point (around ecb)
  "Fixes a bug in the original implementation: if clicked onto an image then
the point was not set by `mouse-set-point'."
  (if (and (fboundp 'event-over-glyph-p) (event-over-glyph-p e))
      ;; We are in XEmacs, and clicked on a picture
      (let ((ext (event-glyph-extent e)))
        ;; This position is back inside the extent where the
        ;; junk we pushed into the property list lives.
        (if (extent-end-position ext)
            (progn
              (mouse-set-point e)
              (goto-char (1- (extent-end-position ext))))
          (mouse-set-point e)))
    ;; We are not in XEmacs, OR we didn't click on a picture.
    (mouse-set-point e)))
  

(defun ecb-speedbar-select-speedbar-window ()
  (ignore-errors
    (and (window-live-p (get-buffer-window ecb-speedbar-buffer-name))
         (select-window (get-buffer-window ecb-speedbar-buffer-name)))))


(defun ecb-speedbar-set-buffer()
  "Set the speedbar buffer within ECB."
  (ecb-speedbar-activate)
  (set-window-buffer (selected-window)
                     (get-buffer-create ecb-speedbar-buffer-name))
  (if ecb-running-emacs-21
      (set (make-local-variable 'automatic-hscrolling) nil)))


(defvar ecb-speedbar-verbosity-level-old nil)
(defvar ecb-speedbar-select-frame-method-old nil)

(defun ecb-speedbar-activate()
  "Make sure the speedbar is running. WARNING: This could be dependent on the
current speedbar implementation but normally it should work with recent
speedbar versions >= 0.14beta1. But be aware: If the speedbar impl changes in
future this could break."

  ;; enable the advices for speedbar
  (ecb-enable-advices ecb-speedbar-adviced-functions)
  
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
  (ecb-disable-advices ecb-speedbar-adviced-functions)
  
  (setq speedbar-frame nil)
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



(defun ecb-speedbar-active-p ()
  "Return not nil if speedbar is active and integrated in the `ecb-frame'."
  (and (get-buffer ecb-speedbar-buffer-name)
       (get-buffer-window (get-buffer ecb-speedbar-buffer-name) ecb-frame)))

(defun ecb-speedbar-update-contents ()
  "Encapsulate updating the speedbar."
  (speedbar-update-contents))

(defun ecb-speedbar-current-buffer-sync()
  "Update the speedbar so that it's synced up with the current file."
  (interactive)

  ;;only operate if the current frame is the ECB frame and the
  ;;ecb-speedbar-buffer is visible!
  (ecb-do-if-buffer-visible-in-ecb-frame 'ecb-speedbar-buffer-name
    ;; this macro binds the local variables visible-buffer and visible-window!
    (let ((speedbar-default-directory
           (save-excursion
             (set-buffer visible-buffer)
             (ecb-fix-filename default-directory)))
          (ecb-default-directory (ecb-fix-filename default-directory)))
      (when (and (not (string-equal speedbar-default-directory
                                    ecb-default-directory))
                 speedbar-buffer
                 (buffer-live-p speedbar-buffer))
        (ecb-speedbar-update-contents)))))


;; Handling of files which can not be parsed by semantic (i.e. there is no
;; semantic-grammar available) but which can be parsed by imenu and/or etags
;; via speedbar.

(defun ecb-speedbar-sb-tag-p (tag)
  "Return not nil if TAG is a semantic-tag generated from a speedbar tag."
  (ecb--semantic--tag-get-property tag 'ecb-speedbar-tag))

(require 'tree-buffer)
(require 'ecb-face)
(defun ecb-create-non-semantic-tree (node tag-list)
  "Add all tags of TAG-LIST with side-effects as children to NODE. TAG-LIST is
a list generated by `ecb-get-tags-for-non-semantic-files'. TAG-LIST is of the
form:
\( \(\"name\" . marker-or-number) <-- one tag at this level
  \(\"name\" \(\"name\" . mon) (\"name\" . mon) )  <-- one group of tags
  \(\"name\" mon \(\"name\" . mon) )             <-- group w/ a pos. and tags

Groups can contain tags which are groups again...therefore this function is
called recursive for the elements of a group.

Return NODE."
  (let ((new-node nil)
        (new-tag nil))
    (dolist (tag tag-list)
      (cond ((null tag) nil)            ;this would be a separator
            ((speedbar-generic-list-tag-p tag)
             ;; the semantic tag for this tag
             (setq new-tag (ecb--semantic-tag (car tag)
                                              (intern (car tag))))
             (ecb--semantic--tag-set-overlay new-tag (make-vector 2 (cdr tag)))
             (ecb--semantic--tag-put-property new-tag 'ecb-speedbar-tag t)
             (ecb-apply-user-filter-to-tags (list new-tag))
             (when (not (ecb-tag-forbidden-display-p new-tag))
               (tree-node-new (progn
                                (set-text-properties
                                 0 (length (car tag))
                                 `(face ,ecb-method-non-semantic-face) (car tag))
                                (car tag))
                              0
                              new-tag
                              t
                              node)))
            ((speedbar-generic-list-positioned-group-p tag)
             ;; the semantic tag for this tag
             (setq new-tag (ecb--semantic-tag (car tag)
                                              (intern (car tag))))
             (ecb--semantic--tag-set-overlay new-tag
                                             (make-vector 2 (car (cdr tag))))
             (ecb--semantic--tag-put-property new-tag 'ecb-speedbar-tag t)
             (ecb-apply-user-filter-to-tags (list new-tag))
             (when (not (ecb-tag-forbidden-display-p new-tag))             
               (ecb-create-non-semantic-tree
                (setq new-node
                      (tree-node-new (progn
                                       (set-text-properties
                                        0 (length (car tag))
                                        `(face ,ecb-method-non-semantic-face) (car tag))
                                       (car tag))
                                     0
                                     new-tag
                                     nil node))
                (cdr (cdr tag)))
               (tree-node-set-expanded new-node
                                       (member major-mode
                                               ecb-non-semantic-methods-initial-expand))))
            ((speedbar-generic-list-group-p tag)
             (ecb-create-non-semantic-tree
              (setq new-node
                    (tree-node-new (progn
                                     (set-text-properties
                                      0 (length (car tag))
                                      `(face ,ecb-method-non-semantic-face) (car tag))
                                     (car tag))
                                   1
                                   nil nil node))
              (cdr tag))
             (tree-node-set-expanded new-node
                                     (member major-mode
                                             ecb-non-semantic-methods-initial-expand)))
            (t (ecb-error "ecb-create-non-semantic-tree: malformed tag-list!")
               )))
    node))

(defun ecb-get-tags-for-non-semantic-files ()
  "Get a tag-list for current source-file. This is done via the
`speedbar-fetch-dynamic-tags' mechanism which supports imenu and etags."
  (require 'imenu)
  (if (member major-mode ecb-non-semantic-exclude-modes)
      nil
    (let* ((lst (let ((speedbar-dynamic-tags-function-list
                       (if (not (assoc major-mode
                                       ecb-non-semantic-parsing-function))
                           (list (cons 'speedbar-fetch-dynamic-imenu 'identity)
                                 (cons 'speedbar-fetch-dynamic-etags 'identity))
                         (list (cons (cdr (assoc major-mode
                                                 ecb-non-semantic-parsing-function))
                                     'identity)))))
                  (speedbar-fetch-dynamic-tags (buffer-file-name
                                                (current-buffer)))))
           (tag-list (cdr lst))
           (methods speedbar-tag-hierarchy-method))
    
      ;; removing the imenu-Rescan-item
      (if (string= (car (car tag-list)) (car imenu--rescan-item))
          (setq tag-list (cdr tag-list)))
      ;; If imenu or etags returns already groups (etags will do this probably
      ;; not, but imenu will do this sometimes - e.g. with cperl) then we do not
      ;; regrouping with the speedbar-methods of
      ;; `speedbar-tag-hierarchy-method'!
      (when (dolist (tag tag-list t)
              (if (or (speedbar-generic-list-positioned-group-p tag)
                      (speedbar-generic-list-group-p tag))
                  (return nil)))
        (while methods
          (setq tag-list (funcall (car methods) tag-list)
                methods (cdr methods))))
      tag-list)))


(silentcomp-provide 'ecb-speedbar)

;;; ecb-speedbar.el ends here