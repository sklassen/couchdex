#
# Makefile for CouchDB Design Documents
#
# This Makefile helps manage CouchDB design documents by providing targets to
# pull, push, and build them from a local directory structure.
#

# ==============================================================================
# External Commands
# ==============================================================================

CURL := curl
JQ := jq
CAT := cat
SED := sed
RM := rm -rf

# ==============================================================================
# Include User Enviroment
# ==============================================================================

COUCH_RC ?= ${HOME}/.couchdexrc
-include ${COUCH_RC}

# ==============================================================================
# Project Settings
# ==============================================================================

COUCH_VERBOSE ?= 1
COUCH_VERSION := 0.1

# ==============================================================================
# User-Configurable Variables
# ==============================================================================

COUCH_SCHEME ?= http
COUCH_HOST ?= 127.0.0.1
COUCH_PORT ?= 5984

COUCH_ADMIN ?= admin
COUCH_PASSWD ?= 

COUCH_DB ?=	$(notdir $(patsubst %/,%,$(dir $(shell pwd))))
COUCH_DESIGN ?= $(notdir $(shell pwd))

COUCH_Q ?= 4

# ==============================================================================
# Derived Variables
# ==============================================================================

COUCH_USERINFO := ${COUCH_ADMIN}:${COUCH_PASSWD}@
COUCH_AUTHORITY := ${COUCH_USERINFO}${COUCH_HOST}:${COUCH_PORT}
COUCH_SRV := ${COUCH_SCHEME}://${COUCH_AUTHORITY}
COUCH_DBN := ${COUCH_SRV}/${COUCH_DB}
COUCH_DESIGN_DOC := ${COUCH_DBN}/_design/${COUCH_DESIGN}

COUCH_DESIGN_FILE := .design_${COUCH_DESIGN}.json
COUCH_DESIGN_BUILD := .design_${COUCH_DESIGN}_build.json

COUCH_DESIGN_ID := $(shell ${CAT} ${COUCH_DESIGN_FILE} | ${JQ} -j ._id)
COUCH_DESIGN_REV := $(shell ${CAT} ${COUCH_DESIGN_FILE} | ${JQ} -j ._rev)
COUCH_DESIGN_REV_FORCE := $(shell ${V}${CURL} -s -X GET ${COUCH_DESIGN_DOC} | ${JQ} -j ._rev)

COUCH_DESIGN_LANGUAGE := language
COUCH_DESIGN_FILES := validate_doc_update rewrite
COUCH_DESIGN_VIEWS := views
COUCH_DESIGN_DIRECTORIES := updates shows lists filters
COUCH_DESIGN_KEYS := $(shell ${V}${CAT} ${COUCH_DESIGN_FILE} | ${JQ} -j '. | keys | join(" ")' )

COUCH_SUFFIX := $(if $(findstring erlang, $(shell cat $(COUCH_DESIGN_FILE))),"erl","js")

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

ifeq (, $(shell which ${SED}))
$(error "No ${SED} in $(PATH), consider apt-get install sed")
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

define comma_list
$(subst $(space),$(comma),$(strip $(1)))
endef

