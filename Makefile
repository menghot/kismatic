# Set the build version
ifeq ($(origin VERSION), undefined)
	VERSION := $(shell git describe --tags --always --dirty)
endif
# build date
ifeq ($(origin BUILD_DATE), undefined)
	BUILD_DATE := $(shell date -u)
endif

# Setup some useful vars
PKG = github.com/apprenda/kismatic
HOST_GOOS = $(shell go env GOOS)
HOST_GOARCH = $(shell go env GOARCH)

# Versions of external dependencies
GLIDE_VERSION = v0.11.1
ANSIBLE_VERSION = 2.3.0.0
PROVISIONER_VERSION = v1.2.0
KUBERANG_VERSION = v1.1.3
GO_VERSION = 1.8.0
KUBECTL_VERSION = v1.7.0-beta.2
HELM_VERSION = v2.4.2

ifeq ($(origin GLIDE_GOOS), undefined)
	GLIDE_GOOS := $(HOST_GOOS)
endif
ifeq ($(origin GOOS), undefined)
	GOOS := $(HOST_GOOS)
endif

build: bin/$(GOOS)/kismatic

build-inspector:
	@$(MAKE) GOOS=linux bin/inspector/linux/amd64/kismatic-inspector
	@$(MAKE) GOOS=darwin bin/inspector/darwin/amd64/kismatic-inspector

.PHONY: bin/$(GOOS)/kismatic
bin/$(GOOS)/kismatic: vendor
	go build -o $@                                                              \
	    -ldflags "-X main.version=$(VERSION) -X 'main.buildDate=$(BUILD_DATE)'" \
	    ./cmd/kismatic

.PHONY: bin/inspector/$(GOOS)/amd64/kismatic-inspector
bin/inspector/$(GOOS)/amd64/kismatic-inspector: vendor
	go build -o $@                                                               \
	    -ldflags "-X main.version=$(VERSION) -X 'main.buildDate=$(BUILD_DATE)'"  \
	    ./cmd/kismatic-inspector

clean:
	rm -rf bin
	rm -rf out
	rm -rf vendor
	rm -rf vendor-ansible/out
	rm -rf vendor-provision
	rm -rf integration/vendor
	rm -rf vendor-kuberang
	rm -rf vendor-helm

test: vendor
	go test -v ./cmd/... ./pkg/... $(TEST_OPTS)

integration-test: dist just-integration-test

vendor: tools/glide
	./tools/glide install

tools/glide:
	mkdir -p tools
	curl -L https://github.com/Masterminds/glide/releases/download/$(GLIDE_VERSION)/glide-$(GLIDE_VERSION)-$(GLIDE_GOOS)-$(HOST_GOARCH).tar.gz | tar -xz -C tools
	mv tools/$(GLIDE_GOOS)-$(HOST_GOARCH)/glide tools/glide
	rm -r tools/$(GLIDE_GOOS)-$(HOST_GOARCH)

vendor-ansible/out:
	mkdir -p vendor-ansible/out
	curl -L https://github.com/apprenda/vendor-ansible/releases/download/v$(ANSIBLE_VERSION)/ansible.tar.gz -o vendor-ansible/out/ansible.tar.gz
	tar -zxf vendor-ansible/out/ansible.tar.gz -C vendor-ansible/out
	rm vendor-ansible/out/ansible.tar.gz


