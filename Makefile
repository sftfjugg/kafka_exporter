GO    := GO15VENDOREXPERIMENT=1 go
PROMU := $(GOPATH)/bin/promu
pkgs   = $(shell $(GO) list ./... | grep -v /vendor/)

PREFIX                  ?= $(shell pwd)
BIN_DIR                 ?= $(shell pwd)
DOCKER_IMAGE_NAME       ?= kafka-exporter
DOCKER_IMAGE_TAG        ?= $(subst /,-,$(shell git rev-parse --abbrev-ref HEAD))
TAG 					:= $(shell echo `if [ "$(TRAVIS_BRANCH)" = "master" ] || [ "$(TRAVIS_BRANCH)" = "" ] ; then echo "latest"; else echo $(TRAVIS_BRANCH) ; fi`)

PUSHTAG                 ?= type=registry,push=true
DOCKER_PLATFORMS        ?= linux/amd64,linux/s390x,linux/arm64,linux/ppc64le

all: format build test

style:
	@echo ">> checking code style"
	@! gofmt -d $(shell find . -path ./vendor -prune -o -name '*.go' -print) | grep '^'

test:
	@echo ">> running tests"
	@$(GO) test -short $(pkgs)

format:
	@echo ">> formatting code"
	@$(GO) fmt $(pkgs)

vet:
	@echo ">> vetting code"
	@$(GO) vet $(pkgs)

build: promu
	@echo ">> building binaries"
	@$(GO) mod vendor
	@$(PROMU) build --prefix $(PREFIX)


crossbuild: promu
	@echo ">> crossbuilding binaries"
	@$(PROMU) crossbuild --go=1.19

tarball: promu
	@echo ">> building release tarball"
	@$(PROMU) tarball --prefix $(PREFIX) $(BIN_DIR)

docker: build
	@echo ">> building docker image"
	@docker build -t "$(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG)" --build-arg BIN_DIR=. .

push: crossbuild
	@echo ">> building and pushing multi-arch docker images, $(DOCKER_USERNAME),$(DOCKER_IMAGE_NAME),$(TAG)"
	@docker login -u $(DOCKER_USERNAME) -p $(DOCKER_PASSWORD)
	@docker buildx create --use
	@docker buildx build -t "$(DOCKER_USERNAME)/$(DOCKER_IMAGE_NAME):$(TAG)" \
		--output "$(PUSHTAG)" \
		--platform "$(DOCKER_PLATFORMS)" \
		.

release: promu github-release
	@echo ">> pushing binary to github with ghr"
	@$(PROMU) crossbuild tarballs
	@$(PROMU) release .tarballs

promu:
	@GOOS=$(shell uname -s | tr A-Z a-z) \
		GOARCH=$(subst x86_64,amd64,$(patsubst i%86,386,$(shell uname -m))) \
		$(GO) install github.com/prometheus/promu@v0.13.0

github-release:
	@GOOS=$(shell uname -s | tr A-Z a-z) \
		GOARCH=$(subst x86_64,amd64,$(patsubst i%86,386,$(shell uname -m))) \
		$(GO) install github.com/github-release/github-release@v0.10.0 \
		$(GO) mod tidy

# Run go fmt against code
.PHONY: fmt
fmt:
	@find . -type f -name '*.go'| grep -v "/vendor/" | xargs gofmt -w -s

# Run mod tidy against code
.PHONY: tidy
tidy:
	@go mod tidy

# Run golang lint against code
.PHONY: lint
lint: golangci-lint
	@$(GOLANG_LINT) run \
      --timeout 30m \
      --disable-all \
      -E deadcode \
      -E unused \
      -E varcheck \
      -E ineffassign \
      -E goimports \
      -E gofmt \
      -E misspell \
      -E unparam \
      -E unconvert \
      -E govet \
      -E errcheck \
      -E structcheck

# find or download golangci-lint
# download golangci-lint if necessary
golangci-lint:
ifeq (, $(shell which golangci-lint))
	@GOOS=$(shell uname -s | tr A-Z a-z) \
    		GOARCH=$(subst x86_64,amd64,$(patsubst i%86,386,$(shell uname -m))) \
    		$(GO) install github.com/golangci/golangci-lint/cmd/golangci-lint@v1.48.0
GOLANG_LINT=$(shell go env GOPATH)/bin/golangci-lint
else
GOLANG_LINT=$(shell which golangci-lint)
endif

.PHONY: all style format build test vet tarball docker promu
