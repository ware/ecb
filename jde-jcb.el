;;; jde-jcb.el --- a code browser

;; Copyright (C) 2000 Jesper Nordenberg

;; Author: Jesper Nordenberg <mayhem@home.se>
;; Maintainer: Jesper Nordenberg <mayhem@home.se>
;; Keywords: java, class, browser
;; Created: Jul 2000
;; Version: 0.04

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:
;;
;; The Emacs code browser (ECB) creates four buffers: *ECB Directories*,
;; *ECB Sources*, *ECB Methods* and *ECB History*. These buffers can be
;; used to navigate through source code by clicking the left mouse
;; button.
;;
;; To use the Emacs code browser add the ECB files to your load path
;; and add the following line to your .emacs file:
;;
;; (require 'jde-jcb)
;;
;; ECB requires version 1.2.1 or higher of Eric's semantic bovinator
;; (http://www.ultranet.com/~zappo/semantic.shtml).
;; If you are working with Java ECB works best when the JDE package
;; (http://sunsite.auc.dk/jde) is installed.
;; 
;; ECB is activated by calling:
;;
;; (ecb-activate)
;;
;; To use the ECB you must add source paths in the customizations.
;; Customization is accessed by pressing F2 in the directories buffer or
;; with "M-x customize-group ecb".
;;
;; Clicking on a source or method using mouse button 2 causes the file to
;; be loaded in another window.
;;
;; Clicking on a source or directory using mouse button 3 activates a pop-up
;; menu where sources and directories can be created and deleted. Note that
;; it's the item that is clicked, not highlighted, that is the target for
;; the selected operation.
;;
;; TODO:
;; - Fix XEmacs incompatibilities (I need help on this one!)
;; - More layouts
;; - More functions on the pop-up menus. Suggestions are welcome!
;; - Syntax highlighting in methods buffer
;; - Lots more...
;;
;; The latest version of the ECB is available at
;; http://home.swipnet.se/mayhem/javabrowser.html

;;; Code:

(require 'semantic)
(require 'semantic-el)
(require 'semantic-c)
(require 'tree-buffer)
(require 'jde-jcb-layout)
(require 'jde-jcb-util)

(eval-when-compile
  ;; to avoid compiler grips
  (require 'cl))

;;====================================================
;; Variables
;;====================================================
(defvar ecb-methods nil
  "The currently selected method.")
(defvar ecb-selected-method-start 0
  "The currently selected method.")
(defvar ecb-path-selected-directory nil
  "Path to currently selected directory.")
(defvar ecb-path-selected-source nil
  "Path to currently selected source.")

(defvar ecb-directories-buffer-name "*ECB Directories*")
(defvar ecb-sources-buffer-name "*ECB Sources*")
(defvar ecb-methods-buffer-name "*ECB Methods*")
(defvar ecb-history-buffer-name "*ECB History*")
(defvar ecb-activated nil
  "Do not set this variable directly. Use `ecb-activate' and
`ecb-deactivate'!")

;;====================================================
;; Customization
;;====================================================
(defgroup ecb nil
  "Emacs code browser."
  :group 'tools
  :prefix "ecb-")

(defgroup ecb-general nil
  "General settings for the Emacs code browser."
  :group 'ecb
  :prefix "ecb-")

(defgroup ecb-directories nil
  "Settings for the directories buffer in the Emacs code browser."
  :group 'ecb
  :prefix "ecb-")

(defgroup ecb-sources nil
  "Settings for the source buffers in the Emacs code browser."
  :group 'ecb
  :prefix "ecb-")

(defgroup ecb-methods nil
  "Settings for the methods buffer in the Emacs code browser."
  :group 'ecb
  :prefix "ecb-")

(defcustom ecb-source-path nil
  "Path where to find code sources."
  :group 'ecb-directories
  :set '(lambda(symbol value)
	  (set symbol (mapcar (lambda (path)
                                (ecb-strip-slash path))
                              value))
	  (if (and ecb-activated
                   (functionp 'ecb-update-directories-buffer))
	      (ecb-update-directories-buffer)))
  :type '(repeat (directory :tag "Path")))

(defcustom ecb-show-sources-in-directories-buffer nil
  "Show source files in directories buffer."
  :group 'ecb-directories
  :type 'boolean)

(defface ecb-sources-face
  '((((class color) (background light)) (:foreground "medium blue"))
    (((class color) (background dark))  (:foreground "LightBlue1"))
    (t (:background "gray")))
  "Define a face for displaying sources in the directories buffer."
  :group 'faces
  :group 'ecb-directories)

(defcustom ecb-source-in-directories-buffer-face
  'ecb-sources-face
  "Face for source files in the directories buffer."
  :group 'ecb-directories
  :type 'face)

(defcustom ecb-directory-indent 2
  "Indent size for directories."
  :group 'ecb-directories
  :type 'integer)

(defcustom ecb-directory-expand-symbol-before nil
  "Show the directory expand symbol before the directory name."
  :group 'ecb-directories
  :type 'boolean)

(defcustom ecb-excluded-directories-regexp ".*CVS.*"
  "Specifies directories that should not be included in the directories list.
The value of this variable should be a regular expression."
  :group 'ecb-directories
  :type 'regexp)

(defcustom ecb-source-file-regexp ".*\\.\\(java\\|el\\|c\\|cc\\|h\\|hh\\|txt\\|html\\)$"
  "Files matching this regular expression will be added to the source buffer."
  :group 'ecb-sources
  :type 'regexp)

(defcustom ecb-show-source-file-extension t
  "Show the file extension of source files."
  :group 'ecb-sources
  :type 'boolean)

(defcustom ecb-sort-history-items nil
  "Sorts the items in the history buffer."
  :group 'ecb-sources
  :type 'boolean)

(defcustom ecb-show-method-argument-types t
  "Show method argument types."
  :group 'ecb-methods
  :type 'boolean)

(defcustom ecb-show-method-return-type nil
  "Show method return type."
  :group 'ecb-methods
  :type 'boolean)

(defcustom ecb-sort-methods t
  "Sort the contents of the methods buffer." 
  :group 'ecb-methods
  :type 'boolean) 

(defcustom ecb-truncate-lines t
  "Truncate lines in ECB buffers."
  :group 'ecb-general
  :type 'boolean)

(defcustom ecb-window-sync t
  "Synchronize ECB with edit window."
  :group 'ecb-general
  :type 'boolean)

(defcustom ecb-activate-before-layout-draw-hook nil
  "*Normal hook run at the end of activating the ecb-package by running
`ecb-activate'. This hooks are run after all the internal setup process
but directly before(!) drawing the layout specified in `ecb-layout' \(means
before dividing the frame into several windows).
A senseful using of this hook can be maximizing the Emacs-frame for example,
because this should be done before the layout is drawn because ECB computes
the size of the ECB-windows with the current frame size!
If you need a hook-option for the real end of the activating process (i.e.
after the layout-drawing) look at `ecb-activate-hook'."
  :group 'ecb-general
  :type 'hook)

(defcustom ecb-activate-hook nil
  "*Normal hook run at the end of activating the ecb-package by running
`ecb-activate'. This hooks are run at the real end of the activating
process, means after the layout has been drawn!. If you need hooks which are
run direct before the layout-drawing look at
`ecb-activate-before-layout-draw-hook'."
  :group 'ecb-general
  :type 'hook)

(defcustom ecb-deactivate-hook nil
  "*Normal hook run at the end of deactivating the ecb-package by running
`ecb-deactivate'."
  :group 'ecb-general
  :type 'hook)

;;====================================================
;; Methods
;;====================================================
(defun ecb-get-method-sig(method-token)
  (let ((method-type (semantic-token-type method-token)))
    (concat
     (if (and ecb-show-method-return-type
	      (> (length method-type) 0))
	 (concat (if (listp method-type)
		     (car method-type) method-type) " ")
       "")
     (semantic-token-name method-token)
     "("
     (if ecb-show-method-argument-types
	 (condition-case nil
	     (mapconcat
	      (lambda(method-arg-token)
		(let ((method-arg-type (semantic-token-type method-arg-token)))
		  (if (listp method-arg-type)
		      (car method-arg-type)
		    method-arg-type)))
	      (semantic-token-function-args method-token) ",")
	   (error nil)))
     ")")))
  
(defun ecb-default-get-methods()
;  (save-current-buffer
;    (bovinate))
  (let* ((tokens (condition-case nil
                     ;; semantic <= 1.2.1
                     (semantic-bovinate-toplevel 0 nil t)
                   (wrong-number-of-arguments
                    ;; semantic >= 1.3.1
                    (semantic-bovinate-toplevel t))))
         (source (car (semantic-find-nonterminal-by-token 'type tokens)))
	 (source-parts (semantic-token-type-parts source))
	 (methods
	  (semantic-find-nonterminal-by-token
	   'function
	   (if source-parts source-parts tokens))))
    (setq ecb-methods
	  (mapcar (lambda(method) (cons (semantic-token-start method)
					(semantic-token-end method)))
		  methods))
    (if ecb-sort-methods
	(setq methods (sort methods (lambda(a b)
				      (string< (semantic-token-name a)
					       (semantic-token-name b))))))
    (mapcar
     (lambda(method-token)
       (cons
	(ecb-get-method-sig method-token)
	(semantic-token-start method-token)))
     methods)))

(defun ecb-set-selected-directory(path)
  (setq path (ecb-strip-slash path))
  (setq ecb-path-selected-directory path)
  
  (when (not ecb-show-sources-in-directories-buffer)
    (save-selected-window
      (if (get-buffer-window ecb-directories-buffer-name)
	  (pop-to-buffer ecb-directories-buffer-name))
      (tree-buffer-highlight-node-data ecb-path-selected-directory)))

  (ecb-buffer-select ecb-sources-buffer-name)
  (let ((old-children (tree-node-get-children (tree-buffer-get-root))))
    (tree-node-set-children (tree-buffer-get-root) nil)
    (ecb-tree-node-add-files
     (tree-buffer-get-root)
     path
     (directory-files ecb-path-selected-directory nil ecb-source-file-regexp)
     0
     ecb-show-source-file-extension
     old-children t))
  (tree-buffer-update))
			       
(defun ecb-get-source-name(filename)
  "Returns the source name of a file."
  (let ((f (file-name-nondirectory filename)))
    (if ecb-show-source-file-extension
	f
      (file-name-sans-extension f))))
  
(defun ecb-select-source-file(filename)
  "Updates the directories, sources and history buffers to match the filename given."
  (save-current-buffer
    (ecb-set-selected-directory (file-name-directory filename))
    (setq ecb-path-selected-source filename)
    (let ((node (tree-node-find-child-data (tree-buffer-get-root)
					   ecb-path-selected-source)))
      (save-selected-window
	(when ecb-show-sources-in-directories-buffer
	  (if (get-buffer-window ecb-directories-buffer-name)
	      (pop-to-buffer ecb-directories-buffer-name))
	  (tree-buffer-highlight-node-data ecb-path-selected-source))
	(if (get-buffer-window ecb-sources-buffer-name)
	    (pop-to-buffer ecb-sources-buffer-name))
	(tree-buffer-highlight-node-data ecb-path-selected-source))

      (ecb-buffer-select ecb-history-buffer-name)
      (let ((child (tree-node-find-child-data
		    (tree-buffer-get-root) ecb-path-selected-source)))
	(when child
	    (tree-node-remove-child
	     (tree-buffer-get-root) child))
	(tree-node-set-children
	 (tree-buffer-get-root)
	 (let ((history-items
		(cons
		 (tree-node-new (tree-node-get-name node) 0
				ecb-path-selected-source t
				(tree-buffer-get-root))
		 (tree-node-get-children (tree-buffer-get-root)))))
	   (if ecb-sort-history-items
	       (sort history-items
		     (function (lambda (l r) (string< (tree-node-get-name l)
						      (tree-node-get-name r)))))
	     history-items)))
	(setq tree-buffer-highlighted-node-data ecb-path-selected-source)
	(tree-buffer-update)))))

(defun ecb-update-methods-buffer()
  "Updates the methods buffer with the current buffer."
  (let ((methods (ecb-default-get-methods)))
    (save-selected-window
      (ecb-buffer-select ecb-methods-buffer-name)
      (let ((node (tree-buffer-get-root)))
	(tree-node-set-children node nil)
	(dolist (method methods)
	  (tree-node-add-child node (tree-node-new (car method) 0 (cdr method) t))))
      (tree-buffer-update)
      (set-window-point (selected-window) 1))))
  
(defun ecb-set-selected-source(filename &optional window-skips
					   no-edit-buffer-selection)
  "Updates all the ECB buffers and loads the file. The file is also
  displayed unless NO-EDIT-BUFFER-SELECTION is set to non nil. In such case
  the file is only loaded invisible in the background, all semantic-parsing
  and ECB-Buffer-updating is done but the content of the main-edit window
  is not changed."
  (ecb-select-source-file filename)
  (if no-edit-buffer-selection
      ;; load the selected source in an invisible buffer, do all the
      ;; updating and parsing stuff with this buffer in the background and
      ;; display the methods in the METHOD-buffer. We can not go back to
      ;; the edit-window because then the METHODS buffer would be
      ;; immediately updated with the methods of the edit-window.
      (save-selected-window
        (save-excursion
          (set-buffer (find-file-noselect ecb-path-selected-source))
          (ecb-update-methods-buffer)))
    ;; open the selected source in the edit-window and do all the update and
    ;; parsing stuff with this buffer
    (ecb-find-file-and-display ecb-path-selected-source
                                   window-skips)
    (ecb-update-methods-buffer)))

(defun ecb-select-method(method-start)
  (setq ecb-selected-method-start method-start)
  (when (get-buffer-window ecb-methods-buffer-name)
    (save-excursion
      (ecb-buffer-select ecb-methods-buffer-name)
      (tree-buffer-highlight-node-data ecb-selected-method-start))))

(defun ecb-get-method-start-at-point()
  (catch 'exit
    (let ((pos (point)))
      (dolist (method ecb-methods)
	(if (and (>= pos (car method))
		 (<= pos (cdr method)))
	    (throw 'exit (car method)))))))


;; Klaus: The new feature for clearing the history is not yet ready for
;; release! Therefore the next two functions are commented out.

;; (defun ecb-remove-from-history (node-data)
;;   (let ((node (tree-node-find-child-data
;;                (tree-buffer-get-root) node-data)))
;;     (when node
;;       (tree-node-remove-child (tree-buffer-get-root) node))))
  

;; (defun ecb-clear-history ()
;;   (interactive)
;;   (ecb-buffer-select ecb-history-buffer-name)
;;   (let ((buffer-file-name-list (mapcar (lambda (buff)
;;                                          (buffer-file-name buff))
;;                                        (buffer-list)))
;;         (tree-childs (tree-node-get-children (tree-buffer-get-root)))
;;         child-data child)
;;     (while tree-childs
;;       (setq child-data (tree-node-get-data (car tree-childs)))
;;       (if (not (member child-data buffer-file-name-list))
;;           (ecb-remove-from-history child-data))
;;       (setq tree-childs (cdr tree-childs))))
;;   (tree-buffer-update))

(defun ecb-current-buffer-sync(&optional opt-buffer)
  "Synchronizes the ECB buffers with the current buffer."
  (interactive)
  (let ((filename (buffer-file-name (if opt-buffer opt-buffer (current-buffer)))))
    (when (and filename (not (string= filename ecb-path-selected-source)))
      (ecb-select-source-file filename)
      (ecb-update-methods-buffer))))
    ;; Doesnt work with selections
    ;; (let ((method-start (ecb-get-method-start-at-point)))
    ;;      (when (not (equal method-start ecb-selected-method-start))
    ;;	(ecb-select-method (ecb-get-method-start-at-point))))))

(defun ecb-find-file-and-display(filename &optional window-skips)
  "Finds the file in the correct window."
  (select-window ecb-edit-window)
  (if window-skips
      (other-window window-skips))
  (find-file ecb-path-selected-source)
  (pop-to-buffer (buffer-name)))

(defun ecb-switch-to-edit-buffer()
  (select-window ecb-edit-window))
  
(defun ecb-get-directories(path)
  (let ((files (directory-files path nil "^[^.].*"))
	dirs)
    (dolist (file files dirs)
      (if (and (file-accessible-directory-p (concat path "/" file))
	       (not (string-match ecb-excluded-directories-regexp file)))
	  (setq dirs (list-append dirs (list file)))))))

(defun ecb-tree-node-add-files
  (node path files type include-extension old-children &optional not-expandable)
  (dolist (file files)
    (let ((filename (concat path "/" file))
	  child)
      (tree-node-add-child
       node
       (ecb-new-child
	old-children
	(if include-extension
	    file
	  (file-name-sans-extension file))
	type filename (or not-expandable (= type 1)))))))
  
(defun ecb-update-directory-node(node)
  (let ((old-children (tree-node-get-children node))
	(path (tree-node-get-data node)))
    (tree-node-set-children node nil)
    (if (file-accessible-directory-p path)
	(let ((files (directory-files path nil "^[^.].*"))
	      dirs normal-files)
	  (dolist (file files)
	    (let ((filename (concat path "/" file)))
	      (if (file-accessible-directory-p filename)
		  (if (not (string-match ecb-excluded-directories-regexp file))
		      (setq dirs (list-append dirs (list file))))
		(if (string-match ecb-source-file-regexp file)
		    (setq normal-files (list-append normal-files (list file)))))))
	  (ecb-tree-node-add-files node path dirs 0 t old-children)
	  (if ecb-show-sources-in-directories-buffer
	      (ecb-tree-node-add-files node path normal-files 1
					   ecb-show-source-file-extension
					   old-children))
	  (tree-node-set-expandable node (or (tree-node-get-children node)))))))

(defun ecb-update-directories-buffer()
  "Updates the ECB directories buffer."
  (interactive)
  (save-current-buffer
    (ecb-buffer-select ecb-directories-buffer-name)
    (setq tree-buffer-type-faces
	  (list (cons 1 ecb-source-in-directories-buffer-face)))
    (setq tree-buffer-indent ecb-directory-indent)
    (let* ((node (tree-buffer-get-root))
	   (old-children (tree-node-get-children node)))
      (tree-node-set-children node nil)
      (if ecb-source-path
	  (progn
	    (dolist (dir ecb-source-path)
	      (tree-node-add-child node (ecb-new-child old-children dir 0 dir)))
	    (tree-buffer-update))
	(progn
	  (erase-buffer)
	  (insert "No source paths set.\nPress F2 to customize."))))))

(defun ecb-new-child(old-children name type data &optional not-expandable)
  (catch 'exit
    (dolist (child old-children)
      (when (and (equal (tree-node-get-data child) data)
		 (= (tree-node-get-type child) type))
	(tree-node-set-name child name)
	(if not-expandable
	    (tree-node-set-expandable child nil))
	(throw 'exit child)))
    (tree-node-new name type data not-expandable)))

(defun ecb-buffer-select(name)
  (set-buffer (get-buffer name)))

;;====================================================
;; Mouse functions
;;====================================================
(defun ecb-directory-clicked(node mouse-button shift-pressed)
  (ecb-update-directory-node node)
  (if (= 0 (tree-node-get-type node))
      (progn
	(when (= 1 mouse-button)
	  (tree-node-toggle-expanded node))
	(ecb-set-selected-directory (tree-node-get-data node))
	(ecb-buffer-select ecb-directories-buffer-name)
	(tree-buffer-update))
    (ecb-set-selected-source (tree-node-get-data node)
				(if ecb-layout-edit-window-splitted
				    mouse-button 0)
				shift-pressed)))

(defun ecb-source-clicked(node mouse-button shift-pressed)
  (ecb-set-selected-source (tree-node-get-data node)
			      (if ecb-layout-edit-window-splitted
				  mouse-button 0)
			      shift-pressed))

(defun ecb-method-clicked(node mouse-button shift-pressed)
  (ecb-find-file-and-display ecb-path-selected-source
		     (if ecb-layout-edit-window-splitted
			 mouse-button 0))
  (goto-char (tree-node-get-data node)))

;;====================================================
;; Create buffers & menus
;;====================================================

(defun ecb-activate ()
  "Activates the ECB and creates all the buffers and draws the ECB-screen
with the actually choosen layout \(see `ecb-layout')."
  (interactive)
  (if ecb-activated
      (ecb-redraw-layout)
    (let ((curr-buffer-list (mapcar (lambda (buff)
                                      (buffer-name buff))
                                    (buffer-list))))
      ;; create all the ECB-buffers if they don�t already exist
      (unless (member ecb-directories-buffer-name curr-buffer-list)
        (tree-buffer-create
         ecb-directories-buffer-name
         'ecb-directory-clicked
         'ecb-update-directory-node
         (list (cons 0 ecb-directories-menu) (cons 1 ecb-sources-menu))
         ecb-truncate-lines
	 ecb-directory-expand-symbol-before)
        ;; if we want some keys only defined in a certain tree-buffer we
        ;; must do this directly after calling the tree-buffer-create
        ;; function because this function makes the tree-buffer-key-map
        ;; variable buffer-local for its tree-buffer and creates the sparse
        ;; keymap.
        (define-key tree-buffer-key-map [f1] 'ecb-update-directories-buffer)
        (define-key tree-buffer-key-map [f2]
          '(lambda()
             (interactive)
             (ecb-switch-to-edit-buffer)
             (customize-group 'ecb))))        

      (unless (member ecb-sources-buffer-name curr-buffer-list)
        (tree-buffer-create
         ecb-sources-buffer-name
         'ecb-source-clicked
         'ecb-source-clicked
         (list (cons 0 ecb-sources-menu))
         ecb-truncate-lines))

      (unless (member ecb-methods-buffer-name curr-buffer-list)
        (tree-buffer-create
         ecb-methods-buffer-name
         'ecb-method-clicked
         'ecb-method-clicked
         nil
         ecb-truncate-lines))
      
      (unless (member ecb-history-buffer-name curr-buffer-list)
        (tree-buffer-create
         ecb-history-buffer-name
         'ecb-source-clicked
         'ecb-source-clicked
         ecb-sources-menu
         ecb-truncate-lines)))

    ;; we need some hooks
    (remove-hook 'post-command-hook 'ecb-hook)
    (add-hook 'post-command-hook 'ecb-hook)
    ;; we add a function to this hook at the end because this function should
    ;; be called at the end of all hook-functions of this hook!
    (add-hook 'compilation-finish-functions
              'ecb-layout-return-from-compilation t)
    (add-hook 'compilation-mode-hook
              'ecb-layout-go-to-compile-window)
    (setq ecb-activated t)
    ;; we must update the directories buffer first time
    (ecb-update-directories-buffer)
    ;; run personal hooks before drawing the layout
    (run-hooks 'ecb-activate-before-layout-draw-hook)
    ;; now we draw the layout choosen in `ecb-layout'.
    (ecb-redraw-layout)
    ;; at the real end we run any personal hooks
    (run-hooks 'ecb-activate-hook))
  (message "The ECB is now activated."))

(defun ecb-deactivate ()
  "Deactivates the ECB and kills all ECB buffers and windows."
  (interactive)
  (unless (not ecb-activated)
    ;; first we delete all ECB-windows.
    (if ecb-edit-window
	(ecb-switch-to-edit-buffer))
    
    (delete-other-windows)
    ;; we can safely do the kills because killing non existing buffers
    ;; doesn�t matter.
    (kill-buffer ecb-directories-buffer-name)
    (kill-buffer ecb-sources-buffer-name)
    (kill-buffer ecb-methods-buffer-name)
    (kill-buffer ecb-history-buffer-name)
    ;; remove the hooks
    (remove-hook 'post-command-hook 'ecb-hook)
    (remove-hook 'compilation-finish-functions
                 'ecb-layout-return-from-compilation)
    (remove-hook 'compilation-mode-hook
                 'ecb-layout-go-to-compile-window)
    (setq ecb-activated nil)
    ;; run any personal hooks
    (run-hooks 'ecb-deactivate-hook))
  (message "The ECB is now deactivated."))

(defvar ecb-directories-menu nil)
(setq ecb-directories-menu (make-sparse-keymap "Directory Menu"))
(define-key ecb-directories-menu [ecb-create-file] '("Create File" . t))
(define-key ecb-directories-menu [ecb-create-directory-source]
  '("Create Source" . t))
(define-key ecb-directories-menu [ecb-delete-directory]
  '("Delete Directory" . t))
(define-key ecb-directories-menu [ecb-create-directory]
  '("Create Child Directory" . t))

(defvar ecb-sources-menu nil)
(setq ecb-sources-menu (make-sparse-keymap "Source Menu"))
(define-key ecb-sources-menu [ecb-delete-source-2] '("Delete Source" . t))
(define-key ecb-sources-menu [ecb-create-file-2] '("Create File" . t))
(define-key ecb-sources-menu [ecb-create-source-2] '("Create Source" . t))

(defun ecb-hook()
  (if (and ecb-window-sync (eq (selected-frame) ecb-frame))
      (condition-case nil
	  (ecb-current-buffer-sync)
	(error nil))))

(provide 'jde-jcb)

;;; jcb.el ends here