REPO_DIR := $(realpath $(dir $(lastword $(MAKEFILE_LIST))))
INSTALL_DIR := $(HOME)/.config/muxler

.PHONY: install

install:
	@test ! -e "$(INSTALL_DIR)" && test ! -L "$(INSTALL_DIR)" || { echo "$(INSTALL_DIR) already exists; refusing to replace it" >&2; exit 1; }
	@mkdir -p "$(HOME)/.config"
	ln -s "$(REPO_DIR)" "$(INSTALL_DIR)"
