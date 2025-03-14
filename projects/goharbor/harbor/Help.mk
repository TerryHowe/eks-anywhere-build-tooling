


########### DO NOT EDIT #############################
# To update call: make add-generated-help-block
# This is added to help document dynamic targets and support shell autocompletion


##@ GIT/Repo Targets
clone-repo:  ## Clone upstream `harbor`
checkout-repo: ## Checkout upstream tag based on value in GIT_TAG file
patch-repo: ## Patch upstream repo with patches in patches directory

##@ Binary Targets
binaries: ## Build all binaries: `harbor-core harbor-jobservice harbor-registryctl harbor-migrate-patch harbor-migrate harbor-exporter` for `linux/amd64 linux/arm64`
_output/bin/harbor/linux-amd64/harbor-core: ## Build `_output/bin/harbor/linux-amd64/harbor-core`
_output/bin/harbor/linux-amd64/harbor-jobservice: ## Build `_output/bin/harbor/linux-amd64/harbor-jobservice`
_output/bin/harbor/linux-amd64/harbor-registryctl: ## Build `_output/bin/harbor/linux-amd64/harbor-registryctl`
_output/bin/harbor/linux-amd64/harbor-migrate-patch: ## Build `_output/bin/harbor/linux-amd64/harbor-migrate-patch`
_output/bin/harbor/linux-amd64/harbor-migrate: ## Build `_output/bin/harbor/linux-amd64/harbor-migrate`
_output/bin/harbor/linux-amd64/harbor-exporter: ## Build `_output/bin/harbor/linux-amd64/harbor-exporter`
_output/bin/harbor/linux-arm64/harbor-core: ## Build `_output/bin/harbor/linux-arm64/harbor-core`
_output/bin/harbor/linux-arm64/harbor-jobservice: ## Build `_output/bin/harbor/linux-arm64/harbor-jobservice`
_output/bin/harbor/linux-arm64/harbor-registryctl: ## Build `_output/bin/harbor/linux-arm64/harbor-registryctl`
_output/bin/harbor/linux-arm64/harbor-migrate-patch: ## Build `_output/bin/harbor/linux-arm64/harbor-migrate-patch`
_output/bin/harbor/linux-arm64/harbor-migrate: ## Build `_output/bin/harbor/linux-arm64/harbor-migrate`
_output/bin/harbor/linux-arm64/harbor-exporter: ## Build `_output/bin/harbor/linux-arm64/harbor-exporter`

##@ Image Targets
local-images: ## Builds `harbor-db/images/amd64 harbor-portal/images/amd64 harbor-core/images/amd64 harbor-log/images/amd64 harbor-nginx/images/amd64 harbor-jobservice/images/amd64 harbor-registry/images/amd64 harbor-registryctl/images/amd64 harbor-redis/images/amd64 harbor-exporter/images/amd64 helm/build` as oci tars for presumbit validation
images: ## Pushes `harbor-db/images/push harbor-portal/images/push harbor-core/images/push harbor-log/images/push harbor-nginx/images/push harbor-jobservice/images/push harbor-registry/images/push harbor-registryctl/images/push harbor-redis/images/push harbor-exporter/images/push helm/push` to IMAGE_REPO
harbor-db/images/amd64: ## Builds/pushes `harbor-db/images/amd64`
harbor-portal/images/amd64: ## Builds/pushes `harbor-portal/images/amd64`
harbor-core/images/amd64: ## Builds/pushes `harbor-core/images/amd64`
harbor-log/images/amd64: ## Builds/pushes `harbor-log/images/amd64`
harbor-nginx/images/amd64: ## Builds/pushes `harbor-nginx/images/amd64`
harbor-jobservice/images/amd64: ## Builds/pushes `harbor-jobservice/images/amd64`
harbor-registry/images/amd64: ## Builds/pushes `harbor-registry/images/amd64`
harbor-registryctl/images/amd64: ## Builds/pushes `harbor-registryctl/images/amd64`
harbor-redis/images/amd64: ## Builds/pushes `harbor-redis/images/amd64`
harbor-exporter/images/amd64: ## Builds/pushes `harbor-exporter/images/amd64`
helm/build: ## Builds/pushes `helm/build`
harbor-db/images/push: ## Builds/pushes `harbor-db/images/push`
harbor-portal/images/push: ## Builds/pushes `harbor-portal/images/push`
harbor-core/images/push: ## Builds/pushes `harbor-core/images/push`
harbor-log/images/push: ## Builds/pushes `harbor-log/images/push`
harbor-nginx/images/push: ## Builds/pushes `harbor-nginx/images/push`
harbor-jobservice/images/push: ## Builds/pushes `harbor-jobservice/images/push`
harbor-registry/images/push: ## Builds/pushes `harbor-registry/images/push`
harbor-registryctl/images/push: ## Builds/pushes `harbor-registryctl/images/push`
harbor-redis/images/push: ## Builds/pushes `harbor-redis/images/push`
harbor-exporter/images/push: ## Builds/pushes `harbor-exporter/images/push`
helm/push: ## Builds/pushes `helm/push`

##@ Helm Targets
helm/build: ## Build helm chart
helm/push: ## Build helm chart and push to registry defined in IMAGE_REPO.

##@ Fetch Binary Targets
_output/dependencies/linux-amd64/eksa/distribution/distribution: ## Fetch `_output/dependencies/linux-amd64/eksa/distribution/distribution`
_output/dependencies/linux-arm64/eksa/distribution/distribution: ## Fetch `_output/dependencies/linux-arm64/eksa/distribution/distribution`

##@ Checksum Targets
checksums: ## Update checksums file based on currently built binaries.
validate-checksums: # Validate checksums of currently built binaries against checksums file.

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
build: ## Called via prow presubmit, calls `validate-checksums local-images attribution  attribution-pr`
release: ## Called via prow postsubmit + release jobs, calls `validate-checksums images `
########### END GENERATED ###########################
