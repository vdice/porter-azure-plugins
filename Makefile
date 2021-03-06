PLUGIN = azure
PKG = github.com/deislabs/porter-$(PLUGIN)-plugins
SHELL = bash

PORTER_HOME ?= $(HOME)/.porter

COMMIT ?= $(shell git rev-parse --short HEAD)
VERSION ?= $(shell git describe --tags 2> /dev/null || echo v0)
PERMALINK ?= $(shell git describe --tags --exact-match &> /dev/null && echo latest || echo canary)

LDFLAGS = -w -X $(PKG)/pkg.Version=$(VERSION) -X $(PKG)/pkg.Commit=$(COMMIT)
XBUILD = CGO_ENABLED=0 go build -a -tags netgo -ldflags '$(LDFLAGS)'
BINDIR = bin/plugins

CLIENT_PLATFORM ?= $(shell go env GOOS)
CLIENT_ARCH ?= $(shell go env GOARCH)
SUPPORTED_PLATFORMS = linux darwin windows
SUPPORTED_ARCHES = amd64

ifeq ($(CLIENT_PLATFORM),windows)
FILE_EXT=.exe
else
FILE_EXT=
endif

.PHONY: build
build:
	mkdir -p $(BINDIR)
	go build -ldflags '$(LDFLAGS)' -o $(BINDIR)/$(PLUGIN)$(FILE_EXT) ./cmd/$(PLUGIN)

xbuild-all:
	$(foreach OS, $(SUPPORTED_PLATFORMS), \
		$(foreach ARCH, $(SUPPORTED_ARCHES), \
				$(MAKE) $(MAKE_OPTS) CLIENT_PLATFORM=$(OS) CLIENT_ARCH=$(ARCH) PLUGIN=$(PLUGIN) xbuild; \
		))

xbuild: $(BINDIR)/$(VERSION)/$(PLUGIN)-$(CLIENT_PLATFORM)-$(CLIENT_ARCH)$(FILE_EXT)
$(BINDIR)/$(VERSION)/$(PLUGIN)-$(CLIENT_PLATFORM)-$(CLIENT_ARCH)$(FILE_EXT):
	mkdir -p $(dir $@)
	GOOS=$(CLIENT_PLATFORM) GOARCH=$(CLIENT_ARCH) $(XBUILD) -o $@ ./cmd/$(PLUGIN)

verify: verify-vendor

verify-vendor: dep
	dep check

HAS_DEP := $(shell command -v dep)
dep:
ifndef HAS_DEP
	curl https://raw.githubusercontent.com/golang/dep/master/install.sh | sh
endif
	dep version

test: test-unit
	$(BINDIR)/$(PLUGIN)$(FILE_EXT) version

test-unit: build
	go test ./...

publish: bin/porter$(FILE_EXT)
	# AZURE_STORAGE_CONNECTION_STRING will be used for auth in the following commands
	if [[ "$(PERMALINK)" == "latest" ]]; then \
		az storage blob upload-batch -d porter/plugins/$(PLUGIN)/$(VERSION) -s $(BINDIR)/$(VERSION); \
		az storage blob upload-batch -d porter/plugins/$(PLUGIN)/$(PERMALINK) -s $(BINDIR)/$(VERSION); \
	else \
		mv $(BINDIR)/$(VERSION) $(BINDIR)/$(PERMALINK); \
		az storage blob upload-batch -d porter/plugins/$(PLUGIN)/$(PERMALINK) -s $(BINDIR)/$(PERMALINK); \
	fi

	# Generate the plugin feed
	#az storage blob download -c porter -n plugins/atom.xml -f bin/plugins/atom.xml
	bin/porter plugins feed generate -d bin/plugins -f bin/plugins/atom.xml -t build/atom-template.xml
	#az storage blob upload -c porter -n plugins/atom.xml -f bin/atom.xml

bin/porter$(FILE_EXT):
	curl -fsSLo bin/porter$(FILE_EXT) https://cdn.deislabs.io/porter/canary/porter-$(CLIENT_PLATFORM)-$(CLIENT_ARCH)$(FILE_EXT)
	chmod +x bin/porter$(FILE_EXT)

install:
	mkdir -p $(PORTER_HOME)/plugins
	install $(BINDIR)/$(PLUGIN)$(FILE_EXT) $(PORTER_HOME)/plugins/$(PLUGIN)$(FILE_EXT)

clean:
	-rm -fr bin/