vendor-provision/out:
	mkdir -p vendor-provision/out/
	curl -L https://github.com/apprenda/kismatic-provision/releases/download/$(PROVISIONER_VERSION)/provision-darwin-amd64 -o vendor-provision/out/provision-darwin-amd64
	curl -L https://github.com/apprenda/kismatic-provision/releases/download/$(PROVISIONER_VERSION)/provision-linux-amd64 -o vendor-provision/out/provision-linux-amd64
	chmod +x vendor-provision/out/*

vendor-kuberang/$(KUBERANG_VERSION):
	mkdir -p vendor-kuberang/$(KUBERANG_VERSION)
	curl https://kismatic-installer.s3-accelerate.amazonaws.com/kuberang/$(KUBERANG_VERSION)/kuberang-linux-amd64 -o vendor-kuberang/$(KUBERANG_VERSION)/kuberang-linux-amd64

vendor-kubectl/out:
	mkdir -p vendor-kubectl/out/
	curl -L https://storage.googleapis.com/kubernetes-release/release/$(KUBECTL_VERSION)/bin/$(GOOS)/amd64/kubectl -o vendor-kubectl/out/kubectl
	chmod +x vendor-kubectl/out/kubectl

vendor-helm/out:
	mkdir -p vendor-helm/out/
	curl -L https://storage.googleapis.com/kubernetes-helm/helm-$(HELM_VERSION)-$(GOOS)-amd64.tar.gz | tar zx -C vendor-helm
	cp vendor-helm/$(GOOS)-amd64/helm vendor-helm/out/helm
	rm -rf vendor-helm/$(GOOS)-amd64
	chmod +x vendor-helm/out/helm

dist: vendor-ansible/out vendor-provision/out vendor-kuberang/$(KUBERANG_VERSION) vendor-kubectl/out vendor-helm/out build build-inspector
	mkdir -p out
	cp bin/$(GOOS)/kismatic out
	mkdir -p out/ansible
	cp -r vendor-ansible/out/ansible/* out/ansible
	rm -rf out/ansible/playbooks
	cp -r ansible out/ansible/playbooks
	mkdir -p out/ansible/playbooks/inspector
	cp -r bin/inspector/* out/ansible/playbooks/inspector
	mkdir -p out/ansible/playbooks/kuberang/linux/amd64/
	cp vendor-kuberang/$(KUBERANG_VERSION)/kuberang-linux-amd64 out/ansible/playbooks/kuberang/linux/amd64/kuberang
	cp vendor-provision/out/provision-$(GOOS)-amd64 out/provision
	cp vendor-kubectl/out/kubectl out/kubectl
	cp vendor-helm/out/helm out/helm
	rm -f out/kismatic.tar.gz
	tar -czf kismatic.tar.gz -C out .
	mv kismatic.tar.gz out

integration/vendor: tools/glide
	go get github.com/onsi/ginkgo/ginkgo
	cd integration && ../tools/glide install

just-integration-test: integration/vendor
	ginkgo --skip "\[slow\]" -p $(GINKGO_OPTS) -v integration

slow-integration-test: integration/vendor
	ginkgo --focus "\[slow\]" -p $(GINKGO_OPTS) -v integration

serial-integration-test: integration/vendor
	ginkgo -v integration

focus-integration-test: integration/vendor
	ginkgo --focus $(FOCUS) -v integration

docs/generate-kismatic-cli:
	mkdir -p docs/kismatic-cli
	go run cmd/kismatic-docs/main.go
	cp docs/kismatic-cli/kismatic.md docs/kismatic-cli/README.md

version: FORCE
	@echo VERSION=$(VERSION)
	@echo GLIDE_VERSION=$(GLIDE_VERSION)
	@echo ANSIBLE_VERSION=$(ANSIBLE_VERSION)
	@echo PROVISIONER_VERSION=$(PROVISIONER_VERSION)

CIRCLE_ENDPOINT=
ifndef CIRCLE_CI_BRANCH
	CIRCLE_ENDPOINT=https://circleci.com/api/v1.1/project/github/apprenda/kismatic
else
	CIRCLE_ENDPOINT=https://circleci.com/api/v1.1/project/github/apprenda/kismatic/tree/$(CIRCLE_CI_BRANCH)
endif


trigger-ci-slow-tests:
	@echo Triggering build with slow tests
	curl -u $(CIRCLE_CI_TOKEN): -X POST --header "Content-Type: application/json"      \
		-d '{"build_parameters": {"RUN_SLOW_TESTS": "true"}}'                      \
		$(CIRCLE_ENDPOINT)

FORCE:
