#!/bin/bash

log()   { echo -e "\e[30;47m ${1} \e[0m ${@:2}"; }        # $1 background white
info()  { echo -e "\e[48;5;28m ${1} \e[0m ${@:2}"; }      # $1 background green
warn()  { echo -e "\e[48;5;202m ${1} \e[0m ${@:2}" >&2; } # $1 background orange
error() { echo -e "\e[48;5;196m ${1} \e[0m ${@:2}" >&2; } # $1 background red

log START $(date "+%Y-%d-%m %H:%M:%S")
START=$SECONDS

[[ -z $(printenv | grep ^CHDIR=) ]] \
    && { error ABORT CHDIR env variable is required; exit 1; } \
    || log CHDIR $CHDIR
    
# list all TF_VAR_ variables available in enviroment variables
while read line; do
    TF_VAR=$(echo $line | cut -d '=' -f 1)
    VALUE=$(echo $line | cut -d '=' -f 2-)
    log $TF_VAR $VALUE
done < <(printenv | grep ^TF_VAR_)

# https://www.terraform.io/cli/commands/plan
terraform -chdir="$CHDIR" plan -out=terraform.plan
    
# https://www.terraform.io/cli/commands/apply
terraform -chdir="$CHDIR" apply -auto-approve terraform.plan

log END $(date "+%Y-%d-%m %H:%M:%S")
info DURATION $(($SECONDS - $START)) seconds