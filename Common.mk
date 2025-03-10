# Disable built-in rules and variables
MAKEFLAGS+=--no-builtin-rules --warn-undefined-variables
SHELL=bash
.SHELLFLAGS:=-eu -o pipefail -c
.SUFFIXES:

RELEASE_ENVIRONMENT?=development

GIT_HASH=$(shell git -C $(BASE_DIRECTORY) rev-parse HEAD)

COMPONENT?=$(REPO_OWNER)/$(REPO)
MAKE_ROOT=$(BASE_DIRECTORY)/projects/$(COMPONENT)
PROJECT_PATH?=$(subst $(BASE_DIRECTORY)/,,$(MAKE_ROOT))
BUILD_LIB=${BASE_DIRECTORY}/build/lib
OUTPUT_BIN_DIR?=$(OUTPUT_DIR)/bin/$(REPO)

#################### AWS ###########################
AWS_REGION?=us-west-2
AWS_ACCOUNT_ID?=$(shell aws sts get-caller-identity --query Account --output text)
ARTIFACTS_BUCKET?=s3://my-s3-bucket
IMAGE_REPO?=$(if $(AWS_ACCOUNT_ID),$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com,localhost:5000)
####################################################

#################### LATEST TAG ####################
# codebuild
BRANCH_NAME?=main
# prow
PULL_BASE_REF?=main
LATEST=latest
ifneq ($(BRANCH_NAME),main)
	LATEST=$(BRANCH_NAME)
endif
ifneq ($(PULL_BASE_REF),main)
	LATEST=$(PULL_BASE_REF)
endif
####################################################

#################### CODEBUILD #####################
CODEBUILD_CI?=false
CI?=false
CLONE_URL=$(call GET_CLONE_URL,$(REPO_OWNER),$(REPO))
#HELM_CLONE_URL=$(call GET_CLONE_URL,$(HELM_SOURCE_OWNER),$(HELM_SOURCE_REPOSITORY))
HELM_CLONE_URL=https://github.com/$(HELM_SOURCE_OWNER)/$(HELM_SOURCE_REPOSITORY).git
ifeq ($(CODEBUILD_CI),true)
	ARTIFACTS_PATH?=$(CODEBUILD_SRC_DIR)/$(PROJECT_PATH)/$(CODEBUILD_BUILD_NUMBER)-$(CODEBUILD_RESOLVED_SOURCE_VERSION)/artifacts
	UPLOAD_DRY_RUN=false
	BUILD_IDENTIFIER=$(CODEBUILD_BUILD_NUMBER)
else
	ARTIFACTS_PATH?=$(MAKE_ROOT)/_output/tar
	UPLOAD_DRY_RUN=true
	ifeq ($(CI),true)
		BUILD_IDENTIFIER=$(PROW_JOB_ID)
	else
		BUILD_IDENTIFIER=$(shell date "+%F-%s")
	endif
endif
####################################################

#################### GIT ###########################
GIT_CHECKOUT_TARGET?=$(REPO)/eks-anywhere-checkout-$(GIT_TAG)
GIT_PATCH_TARGET?=$(REPO)/eks-anywhere-patched
GO_MOD_DOWNLOAD_TARGETS?=$(REPO)/eks-anywhere-go-mod-download
REPO_NO_CLONE?=false
PATCHES_DIR=$(or $(wildcard $(PROJECT_ROOT)/patches),$(wildcard $(MAKE_ROOT)/patches))
####################################################

#################### RELEASE BRANCHES ##############
HAS_RELEASE_BRANCHES?=false
RELEASE_BRANCH?=
SUPPORTED_K8S_VERSIONS=$(shell cat $(BASE_DIRECTORY)/release/SUPPORTED_RELEASE_BRANCHES)
BINARIES_ARE_RELEASE_BRANCHED?=true
IS_RELEASE_BRANCH_BUILD=$(filter true,$(HAS_RELEASE_BRANCHES))
IS_UNRELEASE_BRANCH_TARGET=$(and $(filter false,$(BINARIES_ARE_RELEASE_BRANCHED)),$(filter binaries attribution checksums,$(MAKECMDGOALS)))
TARGETS_ALLOWED_WITH_NO_RELEASE_BRANCH?=build release clean help
ifneq ($(and $(IS_RELEASE_BRANCH_BUILD),$(or $(RELEASE_BRANCH),$(IS_UNRELEASE_BRANCH_TARGET))),)
	RELEASE_BRANCH_SUFFIX=$(if $(filter true,$(BINARIES_ARE_RELEASE_BRANCHED)),/$(RELEASE_BRANCH),)

	ARTIFACTS_PATH:=$(ARTIFACTS_PATH)$(RELEASE_BRANCH_SUFFIX)
	OUTPUT_DIR?=_output$(RELEASE_BRANCH_SUFFIX)
	PROJECT_ROOT?=$(MAKE_ROOT)$(RELEASE_BRANCH_SUFFIX)
	ARTIFACTS_UPLOAD_PATH?=$(PROJECT_PATH)$(RELEASE_BRANCH_SUFFIX)

	# Deps are always released branched
	BINARY_DEPS_DIR?=_output/$(RELEASE_BRANCH)/dependencies

	# include release branch info in latest tag
	LATEST_TAG?=$(GIT_TAG)-$(LATEST)
else ifneq ($(and $(IS_RELEASE_BRANCH_BUILD), $(filter-out $(TARGETS_ALLOWED_WITH_NO_RELEASE_BRANCH),$(MAKECMDGOALS))),)
	# if project has release branches and not calling one of the above targets
$(error When running targets for this project other than `build` or `release` a `RELEASE_BRANCH` is required)
else ifneq ($(IS_RELEASE_BRANCH_BUILD),)
	# project has release branches and one was not specified, trigger target for all
	BUILD_TARGETS=build/release-branches/all
	RELEASE_TARGETS=release/release-branches/all

	# avoid warnings when trying to read GIT_TAG file which wont exist when no release_branch is given
	GIT_TAG=non-existent
else
	PROJECT_ROOT?=$(MAKE_ROOT)
	ARTIFACTS_UPLOAD_PATH?=$(PROJECT_PATH)
	OUTPUT_DIR?=_output
	LATEST_TAG?=$(LATEST)
endif

####################################################

#################### BASE IMAGES ###################
BASE_IMAGE_REPO?=public.ecr.aws/eks-distro-build-tooling
BASE_IMAGE_NAME?=eks-distro-base
BASE_IMAGE_TAG_FILE?=$(BASE_DIRECTORY)/$(shell echo $(BASE_IMAGE_NAME) | tr '[:lower:]' '[:upper:]' | tr '-' '_')_TAG_FILE
BASE_IMAGE_TAG?=$(shell cat $(BASE_IMAGE_TAG_FILE))
BASE_IMAGE?=$(BASE_IMAGE_REPO)/$(BASE_IMAGE_NAME):$(BASE_IMAGE_TAG)
BUILDER_IMAGE?=$(BASE_IMAGE_REPO)/$(BASE_IMAGE_NAME)-builder:$(BASE_IMAGE_TAG)
####################################################

#################### IMAGES ########################
IMAGE_COMPONENT?=$(COMPONENT)
IMAGE_OUTPUT_DIR?=/tmp
IMAGE_OUTPUT_NAME?=$(IMAGE_NAME)
IMAGE_TARGET?=

IMAGE_NAMES?=$(REPO)

# This tag is overwritten in the prow job to point to the upstream git tag and this repo's commit hash
IMAGE_TAG?=$(GIT_TAG)-$(GIT_HASH)
# For projects with multiple containers this is defined to override the default
# ex: CLUSTER_API_CONTROLLER_IMAGE_COMPONENT
IMAGE_COMPONENT_VARIABLE=$(shell echo '$(IMAGE_NAME)' | tr '[:lower:]' '[:upper:]' | tr '-' '_' )_IMAGE_COMPONENT
IMAGE=$(IMAGE_REPO)/$(if $(value $(IMAGE_COMPONENT_VARIABLE)),$(value $(IMAGE_COMPONENT_VARIABLE)),$(IMAGE_COMPONENT)):$(IMAGE_TAG)
LATEST_IMAGE=$(IMAGE:$(lastword $(subst :, ,$(IMAGE)))=$(LATEST_TAG))

IMAGE_USERADD_USER_ID?=1000
IMAGE_USERADD_USER_NAME?=

# Branch builds should look at the current branch latest image for cache as well as main branch latest for cache to cover the cases
# where its the first build from a new release branch
IMAGE_IMPORT_CACHE?=type=registry,ref=$(LATEST_IMAGE) type=registry,ref=$(subst $(LATEST),latest,$(LATEST_IMAGE))

BUILD_OCI_TARS?=false

LOCAL_IMAGE_TARGETS=$(foreach image,$(IMAGE_NAMES),$(image)/images/amd64) $(if $(filter true,$(HAS_HELM_CHART)),helm/build,) 
IMAGE_TARGETS=$(foreach image,$(IMAGE_NAMES),$(if $(filter true,$(BUILD_OCI_TARS)),$(call IMAGE_TARGETS_FOR_NAME,$(image)),$(image)/images/push)) $(if $(filter true,$(HAS_HELM_CHART)),helm/push,) 
####################################################

