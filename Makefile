.SILENT:
.PHONY: vote metrics

help:
	{ grep --extended-regexp '^[a-zA-Z_-]+:.*#[[:space:]].*$$' $(MAKEFILE_LIST) || true; } \
	| awk 'BEGIN { FS = ":.*#[[:space:]]*" } { printf "\033[1;32m%-22s\033[0m%s\n", $$1, $$2 }'


init: # setup project + create S3 bucket
	./make.sh init

staging-init: # terraform init the staging env
	./make.sh staging-init

staging-validate: # terraform validate the staging env
	./make.sh staging-validate

staging-apply: # terraform plan + apply the staging env
	./make.sh staging-apply

staging-destroy: # terraform destroy the staging env
	./make.sh staging-destroy

production-init: # terraform init the production env
	./make.sh production-init

production-validate: # terraform validate the production env
	./make.sh production-validate

production-apply: # terraform plan + apply the production env
	./make.sh production-apply

production-destroy: # terraform destroy the production env
	./make.sh production-destroy

eks-staging-config: # setup kubectl config + aws-auth configmap for staging env
	./make.sh eks-staging-config

eks-production-config: # setup kubectl config + aws-auth configmap for production env
	./make.sh eks-production-config

argo-install: # install argocd in staging env
	./make.sh argo-install

argo-login: # argocd cli login + show access data
	./make.sh argo-login

argo-add-repo: # add git repo connection + create ssh key + add ssh key to github
	./make.sh argo-add-repo

argo-add-cluster: # argocd add production cluster
	./make.sh argo-add-cluster

argo-staging-app: # create argocd staging app
	./make.sh argo-staging-app

argo-production-app: # create argocd production app
	./make.sh argo-production-app

argo-destroy: # delete argocd apps then argocd
	./make.sh argo-destroy