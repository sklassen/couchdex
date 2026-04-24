#
# Makefile for CouchDB Design Documents
#
# This Makefile helps manage CouchDB design documents by providing targets to
# pull, push, and build them from a local directory structure.
#

define USAGE
couchdex.mk (version ${COUCH_VERSION})

Usage
  make -f couchdex.mk [target]

Environment Variables
	COUCH_HOST          "127.0.0.1"
	COUCH_PORT               "5984"
	COUCH_DB       [parent dirname]
	COUCH_DESIGN          [dirname]
	COUCH_ADMIN             "admin"
	COUCH_PASSWD          [require]

Available targets:
  version          - Show version and exit
  status           - Report current status
  init             - Create a Makefile with a sample view
  fetch            - Fetch (GET) design from the database
  pull             - Pull the design document into the directory
  push             - Push (PUT) design to the database
  push-force       - Push (PUT) without reference to the revision
  revert           - Show current revisions
  clone            - Clone a design from the database
  cleanup          - Removed unreferences views
  compact          - Compact a view
  dbs              - Get a list of databases
  create           - Create a database on the server
  compactdb        - Compact the database
  security         - Pull security data
  check            - Confirm couchdex.mk is installed correctly
  clean            - Remove generated files
  help             - Display this help message
endef

export USAGE

# ==============================================================================
# External Commands
# ==============================================================================

CURL := curl
JQ := jq
JQRAW := jq --raw-input --slurp '.'
CAT := cat
RM := rm -rf

# ==============================================================================
# Include User Environment
# ==============================================================================

COUCH_RC ?= ${HOME}/.couchdexrc
-include ${COUCH_RC}

# ==============================================================================
# Project Settings
# ==============================================================================

.SILENT:

COUCH_VERBOSE ?= 0
COUCH_VERSION := 0.2

# ==============================================================================
# User-Configurable Variables
# ==============================================================================

COUCH_SCHEME ?= http
COUCH_HOST ?= 127.0.0.1
COUCH_PORT ?= 5984

COUCH_ADMIN ?= admin
COUCH_PASSWD ?= 

COUCH_DB ?=	$(notdir $(patsubst %/,%,$(dir $(CURDIR))))
COUCH_DESIGN ?= $(notdir $(CURDIR))

COUCH_Q ?= 4

# ==============================================================================
# Derived Variables
# ==============================================================================

COUCH_USERINFO := ${COUCH_ADMIN}:${COUCH_PASSWD}@
COUCH_AUTHORITY := ${COUCH_USERINFO}${COUCH_HOST}:${COUCH_PORT}
COUCH_SRV := ${COUCH_SCHEME}://${COUCH_AUTHORITY}
COUCH_URL := ${COUCH_SRV}/${COUCH_DB}
COUCH_DESIGN_DOC := ${COUCH_URL}/_design/${COUCH_DESIGN}

COUCH_DIR := .couchdex

COUCH_DESIGN_DNLOAD = $(COUCH_DIR)/design_${COUCH_DESIGN}_server.json
COUCH_DESIGN_FILTER = $(COUCH_DIR)/design_${COUCH_DESIGN}_filter.jq
COUCH_DESIGN_BUILD = $(COUCH_DIR)/design_${COUCH_DESIGN}_tmp.json
COUCH_DESIGN_UPLOAD = $(COUCH_DIR)/design_${COUCH_DESIGN}_local.json

COUCH_DESIGN_REV = $(shell ${JQ} -j ._rev ${COUCH_DESIGN_DNLOAD})
COUCH_DESIGN_REV_FORCE = $(shell ${CURL} -s -X GET ${COUCH_DESIGN_DOC} | ${JQ} -j ._rev)

COUCH_DESIGN_LANGUAGE := language
COUCH_DESIGN_FIELDS := rewrite validate_doc_update
COUCH_DESIGN_VIEWS := views
COUCH_DESIGN_DIRECTORIES := filters lists shows updates

COUCH_SUFFIX := $(if $(findstring erlang, $(file <${COUCH_DESIGN_DNLOAD})),erl,js)


# ==============================================================================
# Pre-flight Checks
# ==============================================================================

# Checks for required commands
ifeq (, $(shell which ${JQ}))
$(error "No ${JQ} in $(PATH), consider apt-get install jq")
endif

ifeq (, $(shell which ${CURL}))
$(error "No ${CURL} in $(PATH), consider apt-get install curl")
endif

# Checks for required variables
ifndef COUCH_DB
$(error COUCH_DB is not set)
endif

ifndef COUCH_PASSWD
$(error COUCH_PASSWD is not set)
endif

# ==============================================================================
# Verbosity Settings
# ==============================================================================

V_0 := @
V_1 :=
V := ${V_${COUCH_VERBOSE}}

