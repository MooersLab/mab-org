;;; mab-org-test.el --- ERT test suite for mab-org.el -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Blaine Mooers

;; Author: Blaine Mooers <blaine-mooers@ou.edu>
;; URL: https://github.com/MooersLab/mab-org

;; This file is not part of GNU Emacs.

;;; Commentary:

;; ERT regression tests for mab-org.el.
;;
;; Run from a shell with
;;
;;     emacs -Q --batch -L . -l mab-org-test.el \
;;           -f ert-run-tests-batch-and-exit
;;
;; or, more conveniently, with `make test'.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Make sure the package under test is found whether the suite is run
;; from this directory or a sibling directory.
(let ((here (file-name-directory (or load-file-name buffer-file-name
                                     default-directory))))
  (add-to-list 'load-path here))

(require 'mab-org)

;;;; Helpers used by several tests

(defun mab-org-test--with-temp-dir (fn)
  "Call FN with the path to a fresh temporary directory.
The directory and its contents are deleted after FN returns."
  (let ((dir (file-name-as-directory
              (make-temp-file "mab-org-test-" t))))
    (unwind-protect
        (funcall fn dir)
      (delete-directory dir t))))

(defmacro mab-org-test-with-temp-dir (var &rest body)
  "Bind VAR to a fresh temporary directory and evaluate BODY."
  (declare (indent 1))
  `(mab-org-test--with-temp-dir (lambda (,var) ,@body)))

(defun mab-org-test--read-file (path)
  "Return the contents of PATH as a string."
  (with-temp-buffer
    (insert-file-contents path)
    (buffer-string)))

;;;; mab-org--extract-citekey-from-text

(ert-deftest mab-org-test-extract-citekey-from-cite-form ()
  (should (equal (mab-org--extract-citekey-from-text
                  "[cite:@Smith2020SomeTitle]")
                 "Smith2020SomeTitle")))

(ert-deftest mab-org-test-extract-citekey-from-bare-word ()
  (should (equal (mab-org--extract-citekey-from-text "Smith2020SomeTitle")
                 "Smith2020SomeTitle")))

(ert-deftest mab-org-test-extract-citekey-stops-before-comma ()
  (should (equal (mab-org--extract-citekey-from-text
                  "[cite:@Smith2020,@Jones2021]")
                 "Smith2020")))

(ert-deftest mab-org-test-extract-citekey-handles-nil ()
  (should (null (mab-org--extract-citekey-from-text nil))))

;;;; mab-org--default-project-number-from-filename

(ert-deftest mab-org-test-default-project-number-mab-prefix ()
  (should (equal (mab-org--default-project-number-from-filename
                  "/home/user/mab2156.org")
                 "2156")))

(ert-deftest mab-org-test-default-project-number-ab-prefix ()
  (should (equal (mab-org--default-project-number-from-filename
                  "/home/user/ab2156.org")
                 "2156")))

(ert-deftest mab-org-test-default-project-number-bare-digits ()
  (should (equal (mab-org--default-project-number-from-filename
                  "/home/user/2156-notes.org")
                 "2156")))

(ert-deftest mab-org-test-default-project-number-no-digits ()
  (should (equal (mab-org--default-project-number-from-filename
                  "/home/user/notes.org")
                 "")))

(ert-deftest mab-org-test-default-project-number-nil-filename ()
  (should (equal (mab-org--default-project-number-from-filename nil)
                 "")))

;;;; mab-org--render-mab-wrapped-text

(ert-deftest mab-org-test-render-mab-wrapped-includes-citekey ()
  (let* ((mab-org-notes-directory "/tmp/notes/")
         (mab-org-pdfs-directory "/tmp/pdfs/")
         (mab-org-books-directory "/tmp/books/")
         (out (mab-org--render-mab-wrapped-text "Foo2020Bar")))
    (should (string-match-p "\\\\bibentry{Foo2020Bar}" out))
    (should (string-match-p
             "\\\\addcontentsline{toc}{subsubsection}{Foo2020Bar}" out))
    (should (string-match-p "#\\+INCLUDE: /tmp/notes/Foo2020Bar.org" out))))

(ert-deftest mab-org-test-render-mab-wrapped-omits-notes-drawer ()
  "The mab-style block exposes its links rather than wrapping them."
  (let* ((mab-org-notes-directory "/tmp/notes/")
         (mab-org-pdfs-directory "/tmp/pdfs/")
         (mab-org-books-directory "/tmp/books/")
         (out (mab-org--render-mab-wrapped-text "Foo2020Bar")))
    (should-not (string-match-p "^:Notes:" out))
    (should-not (string-match-p "^:END:" out))
    (should-not (string-match-p "BEGIN_COMMENT" out))
    (should-not (string-match-p "Add more prose" out))))