define escape
$(subst $(eol),\n,$(subst $(tab),\t,$(subst ",\",$1)))
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

.PHONY: help version dbs create security compactdb cleanup init pull push push-force revs clone build compact keys diff check status clean

# ==============================================================================
# Help and Informational Targets
# ==============================================================================

help:
	@echo "couchdex.mk (version ${COUCH_VERSION})"
	@echo ""
	@echo "Usage:"
	@echo "  make -f couchdex.mk [target]"
	@echo ""
	@echo "Available targets:"
	@echo "  version          - Show version and exit"
	@echo "  dbs              - Get a list of databases"
	@echo "  create        		- Create a database on the server"
	@echo "  security      		- Pull security data"
	@echo "  init      				- Create a Makefile with a sample view"
	@echo "  pull      				- Pull (GET) design from the database"
	@echo "  push      				- Push (PUT) design to the database"
	@echo "  revert    				- Show current revisions"
	@echo "  clone     				- Clone a design from the database"
	@echo "  compact   				- Compact a view"
	@echo "  check            - Confirm couchdex.mk is installed correctly"
	@echo "  status           - Report current status"
	@echo "  clean            - Remove generated files"
	@echo "  help             - Display this help message"

version:
	@echo ${COUCH_VERSION}

status:
	@echo "Targeting: ${COUCH_DESIGN_DOC}"
	@echo "Language: ${COUCH_SUFFIX}"
	@echo "Revision: $(subst $\",,$(shell ${CAT} ${COUCH_DESIGN_FILE} | ${JQ} ._rev))"

# ==============================================================================
# Server and Database Management Targets
# ==============================================================================

dbs:
	${V}${CURL} -s -X GET ${COUCH_SRV}/_all_dbs | ${JQ} '. | join(" ")'

create:
	${V}${CURL} -s -X PUT "${COUCH_DBN}?q=${COUCH_Q}"

security:
	${V}${CURL} -s -X GET ${COUCH_DBN}/_security

cleanup:
	${V}${CURL} -s -X POST ${COUCH_DBN}/_view_cleanup

compactdb:
	${V}${CURL} -s -X POST ${COUCH_DBN}/_compact

compact:
	${V}${CURL} -s -X POST ${COUCH_DBN}/_compact/${COUCH_DESIGN}

# ==============================================================================
# Design Document Management Targets
# ==============================================================================

${COUCH_DESIGN_FILE}:
	${V}${CURL} -s -X GET ${COUCH_DESIGN_DOC} | ${JQ} . > ${COUCH_DESIGN_FILE}

init: Makefile
	@echo "Makefile"

Makefile:
	$(file >Makefile,$(eol)COUCH_USER=${COUCH_USER}$(eol)#COUCH_PASSWD=PASSWD_HERE$(eol)$(eol)COUCH_DB=${COUCH_DB}$(eol)COUCH_DESIGN=${COUCH_DESIGN}$(eol)$(eol)include$(space)$(MAKEFILE_LIST)$(eol)$(eol))

pull: ${COUCH_DESIGN_FILE}
	@echo "pulled"

push: build
	${V}${CURL} -s -X PUT ${COUCH_DESIGN_DOC} -d "@${COUCH_DESIGN_BUILD}" -H 'Content-Type: application/json'

push-force: build
	@echo "Forcing push with revision: ${COUCH_DESIGN_REV_FORCE}"
	${V}${SED} -i 's/"_rev":".*"/"_rev":"${COUCH_DESIGN_REV_FORCE}"/' ${COUCH_DESIGN_BUILD}
	${V}${CURL} -s -X PUT ${COUCH_DESIGN_DOC} -d "@${COUCH_DESIGN_BUILD}" -H 'Content-Type: application/json'

revs:
	${V}${CURL} -s -X GET ${COUCH_DESIGN_DOC}?revs_info=true | ${JQ} '._revs_info[].rev'


build:
	$(file >${COUCH_DESIGN_BUILD},{)

	$(file >>${COUCH_DESIGN_BUILD},$(if $(COUCH_DESIGN_ID),"_id":"${COUCH_DESIGN_ID}","_id":"_design/${COUCH_DESIGN}")$(comma))
	$(file >>${COUCH_DESIGN_BUILD},$(if $(COUCH_DESIGN_REV),"_rev":"${COUCH_DESIGN_REV}"$(comma),$(empty)))
	$(file >>${COUCH_DESIGN_BUILD},"couchdex.mk":{"version":"${COUCH_VERSION}"},)

	$(foreach f,$(wildcard language),\
		$(file >>${COUCH_DESIGN_BUILD},"language":"$(call chomp,$(file <${f}))",)\
	)

	$(foreach d,${COUCH_DESIGN_FILES},\
		$(foreach f,$(wildcard $d.*),\
			$(file >>${COUCH_DESIGN_BUILD},"$d":"$(call escape,$(file <${f}))",)\
		)\
	)

	$(foreach t,$(wildcard views),\
		$(file >>${COUCH_DESIGN_BUILD},"${t}":{)\
		$(foreach d,$(wildcard views/*),\
			$(file >>${COUCH_DESIGN_BUILD},"$(notdir ${d})":{)\
			$(foreach f,$(wildcard $d/*),\
				$(file >>${COUCH_DESIGN_BUILD},"$(notdir $(basename ${f}))":"$(call escape,$(file <${f}))",)\
			)\
			$(shell ${SED} -i '$$s/,$$//' ${COUCH_DESIGN_BUILD})\
			$(file >>${COUCH_DESIGN_BUILD},},)\
		)\
		$(shell ${SED} -i '$$s/,$$//' ${COUCH_DESIGN_BUILD})\
		$(file >>${COUCH_DESIGN_BUILD},},)\
	)

	$(foreach d,${COUCH_DESIGN_DIRECTORIES},\
		$(file >>${COUCH_DESIGN_BUILD},"${d}":{)\
		$(foreach f,$(wildcard $d/*),\
    			$(file >>${COUCH_DESIGN_BUILD},"$(notdir $(basename ${f}))":"$(call escape,$(file <${f}))",)\
    		)\
    		$(shell ${SED} -i '$$s/,$$//' ${COUCH_DESIGN_BUILD})\
		$(file >>${COUCH_DESIGN_BUILD},},)\
  	)
	$(shell ${SED} -i '$$s/,$$//' ${COUCH_DESIGN_BUILD})

	$(file >>${COUCH_DESIGN_BUILD},})

	${CAT} ${COUCH_DESIGN_BUILD} | ${JQ} . > ${COUCH_DESIGN_FILE}

clone: ${COUCH_DESIGN_FILE}
	${V}echo "language"
	$(foreach f, $(filter $(COUCH_DESIGN_KEYS),$(COUCH_DESIGN_LANGUAGE)),\
		$(file >language,$(subst $\",,$(shell ${CAT} ${COUCH_DESIGN_FILE} | ${JQ} -j .language)))\
	)

	# files
	$(foreach f, $(filter $(COUCH_DESIGN_KEYS),$(COUCH_DESIGN_FILES)),\
		${CAT} ${COUCH_DESIGN_FILE} | ${JQ} -j '.$f' > $f.${COUCH_SUFFIX} \
	)

	# directories
	$(foreach d, $(filter $(COUCH_DESIGN_KEYS),$(COUCH_DESIGN_DIRECTORIES)),\
	  $(foreach f,$(shell ${CAT} ${COUCH_DESIGN_FILE} | ${JQ} -j '.$d | keys | join(" ")'),\
			mkdir -p "$d"; \
			${CAT} ${COUCH_DESIGN_FILE} | ${JQ} -j '.$d.$f' > $d/$f.${COUCH_SUFFIX}; \
		)\
	)

	# views
	$(foreach t, $(filter $(COUCH_DESIGN_KEYS),$(COUCH_DESIGN_VIEWS)),\
		$(foreach d, $(shell ${CAT} ${COUCH_DESIGN_FILE} | ${JQ} -j '.views | keys | join(" ")'),\
			mkdir -p "views/$d";\
	  		$(foreach f, $(shell ${CAT} ${COUCH_DESIGN_FILE} | ${JQ} -j '.views.$d | keys | join(" ")'),\
				${CAT} ${COUCH_DESIGN_FILE} | ${JQ} -j '.views.$d.$f' > views/$d/$f.${COUCH_SUFFIX};\
			)\
		)\
	)

# ==============================================================================
# Miscellaneous Targets
# ==============================================================================

keys: ${COUCH_DESIGN_FILE}
	@echo ${COUCH_DESIGN_KEYS}

design-diff: ${COUCH_DESIGN_FILE}
	@echo "Comparing language field..."
	@diff <(echo $(shell ${CAT} ${COUCH_DESIGN_FILE} | ${JQ} .language)) <(echo $(shell ${CAT} ${COUCH_DESIGN_BUILD} | ${JQ} .language))
	@echo "Comparing validate_doc_update field..."
	@diff <(echo $(shell ${CAT} ${COUCH_DESIGN_FILE} | ${JQ} .validate_doc_update)) <(echo $(shell ${CAT} ${COUCH_DESIGN_BUILD} | ${JQ} .validate_doc_update))

check:
	@echo "Current revision: ${COUCH_DESIGN_REV}"

clean:
	${V}${RM} ${COUCH_DESIGN_LANGUAGE} $(addsuffix .${COUCH_SUFFIX},${COUCH_DESIGN_FILES}) ${COUCH_DESIGN_VIEWS} ${COUCH_DESIGN_DIRECTORIES}