ifeq ($(COUCH_VERBOSE),1)
SHELL := $(SHELL) -x
endif

# ==============================================================================
# Core Functions
# ==============================================================================

empty :=
space := $(empty) $(empty)
tab := $(empty)	$(empty)
comma := ,

define eol


endef

define freeze0
$(foreach f, $1, |.$(notdir $(basename ${f}))=$(shell ${JQRAW} ${f}))
endef

define freeze1
$(foreach d, $1, |.views.$(notdir $(patsubst %/,%,$(dir ${d}))).$(notdir $(basename ${d}))=$(shell ${JQRAW} ${d}))
endef

define escape
$(subst $(eol),\n,$(subst $(tab),\t,$(subst \\,\,$(subst ",\",$1))))
endef

define chomp
$(subst $(eol),,$1)
endef

# ==============================================================================
# File Existence Check
# ==============================================================================

FILE_EXISTS := $(or $(and $(wildcard Makefile),1),0)

# ==============================================================================
# Phony Targets
# ==============================================================================

.PHONY: help version status dbs create security compact compactdb cleanup init pull push push-force revs clone diff check clean

# ==============================================================================
# Help and Informational Targets
# ==============================================================================


help:
	@printf "%s\n\n" "$$USAGE"

version:
	@echo ${COUCH_VERSION}

status:
	@echo "Targeting: ${COUCH_DESIGN_DOC}"	
	@echo "Language: ${COUCH_SUFFIX}"
	@echo "Revision: $(shell ${JQ} -j '._rev' ${COUCH_DESIGN_DNLOAD})"

# ==============================================================================
# Server and Database Management Targets
# ==============================================================================

dbs:
	${V}${CURL} -s -X GET ${COUCH_SRV}/_all_dbs | ${JQ} '. | join(" ")'

create:
	${V}${CURL} -s -X PUT "${COUCH_URL}?q=${COUCH_Q}"

security:
	${V}${CURL} -s -X GET ${COUCH_URL}/_security

cleanup:
	${V}${CURL} -s -X POST ${COUCH_URL}/_view_cleanup

compactdb:
	${V}${CURL} -s -X POST ${COUCH_URL}/_compact

compact:
	${V}${CURL} -s -X POST ${COUCH_URL}/_compact/${COUCH_DESIGN} -H 'Content-Type: application/json'

# ==============================================================================
# Design Document Management Targets
# ==============================================================================

$(COUCH_DIR):
	@mkdir -p $@

# Fails (but continues) on not found, leaving file size zero.
${COUCH_DESIGN_DNLOAD}: | $(COUCH_DIR)
	-${CURL} --fail -s -X GET ${COUCH_DESIGN_DOC} > ${COUCH_DESIGN_DNLOAD}

fetch: ${COUCH_DESIGN_DNLOAD}
	${V}${JQ} ._rev ${COUCH_DESIGN_DNLOAD}

push: ${COUCH_DESIGN_BUILD}
	${V}${CAT} ${COUCH_DESIGN_BUILD} > ${COUCH_DESIGN_UPLOAD}
	${V}${CURL} -s -X PUT ${COUCH_DESIGN_DOC} -d "@${COUCH_DESIGN_UPLOAD}" -H 'Content-Type: application/json'
	${V}${CURL} -s -X GET ${COUCH_DESIGN_DOC} > ${COUCH_DESIGN_DNLOAD}
	${V}${RM} ${COUCH_DESIGN_BUILD}
	${V}${RM} ${COUCH_DESIGN_UPLOAD}

push-force: ${COUCH_DESIGN_BUILD}
	${V}${JQ} '._rev="${COUCH_DESIGN_REV_FORCE}"' ${COUCH_DESIGN_BUILD} > ${COUCH_DESIGN_UPLOAD}
	${V}${CURL} -s -X PUT ${COUCH_DESIGN_DOC} -d "@${COUCH_DESIGN_UPLOAD}" -H 'Content-Type: application/json'
	${V}${RM} ${COUCH_DESIGN_BUILD}
	${V}${RM} ${COUCH_DESIGN_UPLOAD}

revs:
	${V}${CURL} -s -X GET ${COUCH_DESIGN_DOC}?revs_info=true | ${JQ} '._revs_info[].rev'



ID=._id="_design/${COUCH_DESIGN}"
REV=$(if ${COUCH_DESIGN_REV},|._rev="${COUCH_DESIGN_REV}",$(empty))
LANGUAGE=\
	$(if $(wildcard language),\
		|.language="$(call chomp,$(file <language))",\
		$(empty)\
	)
VALIDATE=\
	$(if $(wildcard validate_doc_update.*),\
		|.validate_doc_update="$(call escape,$(file < validate_doc_update.${COUCH_SUFFIX}))"\
		$(empty)\
	)
DIRECTORIES=\
	$(foreach d, $(COUCH_DESIGN_DIRECTORIES),\
		$(foreach f,$(wildcard $d/.),\
		|.${d}=$(shell echo "{}" | ${JQ} -j '.\
		$(call freeze0,$(wildcard $d/*))\
		')\
		)\
	)
VIEWS=\
	$(if $(wildcard views/.),\
		$(call freeze1,$(wildcard views/*/*)),\
		$(empty)\
	)

${COUCH_DESIGN_FILTER}: ${COUCH_DESIGN_DNLOAD} | $(COUCH_DIR)
	${V}echo '${ID}${REV}${LANGUAGE}${VALIDATE}${DIRECTORIES}${VIEWS}' > $@

${COUCH_DESIGN_BUILD}: ${COUCH_DESIGN_FILTER}| $(COUCH_DIR)
	${V}echo $(COUCH_DESIGN_REV)
	${V}echo "{}" | ${JQ} -f ${COUCH_DESIGN_FILTER} > $@
	${V}${RM} ${COUCH_DESIGN_FILTER}

pull: ${COUCH_DESIGN_DNLOAD}
	$(eval COUCH_DESIGN_KEYS := $(shell ${JQ} -j '. | keys | join(" ")' ${COUCH_DESIGN_DNLOAD}))
	${V}echo "pull: ${COUCH_DESIGN_KEYS}"

	# files
	$(foreach f, $(filter $(COUCH_DESIGN_KEYS),$(COUCH_DESIGN_LANGUAGE)),\
		${JQ} -j '.language' ${COUCH_DESIGN_DNLOAD} >language \
	)

	# files
	$(foreach f, $(filter $(COUCH_DESIGN_KEYS),$(COUCH_DESIGN_FIELDS)),\
		${JQ} -j '.$f + "\n" | @text' ${COUCH_DESIGN_DNLOAD} > $f.${COUCH_SUFFIX} \
	)

	# directories
	$(foreach d, $(filter $(COUCH_DESIGN_KEYS),$(COUCH_DESIGN_DIRECTORIES)),\
	  $(foreach f,$(shell ${JQ} -j '.$d | keys | join(" ")' ${COUCH_DESIGN_DNLOAD}),\
			mkdir -p "$d"; \
			${JQ} -j '.$d.$f + "\n" | @text' ${COUCH_DESIGN_DNLOAD} > $d/$f.${COUCH_SUFFIX}; \
		)\
	)

	# views
	$(foreach t, $(filter $(COUCH_DESIGN_KEYS),$(COUCH_DESIGN_VIEWS)),\
		$(foreach d, $(shell ${JQ} -j '.views | keys | join(" ")' ${COUCH_DESIGN_DNLOAD}),\
			mkdir -p "views/$d";\
	  		$(foreach f, $(shell ${JQ} -j '.views.$d | keys | join(" ")' ${COUCH_DESIGN_DNLOAD}),\
				${JQ} -j '.views.$d.$f + "\n" | @text' ${COUCH_DESIGN_DNLOAD} > views/$d/$f.${COUCH_SUFFIX};\
			)\
		)\
	)

clone: fetch pull

# ==============================================================================
# Miscellaneous Targets
# ==============================================================================

Makefile:
	@echo "$(eol)COUCH_ADMIN=${COUCH_ADMIN}$(eol)#COUCH_PASSWD=PASSWD_HERE$(eol)$(eol)COUCH_DB=${COUCH_DB}$(eol)COUCH_DESIGN=${COUCH_DESIGN}$(eol)$(eol)include$(space)$(MAKEFILE_LIST)$(eol)$(eol))" >@_

init: Makefile
	@echo "Makefile"

diff: ${COUCH_DESIGN_DNLOAD} ${COUCH_DESIGN_BUILD}
	@echo "Comparing design documents"
	${JQ} -S . ${COUCH_DESIGN_DNLOAD} > $(COUCH_DIR)/left.json
	${JQ} -S . ${COUCH_DESIGN_BUILD} > $(COUCH_DIR)/right.json
	@-diff -w -y --left-column --color $(COUCH_DIR)/left.json $(COUCH_DIR)/right.json
	@rm -f $(COUCH_DIR)/left.json $(COUCH_DIR)/right.json ${COUCH_DESIGN_BUILD}

check:
	@$(if ${COUCH_DESIGN_REV},echo "Current revision: ${COUCH_DESIGN_REV}",echo "COUCH_DESIGN_REV is empty")

clean:
	${V}${RM} ${COUCH_DESIGN_DNLOAD} ${COUCH_DESIGN_FILTER} ${COUCH_DESIGN_BUILD} ${COUCH_DESIGN_UPLOAD}