#################### HELM ##########################
HAS_HELM_CHART?=false
HELM_SOURCE_OWNER?=$(REPO_OWNER)
HELM_SOURCE_REPOSITORY?=$(REPO)
HELM_GIT_TAG?=$(GIT_TAG)
HELM_DIRECTORY?=.
HELM_DESTINATION_REPOSITORY?=$(IMAGE_COMPONENT)
HELM_IMAGE_LIST?=
HELM_ADDITIONAL_KEY_VALUES?=
HELM_GIT_CHECKOUT_TARGET?=$(HELM_SOURCE_REPOSITORY)/eks-anywhere-checkout-$(HELM_GIT_TAG)
HELM_GIT_PATCH_TARGET?=$(HELM_SOURCE_REPOSITORY)/eks-anywhere-helm-patched
####################################################

#################### BINARIES ######################
BINARY_PLATFORMS?=linux/amd64 linux/arm64
SIMPLE_CREATE_BINARIES?=true

BINARY_TARGETS?=$(call BINARY_TARGETS_FROM_FILES_PLATFORMS, $(BINARY_TARGET_FILES), $(BINARY_PLATFORMS))
BINARY_TARGET_FILES?=
SOURCE_PATTERNS?=.

#### CGO ############
CGO_CREATE_BINARIES?=false
CGO_SOURCE=$(OUTPUT_DIR)/source
IS_ON_BUILDER_BASE=$(shell if [ -f /buildkit.sh ]; then echo true; fi;)
BUILDER_PLATFORM=$(shell echo $$(go env GOHOSTOS)/$$(go env GOHOSTARCH))
needs-cgo-builder=$(and $(if $(filter true,$(CGO_CREATE_BINARIES)),true,),$(if $(filter-out $(1),$(BUILDER_PLATFORM)),true,))
######################

#### BUILD FLAGS ####
ifeq ($(CGO_CREATE_BINARIES),true)
	CGO_ENABLED=1
	GO_LDFLAGS?=-s -w -buildid= $(EXTRA_GO_LDFLAGS)
	CGO_LDFLAGS?=-Wl,--build-id=none
	EXTRA_GOBUILD_FLAGS?=-gcflags=-trimpath=$(MAKE_ROOT) -asmflags=-trimpath=$(MAKE_ROOT)
else
	CGO_ENABLED=0
	GO_LDFLAGS?=-s -w -buildid= -extldflags -static $(EXTRA_GO_LDFLAGS)
	CGO_LDFLAGS?=
	EXTRA_GOBUILD_FLAGS?=
endif
EXTRA_GO_LDFLAGS?=
GOBUILD_COMMAND?=build
######################

#### HELPERS ########
# https://riptutorial.com/makefile/example/23643/zipping-lists
# Used to generate binary targets based on BINARY_TARGET_FILES
list-rem = $(wordlist 2,$(words $1),$1)

pairmap = $(and $(strip $2),$(strip $3),$(call \
    $1,$(firstword $2),$(firstword $3)) $(call \
    pairmap,$1,$(call list-rem,$2),$(call list-rem,$3)))
######################

####################################################

############### BINARIES DEPS ######################
BINARY_DEPS_DIR?=$(OUTPUT_DIR)/dependencies
FETCH_BINARIES_TARGETS?=
####################################################

#################### LICENSES ######################
LICENSE_PACKAGE_FILTER?=$(SOURCE_PATTERNS)
REPO_SUBPATH?=
HAS_LICENSES?=true
ATTRIBUTION_TARGETS?=$(if $(wildcard $(RELEASE_BRANCH)/ATTRIBUTION.txt),$(RELEASE_BRANCH)/ATTRIBUTION.txt,ATTRIBUTION.txt)
GATHER_LICENSES_TARGETS?=$(OUTPUT_DIR)/attribution/go-license.csv
LICENSES_OUTPUT_DIR?=$(OUTPUT_DIR)
LICENSES_TARGETS_FOR_PREREQ=$(if $(filter true,$(HAS_LICENSES)),$(GATHER_LICENSES_TARGETS) $(OUTPUT_DIR)/ATTRIBUTION.txt,)
####################################################

#################### TARBALLS ######################
HAS_S3_ARTIFACTS?=false

SIMPLE_CREATE_TARBALLS?=true
TAR_FILE_PREFIX?=$(REPO)
FAKE_ARM_BINARIES_FOR_VALIDATION?=$(if $(filter linux/arm64,$(BINARY_PLATFORMS)),false,true)
FAKE_ARM_IMAGES_FOR_VALIDATION?=false
####################################################

#################### OTHER #########################
KUSTOMIZE_TARGET=$(OUTPUT_DIR)/kustomize
GIT_DEPS_DIR?=$(OUTPUT_DIR)/gitdependencies
####################################################

#################### TARGETS FOR OVERRIDING ########
BUILD_TARGETS?=validate-checksums $(if $(IMAGE_NAMES),local-images,) attribution $(if $(filter true,$(HAS_S3_ARTIFACTS)),upload-artifacts,) attribution-pr
RELEASE_TARGETS?=validate-checksums $(if $(IMAGE_NAMES),images,) $(if $(filter true,$(HAS_S3_ARTIFACTS)),upload-artifacts,)
####################################################

define BUILDCTL
	$(BUILD_LIB)/buildkit.sh \
		build \
		--frontend dockerfile.v0 \
		--opt platform=$(IMAGE_PLATFORMS) \
		--opt build-arg:BASE_IMAGE=$(BASE_IMAGE) \
		--opt build-arg:BUILDER_IMAGE=$(BUILDER_IMAGE) \
		--opt build-arg:RELEASE_BRANCH=$(RELEASE_BRANCH) \
		$(foreach BUILD_ARG,$(IMAGE_BUILD_ARGS),--opt build-arg:$(BUILD_ARG)=$($(BUILD_ARG))) \
		--progress plain \
		--local dockerfile=$(DOCKERFILE_FOLDER) \
		--local context=$(IMAGE_CONTEXT_DIR) \
		--opt target=$(IMAGE_TARGET) \
		--output type=$(IMAGE_OUTPUT_TYPE),oci-mediatypes=true,\"name=$(IMAGE),$(LATEST_IMAGE)\",$(IMAGE_OUTPUT) \
		$(if $(filter push=true,$(IMAGE_OUTPUT)),--export-cache type=inline,) \
		$(foreach IMPORT_CACHE,$(IMAGE_IMPORT_CACHE),--import-cache $(IMPORT_CACHE))

endef 

define WRITE_LOCAL_IMAGE_TAG
	echo $(IMAGE_TAG) > $(IMAGE_OUTPUT_DIR)/$(IMAGE_OUTPUT_NAME).docker_tag
	echo $(IMAGE) > $(IMAGE_OUTPUT_DIR)/$(IMAGE_OUTPUT_NAME).docker_image_name	
endef

define IMAGE_TARGETS_FOR_NAME
	$(addsuffix /images/push, $(1)) $(addsuffix /images/amd64, $(1)) $(addsuffix /images/arm64, $(1))
endef

define FULL_FETCH_BINARIES_TARGETS
	$(addprefix $(BINARY_DEPS_DIR)/linux-amd64/, $(1)) $(addprefix $(BINARY_DEPS_DIR)/linux-arm64/, $(1))
endef

define BINARY_TARGETS_FROM_FILES_PLATFORMS
	$(foreach platform, $(2), $(foreach target, $(1), \
		$(OUTPUT_BIN_DIR)/$(subst /,-,$(platform))/$(if $(findstring windows,$(platform)),$(target).exe,$(target))))
endef

define BINARY_TARGET_BODY_ALL_PLATFORMS
	$(eval $(foreach platform, $(BINARY_PLATFORMS), \
		$(call $(if $(call needs-cgo-builder,$(platform)),CGO_BINARY_TARGET_BODY,BINARY_TARGET_BODY),$(platform),$(if $(findstring windows,$(platform)),$(1).exe,$(1)),$(2))))
endef

define BINARY_TARGET_BODY
	$(OUTPUT_BIN_DIR)/$(subst /,-,$(1))/$(2): $(GO_MOD_DOWNLOAD_TARGETS)
		$(BASE_DIRECTORY)/build/lib/simple_create_binaries.sh $$(MAKE_ROOT) \
			$$(MAKE_ROOT)/$(OUTPUT_BIN_DIR)/$(subst /,-,$(1))/$(2) $$(REPO) $$(GOLANG_VERSION) $(1) $(3) \
			"$$(GOBUILD_COMMAND)" "$$(EXTRA_GOBUILD_FLAGS)" "$$(GO_LDFLAGS)" $$(CGO_ENABLED) "$$(CGO_LDFLAGS)" $$(REPO_SUBPATH)

endef

# This "function" is used to construt the git clone URL for projects.
# Indenting the block results in the URL getting prefixed with a
# space, hence no indentation below.
define GET_CLONE_URL
$(shell source $(BUILD_LIB)/common.sh && build::common::get_clone_url $(1) $(2) $(AWS_REGION) $(CODEBUILD_CI))
endef

# Indenting the block results in the URL getting prefixed with a
# space, hence no indentation below.
define TO_UPPER
$(shell echo '$(1)' | tr '[:lower:]' '[:upper:]')
endef

# to avoid dealing with cross compling issues using a buildctl
# multi-stage build to build the binaries for both amd64 and arm64
# licenses and attribution are also run from the builder image since
# the deps are all needed
define CGO_BINARY_TARGET_BODY
	$(OUTPUT_BIN_DIR)/$(subst /,-,$(1))/$(2): $(GO_MOD_DOWNLOAD_TARGETS)
		@mkdir -p $(CGO_SOURCE)/eks-anywhere-build-tooling/
		rsync -rm  --exclude='.git/***' \
			--exclude='***/_output/***' --exclude='projects/$(COMPONENT)/$(REPO)/***' \
			--include='projects/$(COMPONENT)/***' --include='*/' --exclude='projects/***'  \
			$(BASE_DIRECTORY)/ $(CGO_SOURCE)/eks-anywhere-build-tooling/
		@mkdir -p $(OUTPUT_BIN_DIR)/$(subst /,-,$(1))
		# Need so git properly finds the root of the repo
		@mkdir -p $(CGO_SOURCE)/eks-anywhere-build-tooling/.git/{refs,objects}
		@cp $(BASE_DIRECTORY)/.git/HEAD $(CGO_SOURCE)/eks-anywhere-build-tooling/.git
		$(MAKE) binary-builder/cgo/$(1:linux/%=%) \
			IMAGE_OUTPUT=dest=$(OUTPUT_BIN_DIR)/$(subst /,-,$(1)) CGO_TARGET=$$@ IMAGE_BUILD_ARGS="GOPROXY COMPONENT CGO_TARGET"

endef

# intentionall no tab/space since it would come out in the result of calling this func
define TO_UPPER
$(shell echo '$(1)' | tr '[:lower:]' '[:upper:]')
endef

#### Source repo + binary Targets
ifneq ($(REPO_NO_CLONE),true)
$(REPO):
	git clone $(CLONE_URL) $(REPO)
endif

$(GIT_CHECKOUT_TARGET): | $(REPO)
	@rm -f $(REPO)/eks-anywhere-*
	(cd $(REPO) && $(BASE_DIRECTORY)/build/lib/wait_for_tag.sh $(GIT_TAG))
	git -C $(REPO) checkout -f $(GIT_TAG)
	touch $@

