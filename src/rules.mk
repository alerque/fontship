# Defalut to running jobs in parallel, one for each CPU core
MAKEFLAGS += --jobs=$(shell nproc) --output-sync=target
# Default to not echoing commands before running
MAKEFLAGS += --silent
# Disable as much built in file type builds as possible
MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

# Run recipies in zsh, and all in one pass
SHELL := zsh
.SHELLFLAGS := +o nomatch -e -c
.ONESHELL:
.SECONDEXPANSION:

# Don't drop intermediate artifacts (saves rebulid time and aids debugging)
.SECONDARY:
.PRECIOUS: %
.DELETE_ON_ERROR:

CONTAINERIZED != test -f /.dockerenv && echo true || echo false

# Initial environment setup
FONTSHIPDIR != cd "$(shell dirname $(lastword $(MAKEFILE_LIST)))/" && pwd
GITNAME := $(notdir $(shell git worktree list | head -n1 | awk '{print $$1}'))
PROJECT ?= $(GITNAME)
_PROJECTDIR != cd "$(shell dirname $(firstword $(MAKEFILE_LIST)))/" && pwd
PROJECTDIR ?= $(_PROJECTDIR)
PUBDIR ?= $(PROJECTDIR)/pub
# Some Makefile shinanigans to avoid aggressive trimming
space := $() $()

CANONICAL ?= $(shell git ls-files | grep -q '\.glyphs$'' && echo glyphs || echo ufo)

# Allow overriding executables used
FONTMAKE ?= fontmake
FONTV ?= font-v
GFTOOLS ?= gftools
PYTHON ?= python3
SFNT2WOFF ?= sfnt2woff-zopfli
TTFAUTOHINT ?= ttfautohint
TTX ?= ttx
WOFF2COMPRESS ?= woff2_compress

include $(FONTSHIPDIR)/functions.mk

# Read font name from metadata file or guess from repository name
ifeq ($(CANONICAL),glyphs)
FamilyName = $(call glyphsFamilyName,$(firstword $(wildcard *.glyphs)))
endif

ifeq ($(CANONICAL),ufo)
FamilyName = $(call ufoFamilyName,$(firstword $(wildcard *.ufo)))
endif

FamilyName ?= $(shell $(CONTAINERIZED) || $(PYTHON) $(PYTHONFLAGS) -c 'print("$(PROJECT)".replace("-", " ").title())')

ifeq ($(FamilyName),)
$(error We cannot properly detect the font’s Family Name yet from inside Docker. Please manually specify it by adding FamilyName='Family Name' as an agument to your command invocation)
endif

GITVER = --tags --abbrev=6 --match='[0-9].[0-9][0-9][0-9]'
# Determine font version automatically from repository git tags
FontVersion ?= $(shell git describe $(GITVER) | sed 's/-.*//g')
ifneq ($(FontVersion),)
FontVersionMeta ?= $(shell git describe --always --long $(GITVER) | sed 's/-[0-9]\+/\\;/;s/-g/[/')]
GitVersion ?= $(shell git describe $(GITVER) | sed 's/-/-r/')
isTagged := $(if $(subst $(FontVersion),,$(GitVersion)),,true)
else
FontVersion = 0.000
FontVersionMeta ?= $(FontVersion)\;[$(shell git rev-parse --short=6 HEAD)]
GitVersion ?= $(FontVersion)-r$(shell git rev-list --count HEAD)-g$(shell git rev-parse --short=6 HEAD)
isTagged :=
endif

# Look for what fonts & styles are in this repository that will need building
FontBase = $(subst $(space),,$(FamilyName))

# FontStyles = $(subst $(FontBase)-,,$(basename $(wildcard $(FontBase)-*.ufo)))
FontStyles += $(foreach UFO,$(wildcard *.ufo),$(call ufoInstances,$(UFO)))
FontStyles += $(foreach GLYPHS,$(wildcard *.glyphs),$(call glyphInstances$(GLYPHS)))

INSTANCES = $(foreach BASE,$(FontBase),$(foreach STYLE,$(FontStyles),$(BASE)-$(STYLE)))

STATICOTFS = $(addsuffix .otf,$(INSTANCES))
STATICTTFS = $(addsuffix .ttf,$(INSTANCES))
STATICWOFFS = $(addsuffix .woff,$(INSTANCES))
STATICWOFF2S = $(addsuffix .woff2,$(INSTANCES))
ifeq ($(CANONICAL),glyphs)
VARIABLEOTFS = $(addsuffix -VF.otf,$(FontBase))
VARIABLETTFS = $(addsuffix -VF.ttf,$(FontBase))
VARIABLEWOFFS = $(addsuffix -VF.woff,$(FontBase))
VARIABLEWOFF2S = $(addsuffix -VF.woff2,$(FontBase))
endif

