# mab-org

Org-mode helpers for assembling modular annotated bibliographies (mab) and lighter-weight annotated bibliographies (abib) inside Emacs. Works with `citar` and `ebib`, and stamps out new mab project files from a built-in LaTeX template.
![Version](https://img.shields.io/static/v1?label=mab-org&message=0.1&color=brightcolor)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Emacs 27.1+](https://img.shields.io/badge/Emacs-27.1%2B-blueviolet.svg)](https://www.gnu.org/software/emacs/)

---

## Table of contents

- [Why this package exists](#why-this-package-exists)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Public commands](#public-commands)
- [Tutorial 1. Run the package](#tutorial-1-run-the-package)
- [Tutorial 2. Run the tests](#tutorial-2-run-the-tests)
- [Tutorial 3. Install the INFO file](#tutorial-3-install-the-info-file)
- [Project file layout](#project-file-layout)
- [How variant notes work](#how-variant-notes-work)
- [Suggested key bindings](#suggested-key-bindings)
- [Project structure](#project-structure)
- [Contributing](#contributing)
- [License](#license)
- [Acknowledgments](#acknowledgments)

---

## Why this package exists

Manuscript-style annotated bibliographies are easier to maintain when each cited work has a dedicated Org note, when the project document is a single Org file with a complete LaTeX preamble, and when adding or wrapping a citekey is one keystroke away from `citar` or `ebib`. The `mab-org` package provides the small set of commands that hold this workflow together so the bibliography manager and the project document stay in sync.

## Features

- Wrap a single `[cite:@KEY]` or bare citekey at point with the LaTeX `\bibentry` construct.
- Two flavors of wrapper. The mab style writes the file links as bare lines (visible in the exported PDF). The abib style writes the same links inside an Org `BEGIN_COMMENT` block (hidden in the exported PDF).
- Bulk wrapping of every citation in a region, with a confirmation prompt above a configurable threshold.
- Detect existing per-citekey notes and offer reuse, variant (next letter suffix), or quit.
- A single PDF link in the inserted block. By default it points at the article PDF; when the BibTeX entry begins with `@book` (or `@booklet`), it points at the book PDF instead. The detection regexp is configurable.
- New per-citekey notes are created as empty Org files, ready for you to fill in.
- `mab-org-create-project` stamps out a fresh `mab<NUMBER>/mab<NUMBER>.org` project file with a complete LaTeX preamble.
- `mab-org-open-file` finds an existing project file by number, or offers to create it.
- `mab-org-add-bib-item` appends the wrapped block to a mab project file directly from inside `ebib`. Bound to <kbd>B</kbd> in `ebib-index-mode-map` automatically when `ebib` is loaded.
- Search the global BibTeX library and insert `[cite:@KEY]` lines for every entry whose raw text contains a chosen term.
- ERT regression test suite, a Makefile that runs it in batch mode, and a Texinfo manual.

## Requirements

- Emacs 27.1 or later.
- `bibtex.el` (bundled with Emacs).
- Optional. `citar` is used by `mab-org-wrap-citekey` to copy a BibTeX entry into the project `.bib` file. Without `citar`, the wrap commands still wrap and create the note; they simply do not append to the project bib.
- Optional. `ebib` is used by `mab-org-add-bib-item`.

## Installation

### Manual installation

Clone the repository and put it on your Emacs `load-path`.

```elisp
(add-to-list 'load-path "/path/to/mab-org/")
(require 'mab-org)
```

### Installation via `make install`

The Makefile follows GNU conventions. Override `PREFIX` to choose the install root; the default is `$HOME/.local`.

```bash
make
make install        # copies mab-org.el to $PREFIX/share/emacs/site-lisp/
make install-info   # builds and installs mab-org.info under $PREFIX/share/info/
```

After `make install`, add the install directory to your `load-path`.

```elisp
(add-to-list 'load-path "~/.local/share/emacs/site-lisp/")
(require 'mab-org)
```

For a system-wide install, set `PREFIX` and run as root.

```bash
sudo make PREFIX=/usr/local install install-info
```

### `use-package` recipe

```elisp
(use-package mab-org
  :load-path "/path/to/mab-org/"
  :commands (mab-org-create-project
             mab-org-open-file
             mab-org-wrap-citekey
             mab-org-wrap-citekey-abib
             mab-org-wrap-region
             mab-org-insert-matching-keys
             mab-org-add-bib-item))
```

## Configuration

Customize through `M-x customize-group RET mab-org RET` or set in your init file.

| Option | Default | Purpose |
| --- | --- | --- |
| `mab-org-notes-directory` | `~/abibNotes/` | Where per-citekey notes live |
| `mab-org-pdfs-directory` | `~/0papersLabeled/` | Where renamed article PDFs live |
| `mab-org-books-directory` | `~/0booksLabeled/` | Where renamed book PDFs live |
| `mab-org-global-bib-file` | `~/Documents/global.bib` | Master BibTeX library searched by `mab-org-insert-matching-keys` |
| `mab-org-region-confirm-threshold` | `10` | Citation count above which region wrapping prompts |
| `mab-org-book-entry-regexp` | `\`[[:space:]]*@book` | Matches BibTeX entries that should use the book PDF link |
| `mab-org-base-directory` | `nil` | Default base directory for new mab project files |
| `mab-org-mab-path` | `nil` | Default destination for `mab-org-add-bib-item` |

Example.

```elisp
(setq mab-org-global-bib-file (expand-file-name "~/library/global.bib")
      mab-org-base-directory  (expand-file-name "~/projects/")
      mab-org-mab-path        (expand-file-name "~/projects/mab1097/mab1097.org"))
```

## Public commands

| Command | Use |
| --- | --- |
| `mab-org-create-project` | Stamp out `BASE/mab<N>/mab<N>.org` from the template |
| `mab-org-open-file` | Find or create a mab project file by number |
| `mab-org-wrap-citekey` | Wrap the citekey at point (mab style, links visible) |
| `mab-org-wrap-citekey-abib` | Wrap the citekey at point (abib style, links hidden in COMMENT block) |
| `mab-org-wrap-region` | Wrap every `[cite:@KEY]` in the active region |
| `mab-org-insert-matching-keys` | Search the global bib and insert `[cite:@KEY]` lines |
| `mab-org-add-bib-item` | Append the current ebib entry to a mab project file |

---

## Tutorial 1. Run the package

This walk-through assumes you have already installed `mab-org` (either by adding it to `load-path` manually or by running `make install`).

### Step 1. Load the package

```elisp
M-x load-library RET mab-org RET
```

Or, if you have not already evaluated the load form:

```elisp
(require 'mab-org)
```

Confirm the load.

```elisp
(featurep 'mab-org)             ; => t
(fboundp 'mab-org-create-project) ; => t
```

### Step 2. Create a project file

```elisp
M-x mab-org-create-project RET
Project number (digits only): 0386
Project short tag (used in title): mpQcr
Project full title (used in running header): multipass QCr
```

Result: `mab0386/mab0386.org` is created in the directory of the current buffer (or in `mab-org-base-directory` if set), opened in a new buffer, with the full LaTeX preamble already in place.

### Step 3. Wrap a citekey

Open any Org buffer that contains a citation, place point on the citekey, and run:

```elisp
M-x mab-org-wrap-citekey
```

Type a project number when prompted. The package replaces the citekey with the wrapped block, creates an empty per-citekey note (when one does not yet exist), and opens that note in a buffer.

Sample input.

```org
This idea was first proposed in [cite:@Atakisi2019Resolution].
```

Sample output for an `@article` entry (the default):

```org
This idea was first proposed in
#+LATEX: \subsubsection*{\bibentry{Atakisi2019Resolution}}
#+LATEX: \addcontentsline{toc}{subsubsection}{Atakisi2019Resolution}
#+INCLUDE: ~/abibNotes/Atakisi2019Resolution.org
The org-mode note is found [[file:~/abibNotes/Atakisi2019Resolution.org][here]]
The article PDF is found [[file:~/0papersLabeled/Atakisi2019Resolution.pdf][here]]
.
```

When the BibTeX entry is `@book`, the last line becomes:

```org
The book PDF is found [[file:~/0booksLabeled/Coppens1997Xray.pdf][here]]
```

### Step 4. Wrap every citation in a region

Select a region with several `[cite:@KEY]` citations and run:

```elisp
M-x mab-org-wrap-region
```

Citations are processed from end to beginning so earlier positions remain valid. Above ten citations the package asks you to confirm.

### Step 5. Add an entry from inside ebib

```elisp
M-x ebib
```

Navigate to the entry you want to annotate, then press <kbd>B</kbd>. Confirm the destination file (defaults to `mab-org-mab-path` if set). The package appends the wrapped block under the section `\section*{Illustrated and annotated bibliography}`, just below the last existing entry and above any `\clearpage` that introduces the `\section*{Backmatter}` heading. This keeps the new entry inside the bibliography section in the rendered PDF rather than letting it land on the Backmatter page. The note file is created if it does not yet exist.

### Step 6. Search the global bibliography

```elisp
M-x mab-org-insert-matching-keys RET
Search term: unicorns
```

For every BibTeX entry whose raw text contains `unicorns`, the package inserts one `[cite:@KEY]` line at point. Use this to seed a new mab section from a search.

---

## Tutorial 2. Run the tests

The package ships with an ERT regression suite of 47 tests and a Makefile target that runs it cleanly.

### Step 1. From a shell

```bash
cd /path/to/mab-org/
make test
```

The Makefile removes any stale `mab-org.elc` first, then invokes Emacs in batch mode with `load-prefer-newer` enabled, loads `ert` and `mab-org-test.el`, and runs the suite. Successful output ends with a line like:

```
Ran 47 tests, 47 results as expected, 0 unexpected
```

### Step 2. From inside Emacs (interactive ERT)

For an interactive ERT session you can step through:

```elisp
M-x load-file RET /path/to/mab-org/mab-org-test.el RET
M-x ert RET t RET
```

Press <kbd>r</kbd> on a failing test to re-run it, <kbd>.</kbd> to jump to its definition, and <kbd>l</kbd> to view the full backtrace.

### Step 3. Run a single test

```bash
emacs -Q --batch -L . -l mab-org-test.el \
  --eval "(ert-run-tests-batch-and-exit 'mab-org-test-extract-citekey-from-cite-form)"
```

### Step 4. Byte-compile and lint

```bash
make compile   # produces mab-org.elc
make lint      # runs checkdoc against mab-org.el
make clean     # removes .elc and .info
```

---

## Tutorial 3. Install the INFO file

The package ships a Texinfo source file `mab-org.texi` that builds an INFO document covering both `mab-org.el` and `mab-org-test.el`. Once installed, the manual is reachable from inside Emacs with <kbd>C-h i</kbd>.

### Prerequisites

You need `makeinfo` (part of GNU Texinfo) and `install-info` on your `PATH`.

```bash
makeinfo --version
install-info --version
```

If `makeinfo` is missing, install Texinfo. On macOS via Homebrew:

```bash
brew install texinfo
```

On Debian/Ubuntu:

```bash
sudo apt-get install texinfo
```

### Step 1. Build the INFO file

```bash
make info
```

This produces `mab-org.info` next to the source.

### Step 2. Install the INFO file

```bash
make install-info
```

Default install location is `$HOME/.local/share/info/mab-org.info`. Override with `PREFIX` or `INFODIR`.

```bash
make INFODIR=$HOME/Documents/info install-info
```

### Step 3. Make sure Emacs sees the install location

If the install directory is not in Emacs' default `Info-default-directory-list`, add it.

```elisp
(with-eval-after-load 'info
  (add-to-list 'Info-directory-list "~/.local/share/info/"))
```

### Step 4. Open the manual

Inside Emacs.

```
C-h i           ; open the Info top directory
d               ; display the directory of all manuals
m Mab-Org RET   ; jump to the Mab-Org manual
```

Or jump straight to the manual.

```elisp
M-x info RET (mab-org) RET
```

Or from anywhere.

```elisp
M-: (info "(mab-org)") RET
```

### Step 5. Uninstall when no longer wanted

```bash
make uninstall-info
```

This calls `install-info --remove` and deletes `$INFODIR/mab-org.info`.

---

## Project file layout

`mab-org-create-project` writes its output into a per-project subdirectory.

```
<base>/
└── mab0386/
    ├── mab0386.org   <- the project Org file (wrapped in this package's template)
    └── mab0386.bib   <- created by mab-org-wrap-citekey when citar is available
```

Per-citekey notes live in a single shared directory (`mab-org-notes-directory`).

```
~/abibNotes/
├── Atakisi2019Resolution.org
├── Atakisi2019Resolutiona.org   <- variant note (see below)
└── Hodel2020Cryo.org
```

PDFs live alongside.

```
~/0papersLabeled/
├── Atakisi2019Resolution.pdf
└── Hodel2020Cryo.pdf

~/0booksLabeled/
└── Coppens1997XrayChargeDensitiesAndChemicalBonding.pdf
```

## Article PDF vs book PDF

The wrapped block carries a single PDF link. The package picks where it points:

- The default link points at `mab-org-pdfs-directory` (`~/0papersLabeled/`). The line reads `The article PDF is found ...`.
- When the BibTeX entry for the citekey matches `mab-org-book-entry-regexp`, the link points at `mab-org-books-directory` (`~/0booksLabeled/`) instead and the line reads `The book PDF is found ...`. The default regexp matches any entry that begins with `@book`, so `@book` and `@booklet` are both covered.

Lookup order for the BibTeX entry: `citar`'s configured bibliography files first (when `citar` is loaded), then `mab-org-global-bib-file` as a fallback. When neither source has the entry, the default article link is emitted.

To extend the rule, set `mab-org-book-entry-regexp`. Example:

```elisp
;; Treat @book, @booklet, @inbook, and @incollection as books.
(setq mab-org-book-entry-regexp
      "\\`[[:space:]]*@\\(book\\|inbook\\|incollection\\)")
```

## How variant notes work

When you wrap a citekey for which a note already exists, the package asks what to do.

- <kbd>r</kbd> reuse the existing note. The wrapped block references the existing file. No new file is written.
- <kbd>v</kbd> variant. The package finds the next available lowercase letter and writes a new note with that letter appended to the stem. For example, after `Foo2020Bar.org` already exists, picking variant creates `Foo2020Bara.org`.
- <kbd>q</kbd> quit. The function aborts before any change is made to the buffer or the file system.

What the variant suffix changes in the inserted block:

- The TOC entry, the `#+INCLUDE:` directive, and the link to the Org note all use the variant stem (so the variant gets a distinct row in the TOC).
- The `\bibentry` command and the article and book PDF links keep the original citekey, because the BibTeX library and the PDF/book archives are keyed by citekey.

## Suggested key bindings

```elisp
(define-key org-mode-map (kbd "C-c m w") #'mab-org-wrap-citekey)
(define-key org-mode-map (kbd "C-c m W") #'mab-org-wrap-region)
(define-key org-mode-map (kbd "C-c m s") #'mab-org-insert-matching-keys)
(define-key org-mode-map (kbd "C-c m n") #'mab-org-create-project)
(define-key org-mode-map (kbd "C-c m o") #'mab-org-open-file)
;; In ebib-index-mode-map, B is bound to mab-org-add-bib-item automatically.
```

## Project structure

```
mab-org/
├── mab-org.el          ; the package
├── mab-org-test.el     ; ERT regression suite
├── mab-org.texi        ; Texinfo source
├── Makefile            ; build, test, info, install
├── mabXXXX.org         ; reference copy of the project template
└── README.md           ; this file
```

Output files (not version-controlled).

```
mab-org.elc            ; built by `make compile`
mab-org-test.elc       ; built incidentally on `make test`
mab-org.info           ; built by `make info`
```

## Contributing

Issues and pull requests are welcome on GitHub. When opening a PR, please.

1. Run `make test` and confirm all tests pass.
2. Run `make lint` and address any new `checkdoc` warnings.
3. Update the Texinfo manual (`mab-org.texi`) when changing public behavior. The manual is the source of truth for the INFO documentation.
4. Add or extend ERT tests for any new feature or bug fix.
5. Note your change in the **Changelog** chapter of `mab-org.texi`.

## License

Released under the GNU General Public License, version 3 or later. See the header of `mab-org.el` for the full notice. The Texinfo manual is licensed under the GNU Free Documentation License, version 1.3 or later.

## Sources of funding

- NIH: R01 CA242845
- NIH: R01 AI088011
- NIH: P30 CA225520 (PI: R. Mannel)
- NIH: P20 GM103640 and P30 GM145423 (PI: A. West)


## Acknowledgments

Earlier prototypes of these helpers grew out of work captured in the [`ebib-to-mab-el`](https://github.com/MooersLab) repository, including the original `mab-add-bib-item` and the `mab-create-file` template. This release consolidates those features and the citar/wrap workflow under a single package name.
