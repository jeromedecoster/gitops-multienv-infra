#!/bin/bash

#
# variables
#
export AWS_PROFILE=default
export PROJECT_NAME=multienv-infra
export AWS_REGION=eu-west-3
export GIT_REPO=git@github.com:jeromedecoster/gitops-multienv-infra.git
# the directory containing the script file
export PROJECT_DIR="$(cd "$(dirname "$0")"; pwd)"

#
# overwrite TF variables
#
export TF_VAR_project_name=$PROJECT_NAME
export TF_VAR_region=$AWS_REGION

log() { echo -e "\e[30;47m ${1^^} \e[0m ${@:2}"; }          # $1 uppercase background white
info() { echo -e "\e[48;5;28m ${1^^} \e[0m ${@:2}"; }       # $1 uppercase background green
warn() { echo -e "\e[48;5;202m ${1^^} \e[0m ${@:2}" >&2; }  # $1 uppercase background orange
error() { echo -e "\e[48;5;196m ${1^^} \e[0m ${@:2}" >&2; } # $1 uppercase background red

# export functions : https://unix.stackexchange.com/a/22867
export -f log info warn error

# log $1 in underline then $@ then a newline
under() {
    local arg=$1
    shift
    echo -e "\033[0;4m${arg}\033[0m ${@}"
    echo
}

usage() {
    under usage 'call the Makefile directly: make dev
      or invoke this file directly: ./make.sh dev'
}

# setup project + create S3 bucket
init() {
    bash scripts/init.sh
}

# terraform init the staging env
staging-init() {
    [[ ! -f "$PROJECT_DIR/.env_UUID" ]] && init
    export CHDIR="$PROJECT_DIR/terraform/staging"
    export S3_BUCKET=$(cat "$PROJECT_DIR/.env_S3_BUCKET")
    export CONFIG_KEY=staging/terraform.tfstate
    scripts/terraform-init.sh
}

# terraform init the production env
production-init() {
    [[ ! -f $PROJECT_DIR/.env_UUID ]] && init
    export CHDIR=$PROJECT_DIR/terraform/production
    export S3_BUCKET=$(cat "$PROJECT_DIR/.env_S3_BUCKET")
    export CONFIG_KEY=production/terraform.tfstate
    scripts/terraform-init.sh
}

# terraform validate the staging env
staging-validate() {
    export CHDIR="$PROJECT_DIR/terraform/staging"
    scripts/terraform-validate.sh
}

# terraform validate the production env
production-validate() {
    export CHDIR=$PROJECT_DIR/terraform/production
    scripts/terraform-validate.sh
}

# terraform plan + apply the staging env
staging-apply() {
    export CHDIR="$PROJECT_DIR/terraform/staging"
    export TF_VAR_project_env=staging
    scripts/terraform-apply.sh
    # kubectl-eks-config
}

# terraform plan + apply the production env
production-apply() {
    export CHDIR="$PROJECT_DIR/terraform/production"
    export TF_VAR_project_env=production
    scripts/terraform-apply.sh
}

kubectl-eks-config() {
    OUTPUT=$(terraform -chdir="$CHDIR" output --json)
    NAME=$(echo "$OUTPUT" | jq --raw-output '.eks_cluster_id.value')
    log NAME $NAME
    REGION=$(echo "$OUTPUT" | jq --raw-output '.region.value')
    log REGION $REGION

    # setup kubectl config
    log KUBECTL update config ...
    aws eks update-kubeconfig \
        --name $NAME \
        --region $REGION

    KUBE_CONTEXT=$(kubectl config current-context)
    log KUBE_CONTEXT $KUBE_CONTEXT
    
    # wait for configmap availability
    while [[ -z $(kubectl get configmap aws-auth -n kube-system 2>/dev/null) ]]; do sleep 1; done

    log WRITE aws-auth-configmap.yaml
    # your current user or role does not have access to Kubernetes objects on this EKS cluster
    # https://stackoverflow.com/questions/70787520/your-current-user-or-role-does-not-have-access-to-kubernetes-objects-on-this-eks
    # https://stackoverflow.com/a/70980613
    kubectl get configmap aws-auth \
        --namespace kube-system \
        --output yaml > "$PROJECT_DIR/aws-auth-configmap.yaml"

    log WRITE aws-auth-configmap.json
    # convert to json
    yq aws-auth-configmap.yaml -o json > "$PROJECT_DIR/aws-auth-configmap.json"

    AWS_ID=$(cat "$PROJECT_DIR/.env_AWS_ID")
    log AWS_ID $AWS_ID

    # add mapUsers (use jq instead yq to add mapUsers because it's MUCH simpler and MORE clean)
    jq '.data += {"mapUsers": "- userarn: arn:aws:iam::'$AWS_ID':root\n  groups:\n  - system:masters\n"}' aws-auth-configmap.json \
    | yq --prettyPrint > "$PROJECT_DIR/aws-auth-configmap.yaml"

    # apply udated aws-auth-configmap.yaml
    kubectl apply --filename aws-auth-configmap.yaml --namespace kube-system
}

# setup kubectl config + aws-auth configmap for staging env
eks-staging-config() {
    export CHDIR="$PROJECT_DIR/terraform/staging"
    kubectl-eks-config

    log KUBE rename context to $PROJECT_NAME-staging
    kubectl config rename-context arn:aws:eks:$REGION:$AWS_ID:cluster/$PROJECT_NAME-staging $PROJECT_NAME-staging

    KUBE_CONTEXT=$(kubectl config current-context)
    log KUBE_CONTEXT $KUBE_CONTEXT
}

# setup kubectl config + aws-auth configmap for production env
eks-production-config() {
    export CHDIR="$PROJECT_DIR/terraform/production"
    kubectl-eks-config

    log KUBE rename context to $PROJECT_NAME-production
    kubectl config rename-context arn:aws:eks:$REGION:$AWS_ID:cluster/$PROJECT_NAME-production $PROJECT_NAME-production

    KUBE_CONTEXT=$(kubectl config current-context)
    log KUBE_CONTEXT $KUBE_CONTEXT
}

staging-destroy() {
    kubectl config use-context $PROJECT_NAME-staging
    kubectl config current-context

    kubectl delete ns gitops-multienv --ignore-not-found --wait

    export TF_VAR_project_env=staging
    terraform -chdir=$PROJECT_DIR/terraform/staging destroy -auto-approve
}

production-destroy() {
    kubectl config use-context $PROJECT_NAME-production
    kubectl config current-context

    kubectl delete ns gitops-multienv --ignore-not-found --wait

    export TF_VAR_project_env=production
    terraform -chdir=$PROJECT_DIR/terraform/production destroy -auto-approve
}

argo-install() {
    log wait kubectl config context must be defined
    while [[ -z $(kubectl config current-context 2>/dev/null) ]]; do sleep 1; done

    log delete kubectl delete previous argocd namespace
    kubectl delete ns argocd --ignore-not-found --wait

    log create kubectl create argocd namespace
    kubectl create namespace argocd

    log install kubectl install argocd
    kubectl apply \
        --namespace argocd \
        --filename https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    # in another terminal window :
    # watch kubectl get all -n argocd

    log wait kubectl argocd-server must be deployed
    kubectl wait deploy argocd-server \
        --timeout=180s \
        --namespace argocd \
        --for=condition=Available=True

    log patch add load balancer to argocd-server service
    kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

    log wait argocd load balancer must be defined
    # sleep here
    while true; do
        ARGO_LOAD_BALANCER=$(kubectl get svc argocd-server \
            --namespace argocd \
            --output json |
            jq --raw-output '.status.loadBalancer.ingress[0].hostname')
        [[ "$ARGO_LOAD_BALANCER" != 'null' ]] && break;
    done
    log ARGO_LOAD_BALANCER $ARGO_LOAD_BALANCER

    log wait argocd load balancer must be available
    # sleep here
    while [[ -z $(curl $ARGO_LOAD_BALANCER 2>/dev/null) ]]; do sleep 1; done

    ARGO_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
        --namespace argocd \
        --output jsonpath="{.data.password}" |
        base64 --decode)
    log ARGO_PASSWORD $ARGO_PASSWORD

    argocd login $ARGO_LOAD_BALANCER \
        --insecure \
        --username=admin \
        --password=$ARGO_PASSWORD

    log ACTION open $ARGO_LOAD_BALANCER + accept self-signed risk
    log argocd login with ...
    log username admin
    log password $ARGO_PASSWORD
}

argo-login() {
    SERVER=$(kubectl get svc argocd-server \
        --context $PROJECT_NAME-staging \
        --namespace argocd \
        --output json |
        jq --raw-output '.status.loadBalancer.ingress[0].hostname')
    log SERVER $SERVER

    log USERNAME admin

    PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
        --context $PROJECT_NAME-staging \
        --namespace argocd \
        --output jsonpath="{.data.password}" |
        base64 --decode)
    log PASSWORD $PASSWORD

    argocd login $SERVER \
        --insecure \
        --username=admin \
        --password=$PASSWORD
}

