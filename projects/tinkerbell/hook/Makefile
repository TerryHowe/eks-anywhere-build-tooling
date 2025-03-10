BASE_DIRECTORY=$(shell git rev-parse --show-toplevel)
GIT_TAG?=$(shell cat GIT_TAG)
GOLANG_VERSION?="1.15"

REPO=hook
REPO_OWNER=tinkerbell

BASE_IMAGE_NAME?=eks-distro-minimal-base
DOCKERFILE_FOLDER=./docker/linux/$(IMAGE_NAME)

BOOTKIT_IMAGE_COMPONENT=tinkerbell/hook-bootkit
TINK_DOCKER_IMAGE_COMPONENT=tinkerbell/hook-docker
KERNEL_IMAGE_COMPONENT=tinkerbell/hook-kernel

IMAGE_NAMES=bootkit tink-docker kernel

BINARY_TARGET_FILES=bootkit tink-docker
SOURCE_PATTERNS=./ ./

GO_MOD_DOWNLOAD_TARGETS=$(REPO)/bootkit/eks-anywhere-go-mod-download $(REPO)/tink-docker/eks-anywhere-go-mod-download
GATHER_LICENSES_TARGETS=$(OUTPUT_DIR)/bootkit/attribution/go-license.csv $(OUTPUT_DIR)/tink-docker/attribution/go-license.csv
ATTRIBUTION_TARGETS=BOOTKIT_ATTRIBUTION.txt TINK_DOCKER_ATTRIBUTION.txt

CREATE_HOOK_FILES=$(REPO)/dist/vmlinuz-x86_64

HAS_S3_ARTIFACTS=true
SIMPLE_CREATE_TARBALLS=false

include $(BASE_DIRECTORY)/Common.mk

$(OUTPUT_BIN_DIR)/%/bootkit $(REPO)/bootkit/eks-anywhere-go-mod-download \
	$(OUTPUT_DIR)/bootkit/attribution/go-license.csv: REPO_SUBPATH=./bootkit

$(OUTPUT_DIR)/bootkit/attribution/go-license.csv BOOTKIT_ATTRIBUTION.txt: LICENSES_OUTPUT_DIR=$(OUTPUT_DIR)/bootkit

$(OUTPUT_BIN_DIR)/%/tink-docker $(REPO)/tink-docker/eks-anywhere-go-mod-download \
	$(OUTPUT_DIR)/tink-docker/attribution/go-license.csv: REPO_SUBPATH=./tink-docker

$(OUTPUT_DIR)/tink-docker/attribution/go-license.csv TINK_DOCKER_ATTRIBUTION.txt: LICENSES_OUTPUT_DIR=$(OUTPUT_DIR)/tink-docker

# For local image builds we override to push to local registry.
%/images/amd64: IMAGE_OUTPUT=push=true
%/images/amd64: IMAGE_OUTPUT_TYPE=image

# tink-docker image required docker runtime.
# We are using eks-distro-minimal-base-glibc as the base and builder to install docker.
tink-docker/images/%: BASE_IMAGE_NAME=eks-distro-minimal-base-glibc

# Currently the kernel image is being built off upstream.
# TODO: Setup a build environment to build the linux kernel.
kernel/images/%: BASE_IMAGE=quay.io/tinkerbell/hook-kernel:5.10.57

s3-artifacts: $(CREATE_HOOK_FILES)

$(CREATE_HOOK_FILES): tarballs
# Modify the linuxkit config file hook/hook.yaml to point to IMAGE_REPO.
# Upstream make target `dist-existing-images` is triggered to perform linuxkit build and generate OSIE files.
	sed -i -E -e 's,quay.io/tinkerbell/hook-(bootkit|docker|kernel).*,$(IMAGE_REPO)/tinkerbell/hook-\1:latest,g' $(REPO)/hook.yaml
	make dist-existing-images -C $(REPO)
	mkdir -p $(OUTPUT_DIR)/hook/$(GIT_TAG)
	cp $(REPO)/dist/* $(OUTPUT_DIR)/hook/$(GIT_TAG)/
	mkdir -p $(ARTIFACTS_PATH)
	cp -rf $(OUTPUT_DIR)/hook/* $(ARTIFACTS_PATH)


########### DO NOT EDIT #############################
# To update call: make add-generated-help-block
# This is added to help document dynamic targets and support shell autocompletion
# Run make help for a formatted help block with all targets
include Help.mk
########### END GENERATED ###########################