ifeq ($(DEBUG),true)
.SHELLFLAGS += +x
MAKEFLAGS += --no-silent
FONTMAKEFLAGS ?= --verbose DEBUG
FONTVFLAGS ?=
TTFAUTOHINTFLAGS ?= -v --debug
TTXFLAGS ?= -v
WOFF2COMPRESSFLAGS ?=
GFTOOLSFLAGS ?=
PYTHONFLAGS ?= -d
SFNT2WOFFFLAGS ?=
else
ifeq ($(VERBOSE),true)
MAKEFLAGS += --no-silent
FONTMAKEFLAGS ?= --verbose INFO
FONTVFLAGS ?=
GFTOOLSFLAGS ?=
PYTHONFLAGS ?= -v
SFNT2WOFFFLAGS ?=
TTFAUTOHINTFLAGS ?= -v
TTXFLAGS ?= -v
WOFF2COMPRESSFLAGS ?=
else
ifeq ($(QUIET),true)
FONTMAKEFLAGS ?= --verbose ERROR 2> /dev/null
FONTVFLAGS ?= 2> /dev/null
GFTOOLSFLAGS ?= 2> /dev/null
PYTHONFLAGS ?= 2> /dev/null
SFNT2WOFFFLAGS ?= 2> /dev/null
TTFAUTOHINTFLAGS ?= 2> /dev/null
TTXFLAGS ?= 2> /dev/null
WOFF2COMPRESSFLAGS ?= 2> /dev/null
else
FONTMAKEFLAGS ?= --verbose WARNING
FONTVFLAGS ?=
GFTOOLSFLAGS ?=
PYTHONFLAGS ?=
SFNT2WOFFFLAGS ?=
TTFAUTOHINTFLAGS ?=
TTXFLAGS ?=
WOFF2COMPRESSFLAGS ?=
endif
endif
endif

.PHONY: default
default: all

.PHONY: debug
debug:
	echo FONTSHIPDIR = $(FONTSHIPDIR)
	echo GITNAME = $(GITNAME)
	echo PROJECT = $(PROJECT)
	echo PROJECTDIR = $(PROJECTDIR)
	echo PUBDIR = $(PUBDIR)
	echo ----------------------------
	echo FamilyName = $(FamilyName)
	echo FontBase = $(FontBase)
	echo FontStyles = $(FontStyles)
	echo FontVersion = $(FontVersion)
	echo FontVersionMeta = $(FontVersionMeta)
	echo GitVersion = $(GitVersion)
	echo isTagged = $(isTagged)
	echo ----------------------------
	echo CANONICAL = $(CANONICAL)
	echo INSTANCES = $(INSTANCES)
	echo STATICOTFS = $(STATICOTFS)
	echo STATICTTFS = $(STATICTTFS)
	echo STATICWOFFS = $(STATICWOFFS)
	echo STATICWOFF2S = $(STATICWOFF2S)
	echo VARIABLEOTFS = $(VARIABLEOTFS)
	echo VARIABLETTFS = $(VARIABLETTFS)
	echo VARIABLEWOFFS = $(VARIABLEWOFFS)
	echo VARIABLEWOFF2S = $(VARIABLEWOFF2S)

.PHONY: _gha
_gha:
	echo "::set-output name=family-name::$(FamilyName)"
	echo "::set-output name=font-version::$(FontVersion)"
	echo "::set-output name=DISTDIR::$(DISTDIR)"

.PHONY: all
all: debug fonts

.PHONY: clean
clean:
	git clean -dxf

.PHONY: glyphs
glyphs: $$(addsuffix .glyphs,$$(INSTANCES))

.PHONY: fontforge
fontforge: $$(addsuffix .sfd,$$(INSTANCES))

.PHONY: fonts
fonts: static variable

.PHONY: static
static: static-otf static-ttf static-woff static-woff2

.PHONY: variable
variable: variable-otf variable-ttf variable-woff variable-woff2

.PHONY: otf
otf: static-otf variable-otf

.PHONY: ttf
ttf: static-ttf variable-ttf

.PHONY: woff
woff: static-woff variable-woff

