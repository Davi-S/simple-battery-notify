PREFIX ?= /usr/local
SYSCONFDIR ?= /etc
DESTDIR ?=

BINDIR      = $(DESTDIR)$(PREFIX)/bin
MANDIR      = $(DESTDIR)$(PREFIX)/share/man/man1
DOCDIR      = $(DESTDIR)$(PREFIX)/share/doc/simple-battery-notify
BASHCOMPDIR = $(DESTDIR)$(PREFIX)/share/bash-completion/completions
USERUNITDIR = $(DESTDIR)$(PREFIX)/lib/systemd/user
CONFDIR     = $(DESTDIR)$(SYSCONFDIR)

SHELL_SOURCES = src/battery-notify completions/battery-notify.bash scripts/*.sh \
                tests/helpers.bash tests/fakes/fake tests/*.bats tests/integration.sh

BATS ?= bats

.PHONY: all install uninstall check test integration

all:
	@echo "Nothing to build. Run 'make install' (PREFIX=$(PREFIX))."

# The service file gets the real path of the program (it differs with PREFIX).
install:
	install -Dm755 src/battery-notify              $(BINDIR)/battery-notify
	install -Dm644 config/battery-notify.json      $(CONFDIR)/battery-notify.json
	install -d $(USERUNITDIR)
	sed 's|@BINDIR@|$(PREFIX)/bin|' systemd/battery-notify.service >$(USERUNITDIR)/battery-notify.service
	chmod 644 $(USERUNITDIR)/battery-notify.service
	install -Dm644 man/battery-notify.1            $(MANDIR)/battery-notify.1
	install -Dm644 completions/battery-notify.bash $(BASHCOMPDIR)/battery-notify
	install -Dm644 README.md                       $(DOCDIR)/README.md

uninstall:
	rm -f  $(BINDIR)/battery-notify
	rm -f  $(CONFDIR)/battery-notify.json
	rm -f  $(USERUNITDIR)/battery-notify.service
	rm -f  $(MANDIR)/battery-notify.1
	rm -f  $(BASHCOMPDIR)/battery-notify
	rm -rf $(DOCDIR)

# Lint and formatting check (same as CI).
check:
	shellcheck -x $(SHELL_SOURCES)
	shfmt -d $(SHELL_SOURCES)

# Run the test suite (needs bats: pacman -S bash-bats).
test:
	$(BATS) tests

# Test against the real UPower; run locally before each release.
# CHARGER=1 adds the unplug/replug check (interactive).
integration:
	tests/integration.sh $(if $(CHARGER),--charger)
