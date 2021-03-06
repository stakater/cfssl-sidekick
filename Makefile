NAME=cfssl-sidekick
AUTHOR=ukhomeofficedigital
AUTHOR_EMAIL=gambol99@gmail.com
REGISTRY=quay.io
ROOT_DIR=${PWD}
HARDWARE=$(shell uname -m)
GIT_SHA=$(shell git --no-pager describe --always --dirty)
BUILD_TIME=$(shell date -u '+%Y-%m-%d_%I:%M:%S%p')
VERSION ?= $(shell awk '/Version.*=/ { print $$3 }' doc.go | sed 's/"//g')
DEPS=$(shell go list -f '{{range .TestImports}}{{.}} {{end}}' ./...)
PACKAGES=$(shell go list ./...)
LFLAGS ?= -X main.GitSHA=${GIT_SHA}
VETARGS ?= -asmdecl -atomic -bool -buildtags -copylocks -methods -nilfunc -printf -rangeloops -shift -structtags -unsafeptr

.PHONY: test authors changelog build docker static release lint cover vet glide-install

default: build

golang:
	@echo "--> Go Version"
	@go version

build:
	@echo "--> Compiling the project"
	mkdir -p bin
	go build -ldflags "${LFLAGS}" -o bin/${NAME}

static: golang deps
	@echo "--> Compiling the static binary"
	mkdir -p bin
	CGO_ENABLED=0 GOOS=linux go build -a -tags netgo -ldflags "-w ${LFLAGS}" -o bin/${NAME}

docker: static
	@echo "--> Building the docker image"
	docker build -t ${REGISTRY}/${AUTHOR}/${NAME}:${VERSION} .

docker-release:
	@echo "--> Building a release image"
	@make static
	@make docker
	@docker push ${REGISTRY}/${AUTHOR}/${NAME}:${VERSION}

release: static
	mkdir -p release
	gzip -c bin/${NAME} > release/${NAME}_${VERSION}_linux_${HARDWARE}.gz
	rm -f release/${NAME}

clean:
	rm -rf ./bin 2>/dev/null
	rm -rf ./release 2>/dev/null

authors:
	@echo "--> Updating the AUTHORS"
	git log --format='%aN <%aE>' | sort -u > AUTHORS

deps:
	@echo "--> Installing build dependencies"

vet:
	@echo "--> Running go vet $(VETARGS) ."
	@go tool vet 2>/dev/null ; if [ $$? -eq 3 ]; then \
		go get golang.org/x/tools/cmd/vet; \
	fi
	@go tool vet $(VETARGS) *.go

lint:
	@echo "--> Running golint"
	@which golint 2>/dev/null ; if [ $$? -eq 1 ]; then \
		go get -u github.com/golang/lint/golint; \
	fi
	@golint .

gofmt:
	@echo "--> Running gofmt check"
	@gofmt -s -l *.go \
	    | grep -q \.go ; if [ $$? -eq 0 ]; then \
            echo "You need to run the make format, we have file unformatted"; \
            gofmt -s -l *.go; \
            exit 1; \
	    fi

format:
	@echo "--> Running go fmt"
	@gofmt -s -w *.go

bench:
	@echo "--> Running go bench"
	@go test -v -bench=.

coverage:
	@echo "--> Running go coverage"
	@go test -coverprofile cover.out
	@go tool cover -html=cover.out -o cover.html

cover:
	@echo "--> Running go cover"
	@go test --cover

glide-install:
	@echo "--> Installing dependencies"
	@go get github.com/Masterminds/glide
	@glide install

test: deps
	@echo "--> Running the tests"
	@if [ ! -d "vendor" ]; then \
    make glide-install; \
  fi
	@go test -v
	@$(MAKE) gofmt
	@$(MAKE) vet
	@$(MAKE) cover

changelog: release
	git log $(shell git tag | tail -n1)..HEAD --no-merges --format=%B > changelog