.PHONY: woff2
woff2: static-woff2 variable-woff2

.PHONY: static-otf
static-otf: $$(STATICOTFS)

.PHONY: static-ttf
static-ttf: $$(STATICTTFS)

.PHONY: static-woff
static-woff: $$(STATICWOFFS)

.PHONY: static-woff2
static-woff2: $$(STATICWOFF2S)

.PHONY: variable-otf
variable-otf: $$(VARIABLEOTFS)

.PHONY: variable-ttf
variable-ttf: $$(VARIABLETTFS)

.PHONY: variable-woff
variable-woff: $$(VARIABLEWOFFS)

.PHONY: variable-woff2
variable-woff2: $$(VARIABLEWOFF2S)

BUILDDIR ?= .fontship

$(BUILDDIR):
	mkdir -p $@

ifeq ($(CANONICAL),sfd)

%.sfd: %.ufo
	echo SDF: $@

endif
ifeq ($(CANONICAL),ufo)

# UFO normalize

%.ufo: $(BUILDDIR)/last-commit
	cat <<- EOF | $(PYTHON) $(PYTHONFLAGS)
		from defcon import Font, Info
		ufo = Font('$@')
		major, minor = "$(FontVersion)".split(".")
		ufo.info.versionMajor, ufo.info.versionMinor = int(major), int(minor) + 7
		ufo.save('$@')
	EOF

# UFO -> OTF

%.otf: %.ufo $(BUILDDIR)/last-commit
	cat <<- EOF | $(PYTHON) $(PYTHONFLAGS)
		from ufo2ft import compileOTF
		from defcon import Font
		ufo = Font('$<')
		otf = compileOTF(ufo)
		otf.save('$@')
	EOF
	$(normalizeVersion)

# UFO -> TTF

$(BUILDDIR)/%-instance.ttf: %.ufo $(BUILDDIR)/last-commit | $(BUILDDIR)
	$(FONTMAKE) $(FONTMAKEFLAGS) -u $< -o ttf --output-path $@
	$(GFTOOLS) $(GFTOOLSFLAGS) fix-dsig --autofix $@

$(STATICTTFS): %.ttf: $(BUILDDIR)/%-instance.ttf $(BUILDDIR)/last-commit
	$(TTFAUTOHINT) $(TTFAUTOHINTFLAGS) -n $< $@
	$(normalizeVersion)

endif
ifeq ($(CANONICAL),glyphs)

FONTMAKEFLAGS += --master-dir '{tmp}' --instance-dir '{tmp}'

%.glyphs: %.ufo
	$(FONTMAKE) $(FONTMAKEFLAGS) -u $< -o glyphs --output-path $@

# %.ufo: %.glyphs
#     $(FONTMAKE) $(FONTMAKEFLAGS) -g $< -o ufo

%.designspace: %.glyphs
	echo MM $@

# Glyphs -> Varibale OTF

$(BUILDDIR)/%-VF-variable.otf: %.glyphs | $(BUILDDIR)
	$(FONTMAKE) $(FONTMAKEFLAGS) -g $< -o variable-cff2 --output-path $@

$(VARIABLEOTFS): %.otf: $(BUILDDIR)/%-variable.otf $(BUILDDIR)/last-commit
	cp $< $@
	$(normalizeVersion)

# Glyphs -> Varibale TTF

$(BUILDDIR)/%-VF-variable.ttf: %.glyphs | $(BUILDDIR)
	$(FONTMAKE) $(FONTMAKEFLAGS) -g $< -o variable --output-path $@
	$(GFTOOLS) $(GFTOOLSFLAGS) fix-dsig --autofix $@

$(BUILDDIR)/%-unhinted.ttf: $(BUILDDIR)/%-variable.ttf
	$(GFTOOLS) $(GFTOOLSFLAGS) fix-nonhinting $< $@

$(BUILDDIR)/%-nomvar.ttx: $(BUILDDIR)/%.ttf
	$(TTX) $(TTXFLAGS) -o $@ -f -x "MVAR" $<

$(BUILDDIR)/%.ttf: $(BUILDDIR)/%.ttx
	$(TTX) $(TTXFLAGS) -o $@ $<

$(VARIABLETTFS): %.ttf: $(BUILDDIR)/%-unhinted-nomvar.ttf $(BUILDDIR)/last-commit
	cp $< $@
	$(normalizeVersion)

# Glyphs -> Static OTF

$(BUILDDIR)/$(FontBase)-%-instance.otf: $(FontBase).glyphs | $(BUILDDIR)
	$(FONTMAKE) $(FONTMAKEFLAGS) -g $< -i "$(FamilyName) $*" -o otf --output-path $@

$(STATICOTFS): %.otf: $(BUILDDIR)/%-instance.otf $(BUILDDIR)/last-commit
	cp $< $@
	$(normalizeVersion)

# Glyphs -> Static TTF

$(BUILDDIR)/$(FontBase)-%-instance.ttf: $(FontBase).glyphs | $(BUILDDIR)
	$(FONTMAKE) $(FONTMAKEFLAGS) -g $< -i "$(FamilyName) $*" -o ttf --output-path $@
	$(GFTOOLS) $(GFTOOLSFLAGS) fix-dsig --autofix $@

$(STATICTTFS): %.ttf: $(BUILDDIR)/%-instance.ttf $(BUILDDIR)/last-commit
	$(TTFAUTOHINT) $(TTFAUTOHINTFLAGS) -n $< $@
	$(normalizeVersion)

endif

# Webfont compressions

%.woff: %.ttf
	$(SFNT2WOFF) $(SFNT2WOFFFLAGS) $<

%.woff2: %.ttf
	$(WOFF2COMPRESS) $(WOFF2COMPRESSFLAGS) $<

# Utility stuff

.PHONY: $(BUILDDIR)/last-commit
$(BUILDDIR)/last-commit: | $(BUILDDIR)
	git update-index --refresh --ignore-submodules ||:
	git diff-index --quiet --cached HEAD -- *.ufo
	ts=$$(git log -n1 --pretty=format:%cI HEAD)
	touch -d "$$ts" -- $@

DISTDIR = $(FontBase)-$(GitVersion)

$(DISTDIR):
	mkdir -p $@

.PHONY: dist
dist: $(DISTDIR).zip $(DISTDIR).tar.bz2

$(DISTDIR).tar.bz2 $(DISTDIR).zip: install-dist
	bsdtar -acf $@ $(DISTDIR)

dist_doc_DATA ?= $(wildcard $(foreach B,readme README,$(foreach E,md txt markdown,$(B).$(E))))
dist_license_DATA ?= $(wildcard $(foreach B,ofl OFL ofl-faq OFL-FAQ license LICENSE copying COPYING,$(foreach E,md txt markdown,$(B).$(E))))

.PHONY: install-dist
install-dist: fonts | $(DISTDIR)
	$(and $(dist_doc_DATA),install -Dm644 -t "$(DISTDIR)/" $(dist_doc_DATA))
	$(and $(dist_license_DATA),install -Dm644 -t "$(DISTDIR)/" $(dist_license_DATA))
	install -Dm644 -t "$(DISTDIR)/static/OTF/" $(STATICOTFS)
	install -Dm644 -t "$(DISTDIR)/static/TTF/" $(STATICTTFS)
	install -Dm644 -t "$(DISTDIR)/static/WOFF/" $(STATICWOFFS)
	install -Dm644 -t "$(DISTDIR)/static/WOFF2/" $(STATICWOFF2S)
ifeq ($(CANONICAL),glyphs)
	install -Dm644 -t "$(DISTDIR)/variable/OTF/" $(VARIABLEOTFS)
	install -Dm644 -t "$(DISTDIR)/variable/TTF/" $(VARIABLETTFS)
	install -Dm644 -t "$(DISTDIR)/variable/WOFF/" $(VARIABLEWOFFS)
	install -Dm644 -t "$(DISTDIR)/variable/WOFF2/" $(VARIABLEWOFF2S)
endif

install-local: install-local-otf

install-local-otf: otf variable-otf
	install -Dm644 -t "$${HOME}/.local/share/fonts/OTF/" $(STATICOTFS)
ifeq ($(CANONICAL),glyphs)
	install -Dm644 -t "$${HOME}/.local/share/fonts/variable/" $(VARIABLEOTFS)
endif

install-local-ttf: ttf variable-ttf
	install -Dm644 -t "$${HOME}/.local/share/fonts/TTF/" $(STATICTTFS)
ifeq ($(CANONICAL),glyphs)
	install -Dm644 -t "$${HOME}/.local/share/fonts/variable/" $(VARIABLETTFS)
endif

# Empty recipie to suppres makefile regeneration
$(MAKEFILE_LIST):;

# Special dependency to force rebuilds of up to date targets
.PHONY: force
force:;