(ert-deftest mab-org-test-render-mab-wrapped-defaults-to-article-link ()
  "Without a book flag, the mab block uses the article PDF only."
  (let* ((mab-org-notes-directory "/tmp/notes/")
         (mab-org-pdfs-directory "/tmp/pdfs/")
         (mab-org-books-directory "/tmp/books/")
         (out (mab-org--render-mab-wrapped-text "Foo2020Bar")))
    (should (string-match-p "file:/tmp/pdfs/Foo2020Bar.pdf" out))
    (should-not (string-match-p "file:/tmp/books/Foo2020Bar.pdf" out))
    (should (string-match-p "article PDF" out))
    (should-not (string-match-p "book PDF" out))))

(ert-deftest mab-org-test-render-mab-wrapped-uses-book-link-when-book-p ()
  "With a non-nil book flag, the mab block uses the book PDF only."
  (let* ((mab-org-notes-directory "/tmp/notes/")
         (mab-org-pdfs-directory "/tmp/pdfs/")
         (mab-org-books-directory "/tmp/books/")
         (out (mab-org--render-mab-wrapped-text "K1" nil t)))
    (should (string-match-p "file:/tmp/books/K1.pdf" out))
    (should-not (string-match-p "file:/tmp/pdfs/K1.pdf" out))
    (should (string-match-p "book PDF" out))
    (should-not (string-match-p "article PDF" out))))

(ert-deftest mab-org-test-render-mab-wrapped-respects-custom-dirs ()
  (let* ((mab-org-notes-directory "/var/notes")
         (mab-org-pdfs-directory "/var/pdfs")
         (mab-org-books-directory "/var/books")
         (article-out (mab-org--render-mab-wrapped-text "K1"))
         (book-out (mab-org--render-mab-wrapped-text "K1" nil t)))
    (should (string-match-p "/var/notes/K1.org" article-out))
    (should (string-match-p "/var/pdfs/K1.pdf" article-out))
    (should-not (string-match-p "/var/books/K1.pdf" article-out))
    (should (string-match-p "/var/books/K1.pdf" book-out))
    (should-not (string-match-p "/var/pdfs/K1.pdf" book-out))))

;;;; mab-org--render-abib-wrapped-text

(ert-deftest mab-org-test-render-abib-wrapped-uses-comment-block ()
  (let* ((mab-org-notes-directory "/tmp/notes/")
         (mab-org-pdfs-directory "/tmp/pdfs/")
         (mab-org-books-directory "/tmp/books/")
         (out (mab-org--render-abib-wrapped-text "K1")))
    (should (string-match-p "#\\+BEGIN_COMMENT" out))
    (should (string-match-p "#\\+END_COMMENT" out))
    (should-not (string-match-p "^:Notes:" out))))

(ert-deftest mab-org-test-render-abib-wrapped-defaults-to-article-link ()
  "Without a book flag, the abib block uses the article PDF only."
  (let* ((mab-org-notes-directory "/tmp/notes/")
         (mab-org-pdfs-directory "/tmp/pdfs/")
         (mab-org-books-directory "/tmp/books/")
         (out (mab-org--render-abib-wrapped-text "K1")))
    (should (string-match-p "file:/tmp/notes/K1.org" out))
    (should (string-match-p "file:/tmp/pdfs/K1.pdf" out))
    (should-not (string-match-p "file:/tmp/books/K1.pdf" out))))

(ert-deftest mab-org-test-render-abib-wrapped-uses-book-link-when-book-p ()
  "With a non-nil book flag, the abib block uses the book PDF only."
  (let* ((mab-org-notes-directory "/tmp/notes/")
         (mab-org-pdfs-directory "/tmp/pdfs/")
         (mab-org-books-directory "/tmp/books/")
         (out (mab-org--render-abib-wrapped-text "K1" nil t)))
    (should (string-match-p "file:/tmp/books/K1.pdf" out))
    (should-not (string-match-p "file:/tmp/pdfs/K1.pdf" out))))