argo-add-repo() {
    if [[ ! -f ~/.ssh/$PROJECT_NAME.pem ]];
    then
        log CREATE "$PROJECT_NAME.pem keypair (without passphrase)"
        # -t ➜ Specifies the type of key to create.
        # -N ➜ Provides the new passphrase.
        # -f ➜ Specifies the filename of the key file.
        ssh-keygen -t ed25519 -N "" -f ~/.ssh/$PROJECT_NAME.pem

        mv ~/.ssh/$PROJECT_NAME.pem.pub ~/.ssh/$PROJECT_NAME.pub
        info CREATED "~/.ssh/$PROJECT_NAME.pem"
        info CREATED "~/.ssh/$PROJECT_NAME.pub"
    fi

    if [[ -z $(gh ssh-key list | grep ^$PROJECT_NAME) ]];
    then
        log ADD $PROJECT_NAME.pub to Github
        gh ssh-key add ~/.ssh/$PROJECT_NAME.pub --title $PROJECT_NAME
    fi

    log ADD git repository to argocd
    argocd repo add $GIT_REPO \
        --insecure-ignore-host-key \
        --ssh-private-key-path ~/.ssh/$PROJECT_NAME.pem
}

argo-add-cluster() {
    argocd cluster add --yes $PROJECT_NAME-production
}

argo-staging-app() {
    export NAMESPACE=staging
    export SERVER=https://kubernetes.default.svc
    # /!\ switch to the staging cluster for the next commands
    kubectl config use-context $PROJECT_NAME-staging
    cat argocd/argocd-app.yaml | envsubst | kubectl apply -f -

    log wait namespace gitops-multienv must be defined
    while [[ -z $(kubectl get ns gitops-multienv 2>/dev/null) ]]; do sleep 1; done

    log wait website load balancer must be defined
    # sleep here
    while true; do
        WEBSITE_LOAD_BALANCER=$(kubectl get svc website \
            --namespace gitops-multienv \
            --output json |
            jq --raw-output '.status.loadBalancer.ingress[0].hostname')
        [[ "$WEBSITE_LOAD_BALANCER" != 'null' ]] && break;
    done
    log WEBSITE_LOAD_BALANCER $WEBSITE_LOAD_BALANCER

    log wait website load balancer must be available
    # sleep here
    while [[ -z $(curl $WEBSITE_LOAD_BALANCER 2>/dev/null) ]]; do sleep 1; done

    info READY "http://$WEBSITE_LOAD_BALANCER" is available
}

argo-production-app() {
    export NAMESPACE=production
    CLUSTER_ENDPOINT=$(terraform -chdir="$PROJECT_DIR/terraform/production" output \
        -raw eks_cluster_endpoint)
    log CLUSTER_ENDPOINT $CLUSTER_ENDPOINT
    export SERVER=$CLUSTER_ENDPOINT
    # /!\ switch to the staging cluster for the next commands
    kubectl config use-context $PROJECT_NAME-production
    cat argocd/argocd-app.yaml | envsubst | kubectl apply -f -

    log wait namespace gitops-multienv must be defined
    while [[ -z $(kubectl get ns gitops-multienv 2>/dev/null) ]]; do sleep 1; done

    log wait website load balancer must be defined
    # sleep here
    while true; do
        WEBSITE_LOAD_BALANCER=$(kubectl get svc website \
            --namespace gitops-multienv \
            --output json |
            jq --raw-output '.status.loadBalancer.ingress[0].hostname')
        [[ "$WEBSITE_LOAD_BALANCER" != 'null' ]] && break;
    done
    log WEBSITE_LOAD_BALANCER $WEBSITE_LOAD_BALANCER

    log wait website load balancer must be available
    # sleep here
    while [[ -z $(curl $WEBSITE_LOAD_BALANCER 2>/dev/null) ]]; do sleep 1; done

    info READY "http://$WEBSITE_LOAD_BALANCER" is available
}

argo-destroy() {
    argocd app delete app-production --yes
    kubectl delete ns gitops-multienv --context $PROJECT_NAME-production --wait

    argocd app delete app-staging --yes
    kubectl delete ns gitops-multienv --context $PROJECT_NAME-staging --wait
    
    kubectl delete ns argocd --context $PROJECT_NAME-staging --ignore-not-found --wait
}

# if `$1` is a function, execute it. Otherwise, print usage
# compgen -A 'function' list all declared functions
# https://stackoverflow.com/a/2627461
FUNC=$(compgen -A 'function' | grep $1)
[[ -n $FUNC ]] && {
    info execute $1
    eval $1
} || usage
exit 0
