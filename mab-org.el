;;; mab-org.el --- Org-mode helpers for modular annotated bibliographies -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Blaine Mooers

;; Author: Blaine Mooers <blaine-mooers@ou.edu>
;; Maintainer: Blaine Mooers <blaine-mooers@ou.edu>
;; Department: Biochemistry and Physiology
;; Institution: University of Oklahoma Health Campus
;; URL: https://github.com/MooersLab/mab-org
;; Version: 0.4.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: bib, tex, org, citar, ebib, bibliography, tools

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; mab-org bundles the helpers used to assemble manuscript-style
;; modular annotated bibliographies (mab) and lighter-weight annotated
;; bibliographies (abib) inside Org-mode buffers.
;;
;; What the package does
;;
;;   - Wraps citar (and ebib) citekeys with LaTeX `\bibentry' code,
;;     creates per-citekey Org notes, optionally appends the BibTeX
;;     entry to a project-specific .bib file, and bulk-applies the
;;     same wrapping to every citation in a region.
;;
;;   - Detects when a per-citekey note already exists (for example
;;     because it was created during work on another project) and
;;     offers to reuse it, create a variant with a letter suffix, or
;;     quit without changing the buffer.
;;
;;   - Stamps out a `mab<NUMBER>/mab<NUMBER>.org' project file from
;;     a built-in template, with the LaTeX preamble already in place.
;;
;;   - Adds the wrapped block to a mab project file directly from
;;     ebib, by binding `B' in `ebib-index-mode' to the new command
;;     `mab-org-add-bib-item'.
;;
;; Public commands
;;
;;     `mab-org-wrap-citekey'         (mab style; links visible)
;;     `mab-org-wrap-citekey-abib'    (abib style; links inside COMMENT)
;;     `mab-org-wrap-region'          (bulk wrap)
;;     `mab-org-insert-matching-keys' (search the global bib)
;;     `mab-org-create-project'       (stamp out a new mab project)
;;     `mab-org-open-file'            (find or create a mab project)
;;     `mab-org-add-bib-item'         (append from inside ebib)

;;; Code:

(require 'bibtex)
(require 'subr-x)

;;;; Customization

(defgroup mab-org nil
  "Org-mode helpers for modular annotated bibliographies."
  :group 'tex
  :prefix "mab-org-")

(defcustom mab-org-notes-directory
  (expand-file-name "~/abibNotes/")
  "Directory that holds per-citekey Org notes."
  :type 'directory
  :group 'mab-org)

(defcustom mab-org-pdfs-directory
  (expand-file-name "~/0papersLabeled/")
  "Directory that holds renamed article PDFs."
  :type 'directory
  :group 'mab-org)

(defcustom mab-org-books-directory
  (expand-file-name "~/0booksLabeled/")
  "Directory that holds renamed book PDFs.
A second file link is added to every wrapped block so that note
entries that came from a book can be reached without changing the
template."
  :type 'directory
  :group 'mab-org)

(defcustom mab-org-global-bib-file
  (expand-file-name "~/Documents/global.bib")
  "Path to the global BibTeX library.
Searched by `mab-org-insert-matching-keys'."
  :type 'file
  :group 'mab-org)

(defcustom mab-org-region-confirm-threshold 10
  "Maximum number of citations in a region wrapped without prompting.
When `mab-org-wrap-region' finds more citations than this in the
active region, the user is asked to confirm before any work
begins."
  :type 'integer
  :group 'mab-org)

(defcustom mab-org-book-entry-regexp "\\`[[:space:]]*@book"
  "Regexp identifying a book-like BibTeX entry.
Matched against the raw entry text (case-insensitively).  When
the entry for a citekey matches this regexp, the wrapped block
links to `mab-org-books-directory'; otherwise it links to
`mab-org-pdfs-directory'.  The default catches `@book' and
`@booklet' through prefix match.  Extend it (for example to
\"\\\\`[[:space:]]*@\\\\(book\\\\|inbook\\\\|incollection\\\\)\")
to cover further types."
  :type 'regexp
  :group 'mab-org)

(defcustom mab-org-base-directory nil
  "Default base directory under which mab project files live.
When nil, `mab-org-create-project' falls back to the directory of
the current buffer (or `default-directory' when there is no
buffer file)."
  :type '(choice (const :tag "Use current directory" nil) directory)
  :group 'mab-org)

(defcustom mab-org-mab-path nil
  "Default destination for `mab-org-add-bib-item'.
This is the absolute path of the mab project Org file to which
ebib entries are appended.  When nil, the user is prompted with
no default.

The variable is updated automatically when
`mab-org-add-bib-item' is called interactively, so the most
recent choice persists for the rest of the session."
  :type '(choice (const :tag "No default" nil) file)
  :group 'mab-org)

;;;; Pure helpers

(defconst mab-org--cite-block-regexp "\\[cite:@[^]]+\\]"
  "Regexp matching a complete citar/org-cite citation block.
The match has no capture groups; the entire bracketed expression
is in match group 0.  Used to count and locate citations in a
region or buffer.")

(defconst mab-org--cite-key-regexp "\\[cite:@\\([^],; ]+\\)"
  "Regexp matching the first citekey within a citar/org-cite block.
The first capture group is the citekey itself, with no leading
\"@\" or surrounding brackets.  Multi-key citations such as
[cite:@a,@b] or [cite:@a;@b] yield only the first key.")

(defun mab-org--extract-citekey-from-text (text)
  "Return the first citekey found in TEXT, or TEXT itself if none.
A citekey is matched by `mab-org--cite-key-regexp'.  When TEXT
looks like a bare word (no [cite:@ wrapper), TEXT is returned
unchanged so that callers can pass either form."
  (when (stringp text)
    (if (string-match mab-org--cite-key-regexp text)
        (match-string 1 text)
      text)))

(defun mab-org--default-project-number-from-filename (filename)
  "Return the default project number derived from FILENAME.
Tries the following patterns, in order, and returns the first
match.

  1.  An \"ab\" or \"mab\" prefix followed by digits and \".org\".
  2.  Any run of digits anywhere in the basename.

If FILENAME is nil or no digits are found, return the empty
string."
  (let ((base (and filename (file-name-nondirectory filename))))
    (cond
     ((null base) "")
     ((string-match "m?ab\\([0-9]+\\)\\.org" base)
      (match-string 1 base))
     ((string-match "\\([0-9]+\\)" base)
      (match-string 1 base))
     (t ""))))

(defun mab-org--render-mab-wrapped-text (citekey &optional note-stem book-p)
  "Return the mab-style LaTeX-wrapped replacement string for CITEKEY.
NOTE-STEM, when non-nil, is the stem used in place of CITEKEY for
the per-note Org file.  This supports variant notes such as
CITEKEYa.org when one citekey is annotated more than once.

When BOOK-P is non-nil, the inserted PDF link points at
`mab-org-books-directory' and is labeled \"book PDF\".
Otherwise the link points at `mab-org-pdfs-directory' and is
labeled \"article PDF\".  Only one PDF link is emitted; the
choice is the caller's responsibility (typically derived from
`mab-org--book-entry-p').

The block carries the LaTeX `\\bibentry' command, the
table-of-contents line, an `#+INCLUDE:' directive, the link to
the per-note Org file, and the chosen PDF link.  The links are
written as bare lines rather than inside a Notes drawer, so they
remain visible in the exported document.

The LaTeX `\\bibentry' command and the PDF link always use the
original CITEKEY, because the BibTeX library and the PDF/book
archives are keyed by citekey.  The table-of-contents entry, the
INCLUDE directive, and the link to the per-note Org file all use
the stem, so a variant note appears as a distinct row in the
table of contents."
  (let* ((stem (or note-stem citekey))
         (notes-dir (file-name-as-directory mab-org-notes-directory))
         (pdf-dir (file-name-as-directory
                   (if book-p
                       mab-org-books-directory
                     mab-org-pdfs-directory)))
         (pdf-label (if book-p "book PDF" "article PDF")))
    (format
     (concat
      "#+LATEX: \\subsubsection*{\\bibentry{%s}}\n"
      "#+LATEX: \\addcontentsline{toc}{subsubsection}{%s}\n"
      "#+INCLUDE: %s%s.org\n"
      "The org-mode note is found [[file:%s%s.org][here]]\n"
      "The %s is found [[file:%s%s.pdf][here]]")
     citekey stem
     notes-dir stem
     notes-dir stem
     pdf-label pdf-dir citekey)))

(defun mab-org--render-abib-wrapped-text (citekey &optional note-stem book-p)
  "Return the abib-style LaTeX-wrapped replacement string for CITEKEY.
NOTE-STEM and BOOK-P behave as in
`mab-org--render-mab-wrapped-text'.  The result mirrors that
function but wraps the two file links inside an Org COMMENT
block so they do not appear in the exported document."
  (let* ((stem (or note-stem citekey))
         (notes-dir (file-name-as-directory mab-org-notes-directory))
         (pdf-dir (file-name-as-directory
                   (if book-p
                       mab-org-books-directory
                     mab-org-pdfs-directory))))
    (format
     (concat
      "#+LATEX: \\subsubsection*{\\bibentry{%s}}\n"
      "#+LATEX: \\addcontentsline{toc}{subsubsection}{%s}\n"
      "#+INCLUDE: %s%s.org\n"
      "#+BEGIN_COMMENT\n"
      "file:%s%s.org\n"
      "file:%s%s.pdf\n"
      "#+END_COMMENT")
     citekey stem
     notes-dir stem
     notes-dir stem
     pdf-dir citekey)))

(defun mab-org--collect-citation-positions (start end)
  "Return the start positions of every citation between START and END.
A citation is matched by `mab-org--cite-block-regexp'.  Positions
are returned in the order they appear in the buffer."
  (let ((positions '()))
    (save-excursion
      (goto-char start)
      (while (re-search-forward mab-org--cite-block-regexp end t)
        (push (match-beginning 0) positions)))
    (nreverse positions)))

;;;; Abibnote variant handling

(defun mab-org--note-path (stem directory)
  "Return the full path to STEM.org inside DIRECTORY."
  (expand-file-name (concat stem ".org") directory))

(defun mab-org--next-variant-letter (citekey directory)
  "Return the next available variant letter for CITEKEY in DIRECTORY.
Walks the alphabet in order and returns the first lowercase
character C for which no file CITEKEY<C>.org exists in
DIRECTORY.  Returns nil when every single-letter variant from a
through z is already taken."
  (catch 'next
    (dolist (letter (number-sequence ?a ?z))
      (unless (file-exists-p
               (mab-org--note-path
                (format "%s%c" citekey letter) directory))
        (throw 'next letter)))
    nil))

(defun mab-org--prompt-for-note-action (citekey next-letter)
  "Ask the user how to handle an existing CITEKEY.org note.
NEXT-LETTER, when non-nil, is the lowercase character that would
be appended to CITEKEY for the next variant.  Return one of the
symbols `reuse', `variant', or `quit'.

When NEXT-LETTER is nil, the variant option is omitted from the
prompt because every single-letter variant is already taken."
  (let* ((variant-desc (when next-letter
                         (format "Create a variant note as %s%c.org"
                                 citekey next-letter)))
         (choices `((?r "reuse"
                        "Reuse the existing note for this citekey")
                    ,@(when next-letter
                        `((?v "variant" ,variant-desc)))
                    (?q "quit" "Abort the wrap operation")))
         (answer (read-multiple-choice
                  (format "Note %s.org already exists" citekey)
                  choices)))
    (pcase (car answer)
      (?r 'reuse)
      (?v 'variant)
      (?q 'quit))))

(defun mab-org--resolve-note-stem (citekey directory)
  "Return the citekey stem for the abibnote in DIRECTORY.
If CITEKEY.org does not yet exist in DIRECTORY, return CITEKEY
unchanged.  Otherwise prompt the user via
`mab-org--prompt-for-note-action' and return CITEKEY (reuse), or
CITEKEY with the next available letter appended (variant), or
signal `user-error' (quit)."
  (let ((dir (file-name-as-directory directory)))
    (if (not (file-exists-p (mab-org--note-path citekey dir)))
        citekey
      (let* ((next-letter (mab-org--next-variant-letter citekey dir))
             (action (mab-org--prompt-for-note-action citekey next-letter)))
        (pcase action
          ('reuse citekey)
          ('variant
           (unless next-letter
             (user-error
              "All single-letter variants of %s are already taken"
              citekey))
           (format "%s%c" citekey next-letter))
          ('quit (user-error "Wrap aborted by user")))))))

(defun mab-org--ensure-note-file (stem)
  "Create an empty abibnote file for STEM if no note exists yet.
The file is written under `mab-org-notes-directory', and the
directory is created with `make-directory' when missing.  Returns
the absolute path to the note."
  (let* ((dir (file-name-as-directory mab-org-notes-directory))
         (path (mab-org--note-path stem dir)))
    (unless (file-directory-p dir)
      (make-directory dir t))
    (unless (file-exists-p path)
      (with-temp-file path (insert "")))
    path))

;;;; Project template

(defconst mab-org--template-string
  "#+Title: Annotated Bibliography for Project %s %s
#+Options: toc:nil author:nil
#+LATEX_COMPILER: lualatex
#+LaTeX_CLASS:article
#+LaTeX_CLASS_OPTIONS:[11pt,letterpaper,plainpages=false]
#+LaTeX_HEADER:\\usepackage[letterpaper, total={7in, 9in}]{geometry}
#+LaTeX_HEADER:\\usepackage{booktabs}
#+LaTeX_HEADER:\\usepackage{graphicx}
#+LaTeX_HEADER:\\usepackage{xurl} %% permit line breaks in urls
#+LaTeX_HEADER:\\usepackage{hyperref}
#+LaTeX_HEADER:\\usepackage{lineno}
#+LaTeX_HEADER:\\usepackage{datetime2}
#+LaTeX_HEADER:\\usepackage{breakcites} %% allow citation to wrap
#+LaTeX_HEADER:\\usepackage{makeidx}
#+LaTeX_HEADER:\\usepackage[utf8]{inputenc}
#+LaTeX_HEADER:\\usepackage{parskip}
#+LaTeX_HEADER:\\usepackage[T1]{fontenc}
#+LaTeX_HEADER:\\setmainfont{TeX Gyre Heros}
#+LaTeX_HEADER:\\usepackage{authblk}
#+LaTeX_HEADER:\\usepackage[labelfont=bf]{caption}
#+LaTeX_HEADER:\\DeclareCaptionType{equ}[][]
#+LaTeX_HEADER:\\usepackage[bottom]{footmisc}
#+LaTeX_HEADER:\\usepackage{amsfonts, mathtools, amssymb}
#+LaTeX_HEADER:\\usepackage{threeparttable}
#+LaTeX_HEADER:\\usepackage{wrapfig}
#+LaTeX_HEADER:\\pagestyle{myheadings}
#+LaTeX_HEADER:\\usepackage[user,totpages]{zref}
#+LaTeX_HEADER:\\usepackage{fancyhdr}
#+LaTeX_HEADER:\\pagestyle{fancy}
#+LaTeX_HEADER:\\fancyhf{}
#+LaTeX_HEADER:\\fancyhead[L]{\\today}
#+LaTeX_HEADER:\\fancyhead[C]{%s %s}
#+LaTeX_HEADER:\\fancyhead[R]{\\thepage\\ / \\ztotpages}
#+LaTeX_HEADER:\\setlength{\\headheight}{14pt}
#+LaTeX_HEADER:\\usepackage[acronym]{glossaries}
#+LaTeX_HEADER:\\usepackage[automake]{glossaries-extra}
#+LaTeX_HEADER:\\newglossary[nlg]{notation}{not}{ntn}{Notation}
#+LaTeX_HEADER:\\makeglossaries
#+LaTeX_HEADER:\\setabbreviationstyle[acronym]{long-short}
#+LaTeX_HEADER:\\loadglsentries{/Users/blaine/glossaries/acronyms}
#+LaTeX_HEADER:\\loadglsentries{/Users/blaine/glossaries/glossary}
#+LaTeX_HEADER:\\loadglsentries{/Users/blaine/glossaries/notation}
#+LaTeX_HEADER:\\bibliographystyle{cell}
#+LaTeX_HEADER:\\makeindex
#+LaTeX_HEADER:\\RequirePackage{authorindex}
#+LaTeX_HEADER:\\def\\theaipage{\\string\\hyperpage{\\thepage}}
#+LaTeX_HEADER:\\newcommand{\\listofauthorsname}{List of Authors}
#+LaTeX_HEADER:\\newcommand{\\listofauthors}
#+LaTeX_HEADER:\\phantomsection
#+LaTeX_HEADER:\\addcontentsline{toc}{chapter}{\\listofauthorsname}
#+LaTeX_HEADER:\\noindent
#+LaTeX_HEADER:\\printauthorindex
#+LaTeX_HEADER:\\setcounter{tocdepth}{2}
#+LaTeX_HEADER:\\renewcommand{\\refname}{Literature Cited}
#+LaTeX_HEADER:\\newenvironment{code}{\\captionsetup{type=listing}}{}
#+LaTeX_HEADER:\\usepackage{bibentry}
#+LaTeX_HEADER:\\renewcommand{\\familydefault}{\\sfdefault}
#+LaTeX_HEADER:\\modulolinenumbers[1]
#+LaTeX_HEADER:\\setlength{\\parindent}{0pt}
#+LaTeX_HEADER:\\author[1]{Graduate Student}
#+LaTeX_HEADER:\\author[2]{Senior Collaborator}
#+LaTeX_HEADER:\\author[3]{Staff Scientist}
#+LaTeX_HEADER:\\author[1,2,3]{Blaine Mooers\\thanks{blaine-mooers@ou.edu, phone: 405-271-8300}}
#+LaTeX_HEADER:\\affil[1]{Department of Biochemistry and Physiology, University of Oklahoma Health Campus, Oklahoma City, Oklahoma, United States 73104}
#+LaTeX_HEADER:\\affil[2]{Stephenson Cancer Center, University of Oklahoma Health Campus, Oklahoma City, Oklahoma, United States 73104}
#+LaTeX_HEADER:\\affil[3]{Laboratory of Biomolecular Structure and Function, University of Oklahoma Health Campus, Oklahoma City, Oklahoma, United States 73104}
#+LaTeX_HEADER:\\nobibliography*



#+LATEX:\\maketitle
#+LATEX:\\tableofcontents

#+LATEX: %% Unnumbered sections are invisible to the table of contents unless added with \\addcontentsline.
#+LATEX:\\section*{Illustrated and annotated bibliography}
#+LATEX:\\addcontentsline{toc}{section}{Illustrated and annotated bibliography}

# Insert wrapped citekeys below this line.

\\clearpage
#+LATEX: \\section*{Backmatter}

#+LATEX: \\glsaddall[types={main,\\acronymtype}]
#+LATEX: \\printglossary[type=\\acronymtype]
#+LATEX: \\addcontentsline{toc}{section}{Acronyms}

\\clearpage
#+LATEX: \\printglossary
#+LATEX: \\addcontentsline{toc}{section}{Glossary}

\\clearpage
#+LATEX: \\glsaddall[types={notation}]
#+LATEX: \\printglossary[type=notation, title=Mathematical Notation]
#+LATEX: \\addcontentsline{toc}{section}{Mathematical Notation}

#+LATEX: \\addcontentsline{toc}{section}{Literature Cited}
#+LATEX: \\bibliography{%s}

#+LATEX: \\addcontentsline{toc}{section}{Index}
#+LATEX: \\printindex
"
  "Format string for the mab project Org template.
The five `%s' placeholders are filled, in order, with project
number (title), project tag (title), project number again
(running header), project title (running header), and the
bibliography path used by the LaTeX `\\bibliography' command.")

(defun mab-org--render-template (project-number project-tag project-title bib-path)
  "Return the rendered Org template body.
PROJECT-NUMBER is the numeric project identifier (for example
\"0386\").  PROJECT-TAG is the short label that follows the
number in the document title (for example \"mpQcr\").
PROJECT-TITLE is the longer human-readable title used in the
running header (for example \"multipass QCr\").  BIB-PATH is the
path passed to LaTeX `\\bibliography'."
  (format mab-org--template-string
          project-number project-tag
          project-number project-title
          bib-path))

(defun mab-org--resolve-base-directory (override)
  "Return the base directory to use for `mab-org-create-project'.
OVERRIDE, when non-nil, is used directly.  Otherwise the value
falls back through `mab-org-base-directory', the directory of the
current buffer file, and `default-directory'."
  (file-name-as-directory
   (or override
       mab-org-base-directory
       (and (buffer-file-name)
            (file-name-directory (buffer-file-name)))
       default-directory)))

;;;###autoload
(defun mab-org-create-project (project-number project-tag project-title
                                              &optional base-dir bib-path)
  "Create a new mab project under BASE-DIR.

The new project lives in BASE-DIR/mab<PROJECT-NUMBER>/, and the
project file is mab<PROJECT-NUMBER>.org inside that directory.

PROJECT-TAG is the short tag that appears beside the number in
the document title (for example \"mpQcr\").  PROJECT-TITLE is the
longer name shown in the running page header (for example
\"multipass QCr\").  BIB-PATH is the path passed to LaTeX
`\\bibliography'.  When BIB-PATH is nil, `mab-org-global-bib-file'
is used (with any trailing .bib suffix stripped, because LaTeX
adds the suffix itself).

When BASE-DIR is omitted the package falls back to
`mab-org-base-directory', then to the directory of the current
buffer, then to `default-directory'.

The function refuses to overwrite an existing project file."
  (interactive
   (list (read-string "Project number (digits only): ")
         (read-string "Project short tag (used in title): ")
         (read-string "Project full title (used in running header): ")
         nil nil))
  (let* ((base (mab-org--resolve-base-directory base-dir))
         (sub-name (format "mab%s" project-number))
         (sub (file-name-as-directory (expand-file-name sub-name base)))
         (file (expand-file-name (concat sub-name ".org") sub))
         (bib (or bib-path
                  (replace-regexp-in-string
                   "\\.bib\\'" "" mab-org-global-bib-file)))
         (body (mab-org--render-template project-number
                                         project-tag
                                         project-title
                                         bib)))
    (when (file-exists-p file)
      (user-error "File already exists, refusing to overwrite: %s" file))
    (unless (file-directory-p sub)
      (make-directory sub t))
    (with-temp-file file
      (insert body))
    (when (called-interactively-p 'any)
      (find-file file))
    file))

;;;###autoload
(defun mab-org-open-file (project-number &optional base-dir)
  "Find or create a mab project file by PROJECT-NUMBER.
The file searched for is BASE-DIR/mab<PROJECT-NUMBER>/mab<PROJECT-NUMBER>.org.
When that file already exists it is opened.  When it does not
exist, the user is asked whether to create it from the template,
and if so prompted for a project tag and full title."
  (interactive (list (read-string "Project number: ") nil))
  (let* ((base (mab-org--resolve-base-directory
                (or base-dir
                    (and (called-interactively-p 'any)
                         (read-directory-name
                          "Base directory: "
                          (or mab-org-base-directory default-directory)
                          nil t)))))
         (sub-name (format "mab%s" project-number))
         (sub (file-name-as-directory (expand-file-name sub-name base)))
         (file (expand-file-name (concat sub-name ".org") sub)))
    (cond
     ((file-exists-p file)
      (find-file file))
     ((y-or-n-p (format "%s does not exist.  Create from template? " file))
      (let ((tag (read-string "Project short tag (used in title): "))
            (title (read-string "Project full title (used in running header): ")))
        (mab-org-create-project project-number tag title base)
        (find-file file)))
     (t (message "Operation canceled.")))))

;;;; Search the global bibliography

;;;###autoload
(defun mab-org-insert-matching-keys (term)
  "Prompt for a search TERM and insert citation keys for matching entries.
Searches `mab-org-global-bib-file' for BibTeX entries whose raw
text contains TERM (case-insensitive, plain substring match
across all fields including title, author, abstract, keywords,
and the citekey itself).  For each matching entry, insert one
line of the form

    [cite:@CITEKEY]

at point in the current buffer.  Returns the list of raw citekeys
without the [cite:@...] wrapping, so the function can also be
called from other Lisp."
  (interactive "sSearch term: ")
  (unless (file-readable-p mab-org-global-bib-file)
    (user-error "Cannot read %s" mab-org-global-bib-file))
  (let ((target-buffer (current-buffer))
        (matches '()))
    (with-temp-buffer
      (insert-file-contents mab-org-global-bib-file)
      (bibtex-mode)
      (let ((case-fold-search t))
        (bibtex-map-entries
         (lambda (key beg end)
           (let ((entry-text (buffer-substring-no-properties beg end)))
             (when (string-match-p (regexp-quote term) entry-text)
               (push key matches)))))))
    (setq matches (nreverse matches))
    (with-current-buffer target-buffer
      (if matches
          (progn
            (insert (mapconcat (lambda (k) (format "[cite:@%s]" k))
                               matches
                               "\n"))
            (insert "\n")
            (message "Inserted %d citation key(s) matching %S"
                     (length matches) term))
        (message "No entries matched %S" term)))
    matches))

;;;; Wrap citekeys

(defun mab-org--bounds-of-citekey-or-word ()
  "Return (BEG . END) for the citekey or word at point, or nil.
A citation is detected first by searching backward on the current
line for `[cite:@', then forward for the closing `]'.  When that
fails, fall back to `bounds-of-thing-at-point' for `word'."
  (or (save-excursion
        (let ((start (re-search-backward "\\[cite:@"
                                         (line-beginning-position) t))
              (end (re-search-forward "\\]"
                                      (line-end-position) t)))
          (when (and start end)
            (cons start end))))
      (bounds-of-thing-at-point 'word)))

(defun mab-org--read-bibtex-entry-from-citar (citekey)
  "Return the BibTeX entry text for CITEKEY by scanning citar bib files.
If `citar' is not loaded, or no entry is found, return nil."
  (when (featurep 'citar)
    (let ((bib-files (and (fboundp 'citar--bibliography-files)
                          (citar--bibliography-files)))
          (entry nil))
      (when bib-files
        (catch 'found
          (dolist (bib-file bib-files)
            (let ((found
                   (mab-org--read-bibtex-entry-from-bib-file
                    citekey bib-file)))
              (when found
                (setq entry found)
                (throw 'found t))))))
      entry)))

(defun mab-org--read-bibtex-entry-from-bib-file (citekey path)
  "Return the BibTeX entry text for CITEKEY from PATH, or nil.
PATH must be a readable file; otherwise nil is returned."
  (when (and citekey path (file-readable-p path))
    (with-temp-buffer
      (insert-file-contents path)
      (bibtex-mode)
      (bibtex-set-dialect 'BibTeX t)
      (goto-char (point-min))
      (when (re-search-forward
             (format "@[^{]+{%s," (regexp-quote citekey)) nil t)
        (let ((beg (save-excursion (bibtex-beginning-of-entry) (point)))
              (end (save-excursion (bibtex-end-of-entry) (point))))
          (buffer-substring-no-properties beg end))))))

(defun mab-org--lookup-bibtex-entry (citekey)
  "Return the BibTeX entry text for CITEKEY, or nil.
Searches `citar' first when it is loaded, then falls back to
`mab-org-global-bib-file'."
  (or (mab-org--read-bibtex-entry-from-citar citekey)
      (mab-org--read-bibtex-entry-from-bib-file
       citekey mab-org-global-bib-file)))

(defun mab-org--book-entry-p (entry-text)
  "Return non-nil when ENTRY-TEXT is a book-like BibTeX entry.
ENTRY-TEXT is matched against `mab-org-book-entry-regexp'
case-insensitively.  Returns nil when ENTRY-TEXT is nil or not a
string."
  (and (stringp entry-text)
       (let ((case-fold-search t))
         (string-match-p mab-org-book-entry-regexp entry-text))))

(defun mab-org--append-bibtex-entry (path entry)
  "Append BibTeX ENTRY text to PATH, preserving any existing content."
  (with-temp-file path
    (when (file-exists-p path)
      (insert-file-contents path))
    (goto-char (point-max))
    (unless (or (bobp) (bolp)) (insert "\n"))
    (insert entry "\n\n")))

;;;###autoload
(defun mab-org-wrap-citekey ()
  "Replace the citekey under the cursor with LaTeX-wrapped text.
Also create the per-citekey Org note in `mab-org-notes-directory'
if no note for that citekey exists yet.  Works with citekeys in
citar style, in LaTeX style, or as plain bare citekeys.

The LaTeX code uses the bibentry package to inject a
bibliographic entry into a section heading that is added to the
table of contents.  The function also adds bare file links to
the per-note Org file, the article PDF, and the book PDF.

When an abibnote for the citekey already exists (for example
because it was created during work on another project), the user
is prompted to (r)euse the existing note, create a (v)ariant by
appending the next available letter to the stem, or (q)uit
without changing the buffer."
  (interactive)
  (let* ((bounds (mab-org--bounds-of-citekey-or-word))
         (citation-text (when bounds
                          (buffer-substring-no-properties
                           (car bounds) (cdr bounds))))
         (citekey (mab-org--extract-citekey-from-text citation-text))
         (current-file (buffer-file-name))
         (current-dir (when current-file
                        (file-name-directory current-file)))
         (default-project-number
          (mab-org--default-project-number-from-filename current-file)))
    (cond
     ((not citekey)
      (message "No citekey found under the cursor."))
     (t
      (let* ((project-number
              (read-string (format "Project number for BibTeX file [%s]: "
                                   default-project-number)
                           nil nil default-project-number))
             (note-stem (mab-org--resolve-note-stem
                         citekey mab-org-notes-directory))
             (bibtex-entry (mab-org--lookup-bibtex-entry citekey))
             (book-p (mab-org--book-entry-p bibtex-entry))
             (mab-dir (concat "mab" project-number "/"))
             (mab-full-dir (and current-dir (concat current-dir mab-dir)))
             (bib-file-name (concat "mab" project-number ".bib"))
             (bib-file-path (and mab-full-dir
                                 (concat mab-full-dir bib-file-name)))
             (org-file-path (mab-org--note-path
                             note-stem mab-org-notes-directory))
             (wrapped-text (mab-org--render-mab-wrapped-text
                            citekey note-stem book-p)))
        (message "Using bibfile: %s" bib-file-path)
        (when bounds
          (delete-region (car bounds) (cdr bounds)))
        (insert wrapped-text)
        (mab-org--ensure-note-file note-stem)
        (when (and mab-full-dir (not (file-exists-p mab-full-dir)))
          (make-directory mab-full-dir t)
          (message "Created directory %s" mab-full-dir))
        (when (and mab-full-dir bib-file-path)
          (if bibtex-entry
              (progn
                (mab-org--append-bibtex-entry bib-file-path bibtex-entry)
                (message "Added BibTeX entry to %s" bib-file-path))
            (message "Could not retrieve BibTeX entry for %s" citekey)))
        (find-file org-file-path)
        (message "Wrapped %s, note stem %s, opened %s"
                 citekey note-stem org-file-path))))))

;;;###autoload
(defun mab-org-wrap-citekey-abib ()
  "Replace the citekey under the cursor with abib-style wrapped text.
This abib variant differs from `mab-org-wrap-citekey' in two
ways.  First, the bib file is written next to the current buffer
(as ab<NUMBER>.bib) rather than in a mab subdirectory.  Second,
the inserted block uses an Org COMMENT block in place of a Notes
drawer.

When the abibnote already exists, the same reuse/variant/quit
prompt as `mab-org-wrap-citekey' is offered."
  (interactive)
  (let* ((bounds (mab-org--bounds-of-citekey-or-word))
         (citation-text (when bounds
                          (buffer-substring-no-properties
                           (car bounds) (cdr bounds))))
         (citekey (mab-org--extract-citekey-from-text citation-text))
         (current-file (buffer-file-name))
         (current-dir (when current-file
                        (file-name-directory current-file)))
         (default-project-number
          (mab-org--default-project-number-from-filename current-file)))
    (cond
     ((not citekey)
      (message "No citekey found under the cursor."))
     (t
      (let* ((project-number
              (read-string (format "Project number for BibTeX file [%s]: "
                                   default-project-number)
                           nil nil default-project-number))
             (note-stem (mab-org--resolve-note-stem
                         citekey mab-org-notes-directory))
             (bibtex-entry (mab-org--lookup-bibtex-entry citekey))
             (book-p (mab-org--book-entry-p bibtex-entry))
             (bib-file-name (concat "ab" project-number ".bib"))
             (bib-file-path (and current-dir
                                 (concat current-dir bib-file-name)))
             (org-file-path (mab-org--note-path
                             note-stem mab-org-notes-directory))
             (wrapped-text (mab-org--render-abib-wrapped-text
                            citekey note-stem book-p)))
        (message "Using bibfile: %s" bib-file-path)
        (when bounds
          (delete-region (car bounds) (cdr bounds)))
        (insert wrapped-text)
        (mab-org--ensure-note-file note-stem)
        (when (and current-dir bib-file-path)
          (if bibtex-entry
              (progn
                (mab-org--append-bibtex-entry bib-file-path bibtex-entry)
                (message "Added BibTeX entry to %s" bib-file-path))
            (message "Could not retrieve BibTeX entry for %s" citekey)))
        (find-file org-file-path)
        (message "Wrapped %s, note stem %s, opened %s"
                 citekey note-stem org-file-path))))))

;;;###autoload
(defun mab-org-wrap-region (start end)
  "Apply `mab-org-wrap-citekey' to every citation in the region.
START and END delimit the region.  A citar citation is matched by
`mab-org--cite-block-regexp'.  Each match in the region is
processed in turn.  Citations are handled in reverse order (from
the end of the region toward the beginning) so the position of an
earlier citation is not invalidated when a later citation is
replaced by its much longer LaTeX expansion.

If the region contains more than `mab-org-region-confirm-threshold'
citations, a confirmation prompt appears before any work begins,
because each citation triggers file creation, buffer opening, and
an append to the project .bib file."
  (interactive "r")
  (unless (use-region-p)
    (user-error "No active region"))
  (let* ((source-buffer (current-buffer))
         (positions (mab-org--collect-citation-positions start end))
         (n (length positions)))
    (cond
     ((zerop n)
      (message "No citar citations found in the region."))
     ((and (> n mab-org-region-confirm-threshold)
           (not (yes-or-no-p
                 (format "Region contains %d citations (more than %d). Proceed? "
                         n mab-org-region-confirm-threshold))))
      (message "Aborted by user."))
     (t
      (dolist (pos (sort positions #'>))
        (with-current-buffer source-buffer
          (goto-char pos)
          (mab-org-wrap-citekey)))
      (pop-to-buffer source-buffer)
      (message "Wrapped %d citation(s)." n)))))

;;;; Ebib integration

(defun mab-org--ebib-key-at-point ()
  "Return the ebib citekey at point, or signal `user-error'.
Wraps `ebib--get-key-at-point' so that callers fail quickly when
the buffer is not an Ebib index buffer or no entry is selected."
  (unless (derived-mode-p 'ebib-index-mode)
    (user-error "This command can only be used in Ebib's index buffer"))
  (let ((key (and (fboundp 'ebib--get-key-at-point)
                  (ebib--get-key-at-point))))
    (or key (user-error "No bibliography entry selected"))))

(defconst mab-org--clearpage-or-blank-regexp
  (concat "[[:space:]]*\\(?:#\\+LATEX:[[:space:]]*\\)?"
          "\\\\clearpage[[:space:]]*$"
          "\\|[[:space:]]*$")
  "Regexp matching a blank line or a `\\clearpage' line.
Used by `mab-org--insert-into-mab-buffer' to skip over the
structural lines that introduce a Backmatter section.")

(defun mab-org--insert-into-mab-buffer (wrapped)
  "Insert WRAPPED inside the bibliography section of the current buffer.
The buffer is expected to be visiting a mab project Org file.

When a Backmatter section follows the bibliography heading, the
new entry is appended just below the last existing entry,
ABOVE any `\\clearpage' (and surrounding blank lines) that
introduces the Backmatter heading.  This keeps every wrapped
entry inside the bibliography section in the rendered document
rather than letting it land on the Backmatter page.

When no Backmatter heading is present, the block is appended at
end of file.  Signals `user-error' when the bibliography section
heading is missing."
  (goto-char (point-min))
  (unless (re-search-forward
           "\\\\section\\*{Illustrated and annotated bibliography}" nil t)
    (user-error
     "No \\section*{Illustrated and annotated bibliography} found"))
  (let ((bib-heading-end (line-end-position)))
    (cond
     ((save-excursion
        (re-search-forward "\\\\section\\*{Back ?matter}" nil t))
      (goto-char (match-beginning 0))
      (beginning-of-line)
      ;; Walk upward over blank lines and any \clearpage that
      ;; introduces Backmatter; stop at the last line of real
      ;; bibliography content, and position point at end-of-line so
      ;; the inserted block follows it directly.
      (let ((stopped nil))
        (while (and (not stopped)
                    (> (point) bib-heading-end))
          (forward-line -1)
          (unless (looking-at-p mab-org--clearpage-or-blank-regexp)
            (end-of-line)
            (setq stopped t)))
        (unless stopped
          ;; The bibliography section is empty; anchor at end of the
          ;; bibliography heading line.
          (goto-char bib-heading-end))))
     (t (goto-char (point-max)))))
  (insert "\n\n" wrapped))

;;;###autoload
(defun mab-org-add-bib-item (&optional file-path)
  "Append the current ebib entry to a mab project Org file.
The wrapped block is rendered by `mab-org--render-mab-wrapped-text'
and inserted under the section
\"Illustrated and annotated bibliography\".  When the document
also contains a \"Backmatter\" (or \"Back matter\") section, the
entry is inserted just before that.  Otherwise the entry is
appended at the end of the document.

FILE-PATH is the destination file.  When called interactively,
the user is prompted with `mab-org-mab-path' as the default; the
chosen file becomes the new default for the rest of the session.

The per-citekey abibnote file is also created (as an empty
file) if it does not already exist."
  (interactive)
  (let* ((key (mab-org--ebib-key-at-point))
         (default (and mab-org-mab-path
                       (expand-file-name mab-org-mab-path)))
         (target (or file-path
                     (expand-file-name
                      (read-file-name
                       (if default
                           (format "Mab file (default %s): " default)
                         "Mab file: ")
                       (and default (file-name-directory default))
                       default))))
         (bibtex-entry (mab-org--lookup-bibtex-entry key))
         (book-p (mab-org--book-entry-p bibtex-entry))
         (wrapped (mab-org--render-mab-wrapped-text key key book-p)))
    (unless (file-exists-p target)
      (user-error "File %s does not exist" target))
    (setq mab-org-mab-path target)
    (mab-org--ensure-note-file key)
    (let ((buf (find-file-noselect target)))
      (with-current-buffer buf
        (save-excursion
          (mab-org--insert-into-mab-buffer wrapped))
        (save-buffer)))
    (message "Added %s to %s" key target)))

;;;###autoload
(eval-after-load 'ebib
  '(when (boundp 'ebib-index-mode-map)
     (define-key ebib-index-mode-map (kbd "B") #'mab-org-add-bib-item)))

(provide 'mab-org)

;;; mab-org.el ends here
