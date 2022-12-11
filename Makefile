# https://www.gnu.org/software/make/manual/html_node/Special-Targets.html#Special-Targets
# https://www.gnu.org/software/make/manual/html_node/Options-Summary.html

# use bash not sh
SHELL:= /bin/bash

.PHONY: build help
help:
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

GIT_SHA=$(shell git rev-parse HEAD) # latest commit hash
GIT_DIFF=$(shell git diff -s --exit-code || echo "-dirty") # If working copy has changes, append `-dirty` to hash
GIT_REV=$(GIT_SHA)$(GIT_DIFF)
BUILD_TIMESTAMP=$(shell date '+%F_%H:%M:%S')

# absolute path
ROOT_PATH=/workspaces/infrastructure-modules
VPC_PATH=${ROOT_PATH}/modules/vpc

test: ## Setup the test environment, run the tests and clean the environment
	make clean; \
	make prepare; \
	# -p 1 flag to test each package sequentially; \
	cd ${ROOT_PATH}; \
	go test -timeout 30m -p 1 -v -cover ./...; \
	make clean;

.SILENT: prepare-account prepare-modules-data-mongodb
prepare: ## Setup the test environment
	make prepare-account; \
	make prepare-modules-data-mongodb; \
	make prepare-modules-vpc; \
	make prepare-modules-services-scraper-backend
prepare-account:
	echo 'locals {' > modules/account.hcl; \
	echo 'aws_account_region="${AWS_REGION}"' >> 	${ROOT_PATH}/modules/account.hcl; \
	echo 'aws_account_name="${AWS_PROFILE}"' >> 	${ROOT_PATH}/modules/account.hcl; \
	echo 'aws_account_id="${AWS_ID}"' >> 			${ROOT_PATH}/modules/account.hcl; \
	echo 'aws_access_key="${AWS_ACCESS_KEY}"' >> 	${ROOT_PATH}/modules/account.hcl; \
	echo 'aws_secret_key="${AWS_SECRET_KEY}"' >> 	${ROOT_PATH}/modules/account.hcl; \
	echo '}' >> modules/account.hcl;
prepare-modules-vpc:
	# remove the state file in the vpc folder to create a new one \
	if [ ! -e ${VPC_PATH}/terraform.tfstate ]; then \
		echo 'aws_region="${AWS_REGION}"' > 													${VPC_PATH}/terraform_override.tfvars; \
		echo 'vpc_name="$(shell echo $(AWS_PROFILE) | tr A-Z a-z)-${AWS_REGION}-test-vpc"' >> 	${VPC_PATH}/terraform_override.tfvars; \
		echo 'common_tags={Region: "${AWS_REGION}"}' >> 										${VPC_PATH}/terraform_override.tfvars; \
		echo 'vpc_cidr_ipv4="1.0.0.0/16"' >> 													${VPC_PATH}/terraform_override.tfvars; \
		echo 'enable_nat=true' >> 																${VPC_PATH}/terraform_override.tfvars; \
		cd ${VPC_PATH}; \
		terragrunt init; \
		terragrunt apply -auto-approve; \
	fi
prepare-modules-data-mongodb:
	echo 'aws_access_key="${AWS_ACCESS_KEY}"' > 	${ROOT_PATH}/modules/data/mongodb/terraform_override.tfvars; \
	echo 'aws_secret_key="${AWS_SECRET_KEY}"' >> 	${ROOT_PATH}/modules/data/mongodb/terraform_override.tfvars; \
	cd ${ROOT_PATH}/modules/data/mongodb; \
	terragrunt init; 
prepare-modules-services-scraper-backend:
	echo 'aws_access_key="${AWS_ACCESS_KEY}"' > 	${ROOT_PATH}/modules/services/scraper-backend/terraform_override.tfvars; \
	echo 'aws_secret_key="${AWS_SECRET_KEY}"' >> 	${ROOT_PATH}/modules/services/scraper-backend/terraform_override.tfvars;
	cd ${ROOT_PATH}/modules/services/scraper-backend; \
	terragrunt init; 

clean: ## Clean the test environment
	make nuke-region-exclude-vpc; \
	make clean-vpc;
clean-old: ## Clean the test environment that is old
	make nuke-old-region-exclude-vpc; \
	make clean-old-vpc;
clean-vpc:
	if [ ! -e ${VPC_PATH}/terraform.tfstate ]; then \
		make nuke-region-vpc; \
		rm ${VPC_PATH}/terraform.tfstate; \
	else \
		cd ${VPC_PATH}; \
		terragrunt destroy -auto-approve; \
		rm ${VPC_PATH}/terraform.tfstate; \
		# cd ${ROOT_PATH}; \
	fi
clean-old-vpc:
	make nuke-old-region-vpc;

OLD=4h
# nuke: ## Nuke all resources
# 	cloud-nuke aws;
# nuke-region: ## Nuke within the user's region all resources
# 	cloud-nuke aws --region ${AWS_REGION} --force;
nuke-region-exclude-vpc-nat: ## Nuke within the user's region all resources excluding vpc and nat, e.g. for repeating tests manually
	cloud-nuke aws --region ${AWS_REGION} --exclude-resource-type vpc --exclude-resource-type nat-gateway --force;
nuke-region-exclude-vpc:
	cloud-nuke aws --region ${AWS_REGION} --exclude-resource-type vpc --force;
nuke-region-vpc:
	cloud-nuke aws --region ${AWS_REGION} --resource-type vpc --force;
nuke-old-region-exclude-vpc:
	cloud-nuke aws --region ${AWS_REGION} --exclude-resource-type vpc --older-than $OLD --force;
nuke-old-region-vpc:
	cloud-nuke aws --region ${AWS_REGION} --resource-type vpc --older-than $OLD --force;

# it needs the tfstate files which are generated with apply
graph: ## Generate the graphs from all the tfstate files
	make graph-modules-vpc; \
	make graph-modules-services-scraper-backend; \
	make graph-modules-data-mongodb;
graph-modules-vpc:
	cat ${ROOT_PATH}/modules/vpc/terraform.tfstate | inframap generate --tfstate | dot -Tpng > ${ROOT_PATH}/modules/vpc/graph.png
graph-modules-services-scraper-backend:
	cat ${ROOT_PATH}/modules/services/scraper-backend/terraform.tfstate | inframap generate --tfstate | dot -Tpng > ${ROOT_PATH}/modules/services/scraper-backend/graph.png
graph-modules-data-mongodb:
	cat ${ROOT_PATH}/modules/data/mongodb/terraform.tfstate | inframap generate --tfstate | dot -Tpng > ${ROOT_PATH}/modules/data/mongodb/graph.png