(ert-deftest mab-org-test-render-mab-wrapped-with-variant-stem ()
  "A variant stem changes INCLUDE, TOC, and the note link.
The bibentry and the (article or book) PDF link still use the
original citekey."
  (let* ((mab-org-notes-directory "/tmp/notes/")
         (mab-org-pdfs-directory "/tmp/pdfs/")
         (mab-org-books-directory "/tmp/books/")
         (article-out (mab-org--render-mab-wrapped-text
                       "Foo2020Bar" "Foo2020Bara"))
         (book-out (mab-org--render-mab-wrapped-text
                    "Foo2020Bar" "Foo2020Bara" t)))
    ;; The bibentry uses the citekey, not the stem, in both cases.
    (should (string-match-p "\\\\bibentry{Foo2020Bar}" article-out))
    (should (string-match-p "\\\\bibentry{Foo2020Bar}" book-out))
    (should-not (string-match-p "\\\\bibentry{Foo2020Bara}" article-out))
    ;; TOC and INCLUDE use the stem.
    (should (string-match-p
             "\\\\addcontentsline{toc}{subsubsection}{Foo2020Bara}"
             article-out))
    (should (string-match-p "#\\+INCLUDE: /tmp/notes/Foo2020Bara.org"
                            article-out))
    ;; Article-style: only the article PDF, with the citekey.
    (should (string-match-p "file:/tmp/pdfs/Foo2020Bar.pdf" article-out))
    (should-not (string-match-p "file:/tmp/books/" article-out))
    ;; Book-style: only the book PDF, with the citekey.
    (should (string-match-p "file:/tmp/books/Foo2020Bar.pdf" book-out))
    (should-not (string-match-p "file:/tmp/pdfs/" book-out))))

(ert-deftest mab-org-test-render-abib-wrapped-with-variant-stem ()
  (let* ((mab-org-notes-directory "/tmp/notes/")
         (mab-org-pdfs-directory "/tmp/pdfs/")
         (mab-org-books-directory "/tmp/books/")
         (article-out (mab-org--render-abib-wrapped-text "K1" "K1a"))
         (book-out (mab-org--render-abib-wrapped-text "K1" "K1a" t)))
    (should (string-match-p "\\\\bibentry{K1}" article-out))
    (should (string-match-p "#\\+INCLUDE: /tmp/notes/K1a.org" article-out))
    (should (string-match-p "file:/tmp/notes/K1a.org" article-out))
    (should (string-match-p "file:/tmp/pdfs/K1.pdf" article-out))
    (should-not (string-match-p "file:/tmp/books/" article-out))
    (should (string-match-p "file:/tmp/books/K1.pdf" book-out))
    (should-not (string-match-p "file:/tmp/pdfs/" book-out))))

;;;; mab-org--collect-citation-positions

