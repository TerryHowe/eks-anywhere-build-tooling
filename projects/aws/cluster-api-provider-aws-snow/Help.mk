


########### DO NOT EDIT #############################
# To update call: make add-generated-help-block
# This is added to help document dynamic targets and support shell autocompletion


##@ GIT/Repo Targets
clone-repo:  ## Clone upstream `cluster-api-provider-aws-snow`
checkout-repo: ## Checkout upstream tag based on value in GIT_TAG file

##@ Image Targets
local-images: ## Builds `cluster-api-provider-aws-snow/images/amd64` as oci tars for presumbit validation
images: ## Pushes `cluster-api-provider-aws-snow/images/push` to IMAGE_REPO
cluster-api-provider-aws-snow/images/amd64: ## Builds/pushes `cluster-api-provider-aws-snow/images/amd64`
cluster-api-provider-aws-snow/images/push: ## Builds/pushes `cluster-api-provider-aws-snow/images/push`

##@ Artifact Targets
tarballs: ## Create tarballs by calling build/lib/simple_create_tarballs.sh unless SIMPLE_CREATE_TARBALLS=false, then tarballs must be defined in project Makefile
s3-artifacts: # Prepare ARTIFACTS_PATH folder structure with tarballs/manifests/other items to be uploaded to s3
upload-artifacts: # Upload tarballs and other artifacts from ARTIFACTS_PATH to S3

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
