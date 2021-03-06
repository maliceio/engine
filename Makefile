REPO=maliceio/engine
ORG=malice
NAME=engine
VERSION = $(shell cat VERSION)
MESSAGE?="New release $(VERSION)"
GITCOMMIT = $(shell git rev-parse --short HEAD 2> /dev/null || true)
DOCKER_BUILD_ARGS = --build-arg VERSION=$(VERSION) --build-arg GITCOMMIT=$(GITCOMMIT)


all: gotest build size test

.PHONY: dev
dev: ## Setup dev env
	@echo "===> Installing deps"
	go get -u github.com/jteeuwen/go-bindata/...
	go get -u github.com/LK4D4/vndr
	go get -u github.com/maliceio/malice/utils/tomlupdate
	vndr
	hack/validate/vendor

.PHONY: bindata
bindata: ## Embed binary data in malice engine
	@echo "===> Embedding Binary Data"
	rm registry/git/bindata.go || true
	go-bindata -pkg git -ignore="^.*.go|\\.DS_Store" registry/fixture/...
	mv bindata.go registry/git/bindata.go

.PHONY: vendor
vendor: vendor.conf ## check that vendor matches vendor.conf
	vndr 2> /dev/null
	hack/validate/check-git-diff vendor

.PHONY: build
build: ## Build docker image
	docker build $(DOCKER_BUILD_ARGS) -t $(ORG)/$(NAME):$(VERSION) .

.PHONY: size
size: tags ## Update docker image size in README.md
	sed -i.bu 's/docker%20image-.*-blue/docker%20image-$(shell docker images --format "{{.Size}}" $(ORG)/$(NAME):$(VERSION)| cut -d' ' -f1)-blue/' README.md

.PHONY: tags
tags: ## Show all docker image tags
	docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" $(ORG)/$(NAME)

.PHONY: tar
tar: ## Export tar of docker image
	docker save $(ORG)/$(NAME):$(VERSION) -o $(NAME).tar

.PHONY: gotest
gotest: ## Run go tests
	go test -v

.PHONY: test
test: ## Test malice engine
	docker-compose -f ./docker-compose.ci.yml up -d
	docker-compose -f docker-compose.ci.yml run httpie http://engine:3333/login username=admin password=admin

.PHONY: push
push: build ## Push docker image to docker registry
	@echo "===> Pushing $(ORG)/$(NAME):$(VERSION) to docker hub..."
	@docker push $(ORG)/$(NAME):$(VERSION)

.PHONY: daemon
daemon: stop ## Run malice engine daemon
	@echo "===> Starting malice engine daemon..."
	@docker run --init -d --name $(NAME) $(ORG)/$(NAME):$(VERSION)

.PHONY: run
run: stop ## Run docker container
	docker run --init -it --rm --name $(NAME) $(ORG)/$(NAME):$(VERSION)

.PHONY: ssh
ssh: ## SSH into docker image
	@docker run --init -it --rm --entrypoint=sh $(ORG)/$(NAME):$(VERSION)

.PHONY: stop
stop: ## Kill running malice-engine docker containers
	@docker rm -f $(NAME) || true

.PHONY: release
release: ## Create a new release from the VERSION
	@echo "===> Creating Release"
	@hack/make/release ${VERSION}
	@goreleaser --rm-dist

.PHONY: test_release
test_release: ## Test run goreleaser
	@echo "===> Testing Release"
	@goreleaser release --skip-publish --rm-dist --skip-validate

.PHONY: circle
circle: ci-size ## Get docker image size from CircleCI
	@sed -i.bu 's/docker%20image-.*-blue/docker%20image-$(shell cat .circleci/SIZE)-blue/' README.md
	@echo "===> Image size is: $(shell cat .circleci/SIZE)"

.PHONY: ci-build
ci-build:
	@echo "===> Getting CircleCI build number"
	@http https://circleci.com/api/v1.1/project/github/${REPO} | jq '.[0].build_num' > .circleci/build_num

.PHONY: ci-size
ci-size: ci-build
	@echo "===> Getting image build size from CircleCI"
	@http "$(shell http https://circleci.com/api/v1.1/project/github/${REPO}/$(shell cat .circleci/build_num)/artifacts circle-token==${CIRCLE_TOKEN} | jq '.[].url')" > .circleci/SIZE

.PHONY: clean
clean: ## Clean docker image and stop all running containers
	docker-clean stop
	docker rmi maliceengine_httpie || true
	docker rmi $(ORG)/$(NAME) || true
	docker rmi $(ORG)/$(NAME):$(VERSION) || true
	rm -rf dist || true

.PHONY: ci-validate
ci-validate:
	time make -B vendor

# Absolutely awesome: http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
