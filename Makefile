# Makefile for mab-org.el
#
# Common targets:
#   make all           Byte-compile + run the test suite (default).
#   make test          Run the ERT test suite in batch mode.
#   make compile       Byte-compile mab-org.el to mab-org.elc.
#   make info          Build mab-org.info from mab-org.texi.
#   make install       Install mab-org.el into $(EMACSDIR).
#   make install-info  Install mab-org.info into $(INFODIR).
#   make uninstall     Remove the installed mab-org.el.
#   make uninstall-info  Remove the installed mab-org.info.
#   make lint          Run checkdoc against mab-org.el.
#   make clean         Remove all build products.
#   make help          Print this list.
#
# GNU-style overrides:
#   PREFIX             Default $(HOME)/.local
#   EMACSDIR           Default $(PREFIX)/share/emacs/site-lisp
#   INFODIR            Default $(PREFIX)/share/info
#   EMACS              Default emacs
#   INSTALL            Default install
#   INSTALL_INFO       Default install-info
#
# Examples:
#   make install                            # user-level install
#   sudo make PREFIX=/usr/local install     # system-level install

# ----- Tooling -----
EMACS        ?= emacs
MAKEINFO     ?= makeinfo
INSTALL      ?= install
INSTALL_INFO ?= install-info

# ----- Project files -----
PKG     = mab-org
SRC     = $(PKG).el
TESTS   = $(PKG)-test.el
ELC     = $(PKG).elc
TESTELC = $(PKG)-test.elc
TEXI    = $(PKG).texi
INFO    = $(PKG).info

# ----- Install paths -----
PREFIX   ?= $(HOME)/.local
EMACSDIR ?= $(PREFIX)/share/emacs/site-lisp
INFODIR  ?= $(PREFIX)/share/info

EMACS_BATCH = $(EMACS) -Q --batch --eval "(setq load-prefer-newer t)" -L .

.PHONY: all test compile info lint clean help \
        install uninstall install-info uninstall-info

all: compile test

help:
	@echo "Targets:"
	@echo "  make all            Byte-compile + run tests (default)."
	@echo "  make test           Run the ERT suite in batch mode."
	@echo "  make compile        Byte-compile $(SRC) to $(ELC)."
	@echo "  make info           Build $(INFO) from $(TEXI)."
	@echo "  make install        Install $(SRC) to \$$(EMACSDIR)."
	@echo "  make install-info   Install $(INFO) to \$$(INFODIR)."
	@echo "  make uninstall      Remove the installed $(SRC)."
	@echo "  make uninstall-info Remove the installed $(INFO)."
	@echo "  make lint           Run checkdoc on $(SRC)."
	@echo "  make clean          Remove build products."
	@echo ""
	@echo "Override PREFIX, EMACSDIR, or INFODIR to change install"
	@echo "locations.  PREFIX defaults to $(HOME)/.local."

# ----- Build rules -----

compile: $(ELC)

$(ELC): $(SRC)
	$(EMACS_BATCH) -f batch-byte-compile $(SRC)

info: $(INFO)

$(INFO): $(TEXI)
	$(MAKEINFO) --no-split -o $@ $<

# Run the ERT suite.  We do NOT depend on $(ELC) because tests should
# also pass against the .el source.  Any stale byte-compiled file is
# removed up front so Emacs cannot load an outdated definition.
test:
	@rm -f $(ELC) $(TESTELC)
	$(EMACS_BATCH) -l ert -l $(TESTS) \
	    -f ert-run-tests-batch-and-exit

lint:
	$(EMACS_BATCH) --eval "(checkdoc-file \"$(SRC)\")"

clean:
	rm -f $(ELC) $(TESTELC) $(INFO)

# ----- Install / uninstall -----

install: $(SRC)
	$(INSTALL) -d $(DESTDIR)$(EMACSDIR)
	$(INSTALL) -m 0644 $(SRC) $(DESTDIR)$(EMACSDIR)/$(SRC)
	@echo "Installed $(SRC) -> $(DESTDIR)$(EMACSDIR)/$(SRC)"
	@echo "Add the following to your init file if you have not already:"
	@echo "  (add-to-list 'load-path \"$(EMACSDIR)\")"
	@echo "  (require 'mab-org)"

uninstall:
	rm -f $(DESTDIR)$(EMACSDIR)/$(SRC) $(DESTDIR)$(EMACSDIR)/$(ELC)
	@echo "Removed $(DESTDIR)$(EMACSDIR)/$(SRC)"

install-info: $(INFO)
	$(INSTALL) -d $(DESTDIR)$(INFODIR)
	$(INSTALL) -m 0644 $(INFO) $(DESTDIR)$(INFODIR)/$(INFO)
	$(INSTALL_INFO) --info-dir="$(DESTDIR)$(INFODIR)" $(DESTDIR)$(INFODIR)/$(INFO)
	@echo "Installed $(INFO) -> $(DESTDIR)$(INFODIR)/$(INFO)"
	@echo "Open with C-h i d m Mab-Org RET inside Emacs."

uninstall-info:
	-$(INSTALL_INFO) --remove --info-dir="$(DESTDIR)$(INFODIR)" $(DESTDIR)$(INFODIR)/$(INFO)
	rm -f $(DESTDIR)$(INFODIR)/$(INFO)
	@echo "Removed $(DESTDIR)$(INFODIR)/$(INFO)"