$(GIT_PATCH_TARGET): $(GIT_CHECKOUT_TARGET)
	git -C $(REPO) config user.email prow@amazonaws.com
	git -C $(REPO) config user.name "Prow Bot"
	git -C $(REPO) am --committer-date-is-author-date $(PATCHES_DIR)/*
	@touch $@

%eks-anywhere-go-mod-download: $(if $(PATCHES_DIR),$(GIT_PATCH_TARGET),$(GIT_CHECKOUT_TARGET))
	$(BASE_DIRECTORY)/build/lib/go_mod_download.sh $(MAKE_ROOT) $(REPO) $(GIT_TAG) $(GOLANG_VERSION) $(REPO_SUBPATH)
	@touch $@

ifneq ($(REPO),$(HELM_SOURCE_REPOSITORY))
$(HELM_SOURCE_REPOSITORY):
	git clone $(HELM_CLONE_URL) $(HELM_SOURCE_REPOSITORY)

$(HELM_GIT_CHECKOUT_TARGET): | $(HELM_SOURCE_REPOSITORY)
	@echo rm -f $(HELM_SOURCE_REPOSITORY)/eks-anywhere-*
	(cd $(HELM_SOURCE_REPOSITORY) && $(BASE_DIRECTORY)/build/lib/wait_for_tag.sh $(HELM_GIT_TAG))
	git -C $(HELM_SOURCE_REPOSITORY) checkout -f $(HELM_GIT_TAG)
	touch $@
endif

$(HELM_GIT_PATCH_TARGET): $(HELM_GIT_CHECKOUT_TARGET)
	git -C $(HELM_SOURCE_REPOSITORY) config user.email prow@amazonaws.com
	git -C $(HELM_SOURCE_REPOSITORY) config user.name "Prow Bot"
	git -C $(HELM_SOURCE_REPOSITORY) am --committer-date-is-author-date $(wildcard $(MAKE_ROOT)/helm/patches)/*
	@touch $@

ifeq ($(SIMPLE_CREATE_BINARIES),true)
$(call pairmap,BINARY_TARGET_BODY_ALL_PLATFORMS,$(BINARY_TARGET_FILES),$(SOURCE_PATTERNS))
endif

.PHONY: binaries
binaries: $(BINARY_TARGETS)

$(KUSTOMIZE_TARGET):
	@mkdir -p $(OUTPUT_DIR)
	curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash -s -- $(OUTPUT_DIR)

.PHONY: clone-repo
clone-rpeo: $(REPO)

.PHONY: checkout-repo
checkout-repo: $(GIT_CHECKOUT_TARGET)

.PHONY: patch-repo
patch-repo: $(GIT_PATCH_TARGET)

## File/Folder Targets

$(OUTPUT_DIR)/images/%:
	@mkdir -p $(@D)

$(OUTPUT_DIR)/ATTRIBUTION.txt:
	@mkdir -p $(OUTPUT_DIR)
	@cp $(ATTRIBUTION_TARGETS) $(OUTPUT_DIR)


## License Targets

## Gather licenses for project based on dependencies in REPO.
$(GATHER_LICENSES_TARGETS): $(GO_MOD_DOWNLOAD_TARGETS)
	$(BASE_DIRECTORY)/build/lib/gather_licenses.sh $(REPO) $(MAKE_ROOT)/$(LICENSES_OUTPUT_DIR) "$(LICENSE_PACKAGE_FILTER)" $(REPO_SUBPATH)

# Match all variables of ATTRIBUTION.txt `ATTRIBUTION.txt` `{RELEASE_BRANCH}/ATTRIBUTION.txt` `CAPD_ATTRIBUTION.txt`
%TTRIBUTION.txt: $(GATHER_LICENSES_TARGETS)
	$(BASE_DIRECTORY)/build/lib/create_attribution.sh $(MAKE_ROOT) $(GOLANG_VERSION) $(MAKE_ROOT)/$(LICENSES_OUTPUT_DIR) $(@F) $(RELEASE_BRANCH)

.PHONY: gather-licenses
gather-licenses: $(GATHER_LICENSES_TARGETS)

.PHONY: attribution
attribution: $(and $(filter true,$(HAS_LICENSES)),$(ATTRIBUTION_TARGETS))

.PHONY: attribution-pr
attribution-pr:
	$(BASE_DIRECTORY)/build/update-attribution-files/create_pr.sh

#### Tarball Targets

.PHONY: tarballs
tarballs: $(LICENSES_TARGETS_FOR_PREREQ)
ifeq ($(SIMPLE_CREATE_TARBALLS),true)
	$(BASE_DIRECTORY)/build/lib/simple_create_tarballs.sh $(TAR_FILE_PREFIX) $(MAKE_ROOT)/$(OUTPUT_DIR) $(MAKE_ROOT)/$(OUTPUT_BIN_DIR) $(GIT_TAG) "$(BINARY_PLATFORMS)" $(ARTIFACTS_PATH) $(GIT_HASH)
endif

.PHONY: upload-artifacts
upload-artifacts: s3-artifacts
	$(BASE_DIRECTORY)/build/lib/upload_artifacts.sh $(ARTIFACTS_PATH) $(ARTIFACTS_BUCKET) $(ARTIFACTS_UPLOAD_PATH) $(BUILD_IDENTIFIER) $(GIT_HASH) $(LATEST) $(UPLOAD_DRY_RUN)

.PHONY: s3-artifacts
s3-artifacts: tarballs
	$(BUILD_LIB)/create_release_checksums.sh $(ARTIFACTS_PATH)
	$(BUILD_LIB)/validate_artifacts.sh $(MAKE_ROOT) $(ARTIFACTS_PATH) $(GIT_TAG) $(FAKE_ARM_BINARIES_FOR_VALIDATION) $(IMAGE_FORMAT)


### Checksum Targets
	
.PHONY: checksums
checksums: $(BINARY_TARGETS)
ifneq ($(strip $(BINARY_TARGETS)),)
	$(BASE_DIRECTORY)/build/lib/update_checksums.sh $(MAKE_ROOT) $(PROJECT_ROOT) $(MAKE_ROOT)/$(OUTPUT_BIN_DIR)
endif

.PHONY: validate-checksums
validate-checksums: $(BINARY_TARGETS)
ifneq ($(strip $(BINARY_TARGETS)),)
	$(BASE_DIRECTORY)/build/lib/validate_checksums.sh $(MAKE_ROOT) $(PROJECT_ROOT) $(MAKE_ROOT)/$(OUTPUT_BIN_DIR) $(FAKE_ARM_BINARIES_FOR_VALIDATION)
endif

#### Image Helpers


#	IMAGE_NAME is dynamically set based on target prefix. \
#	BASE_IMAGE BUILDER_IMAGE RELEASE_BRANCH are automatically passed as build-arg(s) to buildctl. args: \
#	DOCKERFILE_FOLDER: folder containing dockerfile, defaults ./docker/linux \
#	IMAGE_BUILD_ARGS:  additional build-args passed to buildctl, set to name of variable defined in makefile \
#	IMAGE_CONTEXT_DIR: context directory for buildctl, default: .

.PHONY: %/images/push %/images/amd64 %/images/arm64
%/images/push %/images/amd64 %/images/arm64: IMAGE_NAME=$*
%/images/push %/images/amd64 %/images/arm64: DOCKERFILE_FOLDER?=./docker/linux
%/images/push %/images/amd64 %/images/arm64: IMAGE_CONTEXT_DIR?=.
%/images/push %/images/amd64 %/images/arm64: IMAGE_BUILD_ARGS?=

# Build image using buildkit for all platforms, by default pushes to registry defined in IMAGE_REPO.
%/images/push: IMAGE_PLATFORMS?=linux/amd64,linux/arm64
%/images/push: IMAGE_OUTPUT_TYPE?=image
%/images/push: IMAGE_OUTPUT?=push=true
%/images/push: $(BINARY_TARGETS) $(LICENSES_TARGETS_FOR_PREREQ)
	$(BUILDCTL)

# Build helm chart
.PHONY: helm/build
helm/build: $(OUTPUT_DIR)/ATTRIBUTION.txt
helm/build: $(if $(filter true,$(REPO_NO_CLONE)),,$(HELM_GIT_CHECKOUT_TARGET))
helm/build: $(if $(wildcard $(MAKE_ROOT)/helm/patches),$(HELM_GIT_PATCH_TARGET),)
	$(BUILD_LIB)/helm_copy.sh $(HELM_SOURCE_REPOSITORY) $(HELM_DESTINATION_REPOSITORY) $(HELM_DIRECTORY) $(OUTPUT_DIR)
	$(BUILD_LIB)/helm_require.sh $(IMAGE_REPO) $(HELM_DESTINATION_REPOSITORY) $(OUTPUT_DIR) $(IMAGE_TAG) $(LATEST) $(HELM_IMAGE_LIST)
	$(BUILD_LIB)/helm_replace.sh $(HELM_DESTINATION_REPOSITORY) $(OUTPUT_DIR)
	$(BUILD_LIB)/helm_build.sh $(OUTPUT_DIR) $(HELM_DESTINATION_REPOSITORY)

# Build helm chart and push to registry defined in IMAGE_REPO.
.PHONY: helm/push
helm/push: helm/build
	$(BUILD_LIB)/helm_push.sh $(IMAGE_REPO) $(HELM_DESTINATION_REPOSITORY) $(IMAGE_TAG) $(OUTPUT_DIR)

# Build image using buildkit only builds linux/amd64 oci and saves to local tar.
%/images/amd64: IMAGE_PLATFORMS?=linux/amd64

# Build image using buildkit only builds linux/arm64 oci and saves to local tar.
%/images/arm64: IMAGE_PLATFORMS?=linux/arm64

%/images/amd64 %/images/arm64: IMAGE_OUTPUT_TYPE?=oci
%/images/amd64 %/images/arm64: IMAGE_OUTPUT?=dest=$(IMAGE_OUTPUT_DIR)/$(IMAGE_OUTPUT_NAME).tar

%/images/amd64: $(BINARY_TARGETS) $(LICENSES_TARGETS_FOR_PREREQ)
	@mkdir -p $(IMAGE_OUTPUT_DIR)
	$(BUILDCTL)
	$(WRITE_LOCAL_IMAGE_TAG)

%/images/arm64: $(BINARY_TARGETS) $(LICENSES_TARGETS_FOR_PREREQ)
	@mkdir -p $(IMAGE_OUTPUT_DIR)
	$(BUILDCTL)
	$(WRITE_LOCAL_IMAGE_TAG)

.PHONY: %/cgo/amd64 %/cgo/arm64
%/cgo/amd64 %/cgo/arm64: IMAGE_OUTPUT_TYPE?=local
%/cgo/amd64 %/cgo/arm64: DOCKERFILE_FOLDER?=$(BUILD_LIB)/docker/linux/cgo
%/cgo/amd64 %/cgo/arm64: IMAGE_NAME=binary-builder
%/cgo/amd64 %/cgo/arm64: IMAGE_BUILD_ARGS?=GOPROXY COMPONENT
%/cgo/amd64 %/cgo/arm64: IMAGE_CONTEXT_DIR?=$(CGO_SOURCE)
%/cgo/amd64 %/cgo/arm64: BUILDER_IMAGE=$(BASE_IMAGE_REPO)/builder-base:latest

%/cgo/amd64: IMAGE_PLATFORMS=linux/amd64
%/cgo/amd64:
	@mkdir -p $(CGO_SOURCE)
	$(BUILDCTL)

%/cgo/arm64: IMAGE_PLATFORMS=linux/arm64
%/cgo/arm64:
	@mkdir -p $(CGO_SOURCE)
	$(BUILDCTL)

%-useradd/images/export: IMAGE_OUTPUT_TYPE=local
%-useradd/images/export: IMAGE_OUTPUT_DIR=$(OUTPUT_DIR)/files/$*
%-useradd/images/export: IMAGE_OUTPUT?=dest=$(IMAGE_OUTPUT_DIR)
%-useradd/images/export: IMAGE_BUILD_ARGS=IMAGE_USERADD_USER_ID IMAGE_USERADD_USER_NAME
%-useradd/images/export: DOCKERFILE_FOLDER=$(BUILD_LIB)/docker/linux/useradd
%-useradd/images/export: IMAGE_PLATFORMS=linux/amd64
%-useradd/images/export:
	@mkdir -p $(IMAGE_OUTPUT_DIR)
	$(BUILDCTL)

ifneq ($(IMAGE_NAMES),)
local-images: $(LOCAL_IMAGE_TARGETS)
images: $(IMAGE_TARGETS)
endif

## Fetch Binary Targets
$(BINARY_DEPS_DIR)/linux-%:
	$(BUILD_LIB)/fetch_binaries.sh $(BINARY_DEPS_DIR) $* $(ARTIFACTS_BUCKET) $(LATEST) $(RELEASE_BRANCH)

# Do not binary deps as intermediate files
ifneq ($(FETCH_BINARIES_TARGETS),)
.SECONDARY: $(call FULL_FETCH_BINARIES_TARGETS, $(FETCH_BINARIES_TARGETS))
endif

## Build Targets
.PHONY: build

build: $(BUILD_TARGETS)

.PHONY: release
release: $(RELEASE_TARGETS)

.PHONY: %/release-branches/all
%/release-branches/all:
	@for version in $(SUPPORTED_K8S_VERSIONS) ; do \
		$(MAKE) $* RELEASE_BRANCH=$$version; \
	done;

###  Clean Targets

.PHONY: clean-repo
clean-repo:
	@rm -rf $(REPO)	$(HELM_SOURCE_REPOSITORY)

.PHONY: clean
clean: $(if $(filter true,$(REPO_NO_CLONE)),,clean-repo)
	@rm -rf _output	

## --------------------------------------
## Help
## --------------------------------------
#@  Helpers
.PHONY: help
help: # Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m\033[0m\n"} /^[$$()% \/a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-55s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 4) } ' $(MAKEFILE_LIST)

.PHONY: help-list
help-list: 
	@awk 'BEGIN {FS = ":.*#";} /^[$$()% \/a-zA-Z0-9_-]+:.*?#/ { printf "%s: ##%s\n", $$1, $$2 } /^#@/ { printf "\n##@%s\n", substr($$0, 4) } ' $(MAKEFILE_LIST)

.PHONY: add-generated-help-block
add-generated-help-block: # Add or update generated help block to document project make file and support shell auto completion
add-generated-help-block:
	$(BUILD_LIB)/generate_help_body.sh $(MAKE_ROOT) "$(BINARY_TARGET_FILES)" "$(BINARY_PLATFORMS)" "${BINARY_TARGETS}" \
		$(REPO) $(if $(PATCHES_DIR),true,false) "$(LOCAL_IMAGE_TARGETS)" "$(IMAGE_TARGETS)" "$(BUILD_TARGETS)" "$(RELEASE_TARGETS)" \
		"$(HAS_S3_ARTIFACTS)" "$(HAS_LICENSES)" "$(REPO_NO_CLONE)" "$(call FULL_FETCH_BINARIES_TARGETS,$(FETCH_BINARIES_TARGETS))" \
		"$(HAS_HELM_CHART)"
