


########### DO NOT EDIT #############################
# To update call: make add-generated-help-block
# This is added to help document dynamic targets and support shell autocompletion


##@ GIT/Repo Targets
clone-repo:  ## Clone upstream `hook`
checkout-repo: ## Checkout upstream tag based on value in GIT_TAG file
patch-repo: ## Patch upstream repo with patches in patches directory

##@ Binary Targets
binaries: ## Build all binaries: `bootkit tink-docker` for `linux/amd64 linux/arm64`
_output/bin/hook/linux-amd64/bootkit: ## Build `_output/bin/hook/linux-amd64/bootkit`
_output/bin/hook/linux-amd64/tink-docker: ## Build `_output/bin/hook/linux-amd64/tink-docker`
_output/bin/hook/linux-arm64/bootkit: ## Build `_output/bin/hook/linux-arm64/bootkit`
_output/bin/hook/linux-arm64/tink-docker: ## Build `_output/bin/hook/linux-arm64/tink-docker`

##@ Image Targets
local-images: ## Builds `bootkit/images/amd64 tink-docker/images/amd64 kernel/images/amd64` as oci tars for presumbit validation
images: ## Pushes `bootkit/images/push tink-docker/images/push kernel/images/push` to IMAGE_REPO
bootkit/images/amd64: ## Builds/pushes `bootkit/images/amd64`
tink-docker/images/amd64: ## Builds/pushes `tink-docker/images/amd64`
kernel/images/amd64: ## Builds/pushes `kernel/images/amd64`
bootkit/images/push: ## Builds/pushes `bootkit/images/push`
tink-docker/images/push: ## Builds/pushes `tink-docker/images/push`
kernel/images/push: ## Builds/pushes `kernel/images/push`

##@ Checksum Targets
checksums: ## Update checksums file based on currently built binaries.
validate-checksums: # Validate checksums of currently built binaries against checksums file.

##@ Artifact Targets
tarballs: ## Create tarballs by calling build/lib/simple_create_tarballs.sh unless SIMPLE_CREATE_TARBALLS=false, then tarballs must be defined in project Makefile
s3-artifacts: # Prepare ARTIFACTS_PATH folder structure with tarballs/manifests/other items to be uploaded to s3
upload-artifacts: # Upload tarballs and other artifacts from ARTIFACTS_PATH to S3

##@ License Targets
gather-licenses: ## Helper to call $(GATHER_LICENSES_TARGETS) which gathers all licenses
attribution: ## Generates attribution from licenses gathered during `gather-licenses`.
attribution-pr: ## Generates PR to update attribution files for projects

##@ Clean Targets
clean: ## Removes source and _output directory
clean-repo: ## Removes source directory

##@ Helpers
help: ## Display this help
add-generated-help-block: ## Add or update generated help block to document project make file and support shell auto completion

##@ Build Targets
build: ## Called via prow presubmit, calls `validate-checksums local-images attribution upload-artifacts attribution-pr`
release: ## Called via prow postsubmit + release jobs, calls `validate-checksums images upload-artifacts`
########### END GENERATED ###########################