(ert-deftest mab-org-test-collect-positions-counts-and-orders ()
  (with-temp-buffer
    (insert "Some text [cite:@Alpha2020] middle [cite:@Beta2021] tail.\n")
    (let ((positions (mab-org--collect-citation-positions
                      (point-min) (point-max))))
      (should (= 2 (length positions)))
      (should (apply #'< positions)))))

(ert-deftest mab-org-test-collect-positions-skips-noncitations ()
  (with-temp-buffer
    (insert "no citations here, only \\cite{Alpha2020} and Beta2021.\n")
    (should (null (mab-org--collect-citation-positions
                   (point-min) (point-max))))))

(ert-deftest mab-org-test-collect-positions-bounded-region ()
  (with-temp-buffer
    (insert "[cite:@Alpha2020] then [cite:@Beta2021] then [cite:@Gamma2022]\n")
    (goto-char (point-min))
    (let* ((after-first (progn (search-forward "]") (point)))
           (positions (mab-org--collect-citation-positions
                       after-first (point-max))))
      (should (= 2 (length positions))))))

;;;; Note file creation

(ert-deftest mab-org-test-ensure-note-file-creates-empty ()
  "When no note exists, the file is created and is empty."
  (mab-org-test-with-temp-dir dir
    (let ((mab-org-notes-directory dir))
      (let ((path (mab-org--ensure-note-file "K1")))
        (should (file-exists-p path))
        (should (equal "" (mab-org-test--read-file path)))))))

(ert-deftest mab-org-test-ensure-note-file-leaves-existing-alone ()
  "An existing note file is not overwritten."
  (mab-org-test-with-temp-dir dir
    (let* ((mab-org-notes-directory dir)
           (path (expand-file-name "K1.org" dir)))
      (with-temp-file path (insert "ORIGINAL"))
      (mab-org--ensure-note-file "K1")
      (should (equal "ORIGINAL" (mab-org-test--read-file path))))))

(ert-deftest mab-org-test-ensure-note-file-creates-missing-directory ()
  "The notes directory is created when it does not yet exist."
  (mab-org-test-with-temp-dir dir
    (let* ((sub (expand-file-name "deeper/notes/" dir))
           (mab-org-notes-directory sub))
      (mab-org--ensure-note-file "K1")
      (should (file-directory-p sub))
      (should (file-exists-p (expand-file-name "K1.org" sub))))))

;;;; Variant resolution

(ert-deftest mab-org-test-next-variant-letter-when-none-exist ()
  (mab-org-test-with-temp-dir dir
    (with-temp-file (expand-file-name "Foo2020Bar.org" dir) (insert ""))
    (should (eq (mab-org--next-variant-letter "Foo2020Bar" dir) ?a))))

(ert-deftest mab-org-test-next-variant-letter-skips-used ()
  (mab-org-test-with-temp-dir dir
    (dolist (n '("Foo2020Bar.org" "Foo2020Bara.org" "Foo2020Barb.org"))
      (with-temp-file (expand-file-name n dir) (insert "")))
    (should (eq (mab-org--next-variant-letter "Foo2020Bar" dir) ?c))))

(ert-deftest mab-org-test-next-variant-letter-returns-nil-when-full ()
  (mab-org-test-with-temp-dir dir
    (dolist (letter (number-sequence ?a ?z))
      (with-temp-file (expand-file-name (format "K%c.org" letter) dir)
        (insert "")))
    (should (null (mab-org--next-variant-letter "K" dir)))))

(ert-deftest mab-org-test-resolve-note-stem-no-existing-note ()
  (mab-org-test-with-temp-dir dir
    (cl-letf (((symbol-function 'read-multiple-choice)
               (lambda (&rest _)
                 (error "read-multiple-choice should not be called"))))
      (should (equal (mab-org--resolve-note-stem "K1" dir) "K1")))))

(ert-deftest mab-org-test-resolve-note-stem-reuse ()
  (mab-org-test-with-temp-dir dir
    (with-temp-file (expand-file-name "K1.org" dir) (insert ""))
    (cl-letf (((symbol-function 'read-multiple-choice)
               (lambda (_prompt choices) (assoc ?r choices))))
      (should (equal (mab-org--resolve-note-stem "K1" dir) "K1")))))

(ert-deftest mab-org-test-resolve-note-stem-variant ()
  (mab-org-test-with-temp-dir dir
    (with-temp-file (expand-file-name "K1.org" dir) (insert ""))
    (cl-letf (((symbol-function 'read-multiple-choice)
               (lambda (_prompt choices) (assoc ?v choices))))
      (should (equal (mab-org--resolve-note-stem "K1" dir) "K1a")))))

(ert-deftest mab-org-test-resolve-note-stem-variant-skips-used ()
  (mab-org-test-with-temp-dir dir
    (dolist (n '("K1.org" "K1a.org" "K1b.org"))
      (with-temp-file (expand-file-name n dir) (insert "")))
    (cl-letf (((symbol-function 'read-multiple-choice)
               (lambda (_prompt choices) (assoc ?v choices))))
      (should (equal (mab-org--resolve-note-stem "K1" dir) "K1c")))))

(ert-deftest mab-org-test-resolve-note-stem-quit-signals ()
  (mab-org-test-with-temp-dir dir
    (with-temp-file (expand-file-name "K1.org" dir) (insert ""))
    (cl-letf (((symbol-function 'read-multiple-choice)
               (lambda (_prompt choices) (assoc ?q choices))))
      (should-error (mab-org--resolve-note-stem "K1" dir)
                    :type 'user-error))))

;;;; Book-entry detection

(ert-deftest mab-org-test-book-entry-p-detects-book ()
  "Entries beginning with @book (any case) are treated as books."
  (should (mab-org--book-entry-p "@book{Foo, title = {x}}"))
  (should (mab-org--book-entry-p "@Book{Foo, title = {x}}"))
  (should (mab-org--book-entry-p "@BOOK{Foo, title = {x}}"))
  (should (mab-org--book-entry-p "  @book{Foo, title = {x}}"))
  (should (mab-org--book-entry-p "@booklet{Foo, title = {x}}")))

(ert-deftest mab-org-test-book-entry-p-rejects-others ()
  "Articles and unparseable inputs are not treated as books."
  (should-not (mab-org--book-entry-p nil))
  (should-not (mab-org--book-entry-p ""))
  (should-not (mab-org--book-entry-p "@article{Foo, title = {x}}"))
  (should-not (mab-org--book-entry-p "@inbook{Foo, title = {x}}"))
  (should-not (mab-org--book-entry-p "@incollection{Foo, title = {x}}"))
  (should-not (mab-org--book-entry-p "stray text @book{...}")))

(ert-deftest mab-org-test-book-entry-p-honors-custom-regexp ()
  "A custom regexp can extend detection to @inbook and @incollection."
  (let ((mab-org-book-entry-regexp
         "\\`[[:space:]]*@\\(book\\|inbook\\|incollection\\)"))
    (should (mab-org--book-entry-p "@inbook{Foo}"))
    (should (mab-org--book-entry-p "@incollection{Foo}"))
    (should (mab-org--book-entry-p "@book{Foo}"))
    (should-not (mab-org--book-entry-p "@article{Foo}"))))

;;;; mab-org--lookup-bibtex-entry

(ert-deftest mab-org-test-lookup-bibtex-entry-from-global-bib ()
  "When citar is not loaded, fallback reads `mab-org-global-bib-file'."
  (mab-org-test-with-temp-dir dir
    (let* ((bib (expand-file-name "global.bib" dir))
           (mab-org-global-bib-file bib))
      (with-temp-file bib
        (insert "@book{Coppens1997Xray,
  title = {X-ray charge densities and chemical bonding},
  author = {Coppens, P.}
}

@article{Atakisi2019Resolution,
  title = {Resolution and dose dependence}
}
"))
      (let ((book-entry (mab-org--lookup-bibtex-entry "Coppens1997Xray"))
            (article-entry
             (mab-org--lookup-bibtex-entry "Atakisi2019Resolution")))
        (should (and book-entry (string-match-p "\\`@book" book-entry)))
        (should (mab-org--book-entry-p book-entry))
        (should (and article-entry
                     (string-match-p "\\`@article" article-entry)))
        (should-not (mab-org--book-entry-p article-entry))))))

(ert-deftest mab-org-test-lookup-bibtex-entry-missing-returns-nil ()
  "An unknown citekey returns nil."
  (mab-org-test-with-temp-dir dir
    (let* ((bib (expand-file-name "global.bib" dir))
           (mab-org-global-bib-file bib))
      (with-temp-file bib (insert "@book{Coppens1997Xray, title={x}}\n"))
      (should (null (mab-org--lookup-bibtex-entry "no-such-key"))))))

;;;; mab-org--render-template

(ert-deftest mab-org-test-render-template-substitutes-fields ()
  (let ((out (mab-org--render-template "0386" "mpQcr" "multipass QCr"
                                       "/Users/blaine/Documents/global")))
    (should (string-match-p "Annotated Bibliography for Project 0386 mpQcr"
                            out))
    (should (string-match-p "fancyhead\\[C\\]{0386 multipass QCr}" out))
    (should (string-match-p
             "\\\\bibliography{/Users/blaine/Documents/global}" out))))

(ert-deftest mab-org-test-render-template-uses-affiliation-update ()
  (let ((out (mab-org--render-template "0386" "mpQcr" "multipass QCr"
                                       "/tmp/global")))
    (should (string-match-p "University of Oklahoma Health Campus" out))
    (should-not (string-match-p "Oklahoma Health Sciences" out))))

(ert-deftest mab-org-test-render-template-uses-current-email ()
  (let ((out (mab-org--render-template "0386" "mpQcr" "multipass QCr"
                                       "/tmp/global")))
    (should (string-match-p "blaine-mooers@ou\\.edu" out))))

;;;; mab-org-create-project

(ert-deftest mab-org-test-create-project-uses-subdirectory ()
  "Project file lives at BASE/mab<NUMBER>/mab<NUMBER>.org."
  (mab-org-test-with-temp-dir dir
    (let* ((file (mab-org-create-project "0386" "mpQcr" "multipass QCr"
                                         dir "/tmp/global")))
      (should (file-exists-p file))
      (should (file-directory-p (expand-file-name "mab0386/" dir)))
      (should (string-match-p "/mab0386/mab0386\\.org\\'" file))
      (let ((body (mab-org-test--read-file file)))
        (should (string-match-p "Project 0386 mpQcr" body))
        (should (string-match-p "fancyhead\\[C\\]{0386 multipass QCr}"
                                body))
        (should (string-match-p "\\\\bibliography{/tmp/global}" body))))))

(ert-deftest mab-org-test-create-project-refuses-overwrite ()
  (mab-org-test-with-temp-dir dir
    (let* ((sub (expand-file-name "mab0386/" dir))
           (path (expand-file-name "mab0386.org" sub)))
      (make-directory sub t)
      (with-temp-file path (insert "ORIGINAL"))
      (should-error
       (mab-org-create-project "0386" "mpQcr" "multipass QCr"
                               dir "/tmp/global")
       :type 'user-error)
      (should (equal "ORIGINAL" (mab-org-test--read-file path))))))

(ert-deftest mab-org-test-create-project-defaults-bib-from-custom ()
  (mab-org-test-with-temp-dir dir
    (let ((mab-org-global-bib-file "/some/where/global.bib"))
      (let* ((file (mab-org-create-project "0001" "tag" "Long Title" dir))
             (body (mab-org-test--read-file file)))
        (should (string-match-p "\\\\bibliography{/some/where/global}"
                                body))))))

(ert-deftest mab-org-test-create-project-creates-missing-base ()
  "When BASE-DIR does not yet exist, it is created."
  (mab-org-test-with-temp-dir dir
    (let* ((base (expand-file-name "nested/deeper/" dir))
           (file (mab-org-create-project "0001" "tag" "Long Title"
                                         base "/tmp/global")))
      (should (file-directory-p base))
      (should (file-exists-p file)))))

;;;; mab-org--append-bibtex-entry

(ert-deftest mab-org-test-append-bibtex-entry-creates-file ()
  (mab-org-test-with-temp-dir dir
    (let ((path (expand-file-name "out.bib" dir))
          (entry "@article{Foo2020, title={x}}"))
      (mab-org--append-bibtex-entry path entry)
      (should (file-exists-p path))
      (should (string-match-p "@article{Foo2020"
                              (mab-org-test--read-file path))))))

(ert-deftest mab-org-test-append-bibtex-entry-preserves-existing ()
  (mab-org-test-with-temp-dir dir
    (let ((path (expand-file-name "out.bib" dir)))
      (with-temp-file path (insert "@article{Existing2019,}\n"))
      (mab-org--append-bibtex-entry path "@article{Foo2020,}")
      (let ((body (mab-org-test--read-file path)))
        (should (string-match-p "Existing2019" body))
        (should (string-match-p "Foo2020" body))
        (should (< (string-match "Existing2019" body)
                   (string-match "Foo2020" body)))))))

;;;; mab-org--bounds-of-citekey-or-word

(ert-deftest mab-org-test-bounds-detects-citation ()
  (with-temp-buffer
    (insert "before [cite:@Foo2020Bar] after")
    (search-backward "Foo")
    (let* ((bounds (mab-org--bounds-of-citekey-or-word))
           (text (buffer-substring-no-properties
                  (car bounds) (cdr bounds))))
      (should (equal text "[cite:@Foo2020Bar]")))))

(ert-deftest mab-org-test-bounds-detects-bare-word ()
  (with-temp-buffer
    (insert "Foo2020Bar")
    (goto-char (point-min))
    (forward-char 2)
    (let* ((bounds (mab-org--bounds-of-citekey-or-word))
           (text (buffer-substring-no-properties
                  (car bounds) (cdr bounds))))
      (should (equal text "Foo2020Bar")))))

;;;; mab-org-insert-matching-keys

(ert-deftest mab-org-test-insert-matching-keys-finds-matches ()
  (mab-org-test-with-temp-dir dir
    (let* ((bib (expand-file-name "global.bib" dir))
           (mab-org-global-bib-file bib))
      (with-temp-file bib
        (insert "@article{Foo2020Bar,
  title = {A study of unicorns},
  author = {Foo, A. and Bar, B.}
}

@article{Baz2021Qux,
  title = {On dragons},
  author = {Baz, C.}
}
"))
      (with-temp-buffer
        (let ((matches
               (mab-org-insert-matching-keys "unicorns")))
          (should (equal matches '("Foo2020Bar")))
          (should (string-match-p "\\[cite:@Foo2020Bar\\]"
                                  (buffer-string))))))))

(ert-deftest mab-org-test-insert-matching-keys-no-matches ()
  (mab-org-test-with-temp-dir dir
    (let* ((bib (expand-file-name "global.bib" dir))
           (mab-org-global-bib-file bib))
      (with-temp-file bib
        (insert "@article{Foo2020Bar, title = {x}}\n"))
      (with-temp-buffer
        (let ((matches
               (mab-org-insert-matching-keys "no-such-term")))
          (should (null matches))
          (should (equal "" (buffer-string))))))))

;;;; mab-org--insert-into-mab-buffer

(defun mab-org-test--make-mab-file (path &optional with-backmatter)
  "Write a minimal mab Org file to PATH for testing.
When WITH-BACKMATTER is non-nil, also include a Backmatter
section after the bibliography heading."
  (with-temp-file path
    (insert "Top of file\n\n"
            "#+LATEX:\\section*{Illustrated and annotated bibliography}\n"
            "#+LATEX:\\addcontentsline{toc}{section}{Bibliography}\n\n")
    (when with-backmatter
      (insert "\\clearpage\n"
              "#+LATEX: \\section*{Backmatter}\n"
              "Backmatter content here.\n"))))

(ert-deftest mab-org-test-add-bib-item-inserts-before-backmatter ()
  "When a Backmatter section exists, the wrapped block lands before it."
  (mab-org-test-with-temp-dir dir
    (let* ((mab-org-notes-directory dir)
           (mab-org-pdfs-directory dir)
           (mab-org-books-directory dir)
           (mab-org-mab-path (expand-file-name "mab1.org" dir))
           (path mab-org-mab-path))
      (mab-org-test--make-mab-file path 'with-backmatter)
      (cl-letf (((symbol-function 'derived-mode-p)
                 (lambda (mode) (eq mode 'ebib-index-mode)))
                ((symbol-function 'ebib--get-key-at-point)
                 (lambda () "Foo2020Bar")))
        (with-temp-buffer
          (mab-org-add-bib-item path)))
      (let ((body (mab-org-test--read-file path)))
        (should (string-match-p "\\\\bibentry{Foo2020Bar}" body))
        (should (< (string-match "\\\\bibentry{Foo2020Bar}" body)
                   (string-match "\\\\section\\*{Backmatter}" body)))))))

(ert-deftest mab-org-test-add-bib-item-lands-above-clearpage ()
  "The wrapped block lands above any \\clearpage that introduces Backmatter."
  (mab-org-test-with-temp-dir dir
    (let* ((mab-org-notes-directory dir)
           (mab-org-pdfs-directory dir)
           (mab-org-books-directory dir)
           (path (expand-file-name "mab1.org" dir)))
      (with-temp-file path
        (insert "Top of file\n\n"
                "#+LATEX:\\section*{Illustrated and annotated bibliography}\n"
                "#+LATEX:\\addcontentsline{toc}{section}{Bibliography}\n\n"
                "\\clearpage\n"
                "#+LATEX: \\section*{Backmatter}\n"
                "Backmatter content here.\n"))
      (cl-letf (((symbol-function 'derived-mode-p)
                 (lambda (mode) (eq mode 'ebib-index-mode)))
                ((symbol-function 'ebib--get-key-at-point)
                 (lambda () "Foo2020Bar")))
        (with-temp-buffer
          (mab-org-add-bib-item path)))
      (let ((body (mab-org-test--read-file path)))
        (should (string-match-p "\\\\bibentry{Foo2020Bar}" body))
        ;; The new entry must appear above \\clearpage, not below.
        (should (< (string-match "\\\\bibentry{Foo2020Bar}" body)
                   (string-match "\\\\clearpage" body)))))))

(ert-deftest mab-org-test-add-bib-item-appends-when-no-backmatter ()
  "Without a Backmatter section, the wrapped block is appended at end."
  (mab-org-test-with-temp-dir dir
    (let* ((mab-org-notes-directory dir)
           (mab-org-pdfs-directory dir)
           (mab-org-books-directory dir)
           (path (expand-file-name "mab1.org" dir)))
      (mab-org-test--make-mab-file path nil)
      (cl-letf (((symbol-function 'derived-mode-p)
                 (lambda (mode) (eq mode 'ebib-index-mode)))
                ((symbol-function 'ebib--get-key-at-point)
                 (lambda () "Foo2020Bar")))
        (with-temp-buffer
          (mab-org-add-bib-item path)))
      (let ((body (mab-org-test--read-file path)))
        (should (string-match-p "\\\\bibentry{Foo2020Bar}" body))))))

(ert-deftest mab-org-test-add-bib-item-uses-book-link-for-book-entry ()
  "When the entry is `@book' the wrapped block uses the books directory."
  (mab-org-test-with-temp-dir dir
    (let* ((bib (expand-file-name "global.bib" dir))
           (mab-org-global-bib-file bib)
           (mab-org-notes-directory dir)
           (mab-org-pdfs-directory "/tmp/papers/")
           (mab-org-books-directory "/tmp/books/")
           (path (expand-file-name "mab1.org" dir)))
      (with-temp-file bib
        (insert "@book{Coppens1997Xray, title={X-ray charge densities}}\n"))
      (mab-org-test--make-mab-file path 'with-backmatter)
      (cl-letf (((symbol-function 'derived-mode-p)
                 (lambda (mode) (eq mode 'ebib-index-mode)))
                ((symbol-function 'ebib--get-key-at-point)
                 (lambda () "Coppens1997Xray")))
        (with-temp-buffer
          (mab-org-add-bib-item path)))
      (let ((body (mab-org-test--read-file path)))
        (should (string-match-p "\\\\bibentry{Coppens1997Xray}" body))
        (should (string-match-p "file:/tmp/books/Coppens1997Xray.pdf" body))
        (should-not (string-match-p "file:/tmp/papers/" body))
        (should (string-match-p "book PDF" body))
        (should-not (string-match-p "article PDF" body))))))

(ert-deftest mab-org-test-add-bib-item-uses-article-link-by-default ()
  "When the entry is not a book, the wrapped block uses the papers directory."
  (mab-org-test-with-temp-dir dir
    (let* ((bib (expand-file-name "global.bib" dir))
           (mab-org-global-bib-file bib)
           (mab-org-notes-directory dir)
           (mab-org-pdfs-directory "/tmp/papers/")
           (mab-org-books-directory "/tmp/books/")
           (path (expand-file-name "mab1.org" dir)))
      (with-temp-file bib
        (insert "@article{Atakisi2019Resolution, title={Resolution}}\n"))
      (mab-org-test--make-mab-file path 'with-backmatter)
      (cl-letf (((symbol-function 'derived-mode-p)
                 (lambda (mode) (eq mode 'ebib-index-mode)))
                ((symbol-function 'ebib--get-key-at-point)
                 (lambda () "Atakisi2019Resolution")))
        (with-temp-buffer
          (mab-org-add-bib-item path)))
      (let ((body (mab-org-test--read-file path)))
        (should (string-match-p
                 "file:/tmp/papers/Atakisi2019Resolution.pdf" body))
        (should-not (string-match-p "file:/tmp/books/" body))
        (should (string-match-p "article PDF" body))
        (should-not (string-match-p "book PDF" body))))))

(ert-deftest mab-org-test-add-bib-item-creates-note ()
  "The per-citekey abibnote is created if it does not yet exist."
  (mab-org-test-with-temp-dir dir
    (let* ((mab-org-notes-directory dir)
           (mab-org-pdfs-directory dir)
           (mab-org-books-directory dir)
           (path (expand-file-name "mab1.org" dir))
           (note (expand-file-name "Foo2020Bar.org" dir)))
      (mab-org-test--make-mab-file path nil)
      (cl-letf (((symbol-function 'derived-mode-p)
                 (lambda (mode) (eq mode 'ebib-index-mode)))
                ((symbol-function 'ebib--get-key-at-point)
                 (lambda () "Foo2020Bar")))
        (with-temp-buffer
          (mab-org-add-bib-item path)))
      (should (file-exists-p note))
      (should (equal "" (mab-org-test--read-file note))))))

(ert-deftest mab-org-test-add-bib-item-errors-without-bibliography ()
  "A target file lacking the bibliography section signals `user-error'."
  (mab-org-test-with-temp-dir dir
    (let* ((mab-org-notes-directory dir)
           (mab-org-pdfs-directory dir)
           (mab-org-books-directory dir)
           (path (expand-file-name "mab1.org" dir)))
      (with-temp-file path (insert "Just text, no section.\n"))
      (cl-letf (((symbol-function 'derived-mode-p)
                 (lambda (mode) (eq mode 'ebib-index-mode)))
                ((symbol-function 'ebib--get-key-at-point)
                 (lambda () "Foo2020Bar")))
        (with-temp-buffer
          (should-error (mab-org-add-bib-item path) :type 'user-error))))))

(ert-deftest mab-org-test-add-bib-item-rejects-non-ebib-buffer ()
  "Calling outside Ebib's index buffer signals `user-error'."
  (mab-org-test-with-temp-dir dir
    (let ((path (expand-file-name "mab1.org" dir)))
      (mab-org-test--make-mab-file path 'with-backmatter)
      (with-temp-buffer
        ;; Not in ebib-index-mode; derived-mode-p left at default.
        (should-error (mab-org-add-bib-item path) :type 'user-error)))))

;;;; Public command surface

(ert-deftest mab-org-test-public-commands-bound ()
  (dolist (sym '(mab-org-wrap-citekey
                 mab-org-wrap-citekey-abib
                 mab-org-insert-matching-keys
                 mab-org-wrap-region
                 mab-org-create-project
                 mab-org-open-file
                 mab-org-add-bib-item))
    (should (fboundp sym))))

(ert-deftest mab-org-test-public-commands-are-interactive ()
  (dolist (sym '(mab-org-wrap-citekey
                 mab-org-wrap-citekey-abib
                 mab-org-insert-matching-keys
                 mab-org-wrap-region
                 mab-org-create-project
                 mab-org-open-file
                 mab-org-add-bib-item))
    (should (commandp sym))))

(provide 'mab-org-test)

;;; mab-org-test.el ends here
