all:

WGET = wget
CURL = curl
GIT = git
PERL = ./perl

updatenightly: local/bin/pmbp.pl
	$(CURL) -s -S -L https://gist.githubusercontent.com/wakaba/34a71d3137a52abb562d/raw/gistfile1.txt | sh
	$(GIT) add modules t_deps/modules
	perl local/bin/pmbp.pl --update
	$(GIT) add config

## ------ Setup ------

deps: git-submodules pmbp-install cinnamon

git-submodules:
	$(GIT) submodule update --init

local/bin/pmbp.pl:
	mkdir -p local/bin
	$(WGET) -O $@ https://raw.github.com/wakaba/perl-setupenv/master/bin/pmbp.pl
pmbp-upgrade: local/bin/pmbp.pl
	perl local/bin/pmbp.pl --update-pmbp-pl
pmbp-update: git-submodules pmbp-upgrade
	perl local/bin/pmbp.pl --update
pmbp-install: pmbp-upgrade
	perl local/bin/pmbp.pl --install \
            --create-perl-command-shortcut perl \
            --create-perl-command-shortcut prove \
            --create-perl-command-shortcut plackup

## ------ Deploy ------

cinnamon:
	$(PERL) local/bin/pmbp.pl --install-perl-app git://github.com/wakaba/cinnamon
	echo "#!$(abspath $(PERL))" > local/cinnamon/bin/cinnamon2
	cat local/cinnamon/bin/cinnamon >> local/cinnamon/bin/cinnamon2
	cd local/cinnamon && ../../perl local/bin/pmbp.pl --create-perl-command-shortcut cinnamon=bin/cinnamon2
	chmod u+x local/cinnamon/bin/cinnamon2
	$(PERL) local/bin/pmbp.pl --create-perl-command-shortcut cin=local/cinnamon/cinnamon

## ------ Tests ------

PROVE = ./prove

test: test-deps test-main

test-deps: deps test-home

test-home:
	mkdir -p local/home
	$(GIT) config --file local/home/.gitconfig user.name test
	$(GIT) config --file local/home/.gitconfig user.email test@test

test-main:
	HOME="$(abspath local/home)" $(PROVE) t/*.t
