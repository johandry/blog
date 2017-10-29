#===============================================================================
# Author: Johandry Amador <johandry@gmail.com>
# Title:  Makefile to automate all the actions to my blog.
#
# Usage: make [<rule>]
#
# Basic rules:
# 		<none>		If no rule is specified will do the 'default' rule which is 'build'
#			build     Build a container to build and ship the application.
# 		clean 		Remove all the created images.
#     help			Display all the existing rules and description of what they do
#     version   Shows the application version.
# 		all 			Will build the application in every way and run it
#
# Description: This Makefile is to help me to execute all the possible or most
# common actions to my blog.
# Use 'make help' to view all the options or go to
# https://github.johandry/blog
#
# Report Issues or create Pull Requests in https://github.johandry/blog
#===============================================================================

## Variables (Modify their values if needed):
## -----------------------------------------------------------------------------

# SHELL need to be defined at the top of the Makefile. Do not change its value.
SHELL  				:= /bin/bash

# Output:
NO_COLOR 		 ?= false
ifeq ($(NO_COLOR),false)
ECHO 				 := echo -e
C_STD 				= $(shell $(ECHO) -e "\033[0m")
C_RED		 			= $(shell $(ECHO) -e "\033[91m")
C_GREEN 			= $(shell $(ECHO) -e "\033[92m")
C_YELLOW 			= $(shell $(ECHO) -e "\033[93m")
C_BLUE	 			= $(shell $(ECHO) -e "\033[94m")
I_CROSS 			= $(shell $(ECHO) -e "\xe2\x95\xb3")
I_CHECK 			= $(shell $(ECHO) -e "\xe2\x9c\x94")
I_BULLET 			= $(shell $(ECHO) -e "\xe2\x80\xa2")
else
ECHO 				 := echo
C_STD 				=
C_RED		 			=
C_GREEN 			=
C_YELLOW 			=
C_BLUE	 			=
I_CROSS 			= x
I_CHECK 			= .
I_BULLET 			= *
endif

## To find rules not in .PHONY:
# diff <(grep '^.PHONY:' Makefile | sed 's/.PHONY: //' | tr ' ' '\n' | sort) <(grep '^[^# ]*:' Makefile | grep -v '.PHONY:' | sed 's/:.*//' | sort) | grep '[>|<]'

.PHONY: default help all version test

## Default Rules:
## -----------------------------------------------------------------------------

# default is the rule that is executed when no rule is specified in make. By
# default make will do the rule 'build'
default: build

# all is to execute the entire process to create a Presto AMI and a Presto
# Cluster.
all: clean build build-all image run

# help to print all the commands and what they are for
help:
	@content=""; grep -v '.PHONY:' Makefile | grep -v '^## ' | grep '^[^# ]*:' -B 5 | grep -E '^#|^[^# ]*:' | \
	while read line; do if [[ $${line:0:1} == "#" ]]; \
		then l=$$($(ECHO) $$line | sed 's/^# /  /'); content="$${content}\n$$l"; \
		else header=$$($(ECHO) $$line | sed 's/^\([^ ]*\):.*/\1/'); [[ $${content} == "" ]] && content="\n  $(C_YELLOW)No help information for $${header}$(C_STD)"; $(ECHO) "$(C_BLUE)$${header}:$(C_STD)$$content\n"; content=""; fi; \
	done

# check if the current branch is dirty, meaning, there are pending changes to
# commit
dirt:
	@if [[ $$(git status -s) ]]; then \
		$(ECHO) "$(C_RED)The working directory is dirty. Please commit any pending changes.$(C_STD)"; exit 1; \
	fi

# remove the content in public/ folder. It can be regenerated with hugo
clean-public:
	@$(ECHO) "$(C_GREEN)Deleting old publication$(C_STD)"
	@$(RM) -r public; $(MKDIR) public
	@git worktree prune
	@$(RM) -r .git/worktrees/public/

# publish the new build to the gh-pages branch
build: dirt clean-public
	@$(ECHO) "$(C_GREEN)Checking out gh-pages branch into public$(C_STD)"
	@git worktree add -B gh-pages public origin/gh-pages
	@$(ECHO) "$(C_GREEN)Regenerating site$(C_STD)"
	@$(RM) -r public/*; hugo
	@$(ECHO) "$(C_GREEN)Updating gh-pages branch$(C_STD)"
	@cd public && git add --all && git commit -m "Publishing to gh-pages"
