#!/bin/bash

log()   { echo -e "\e[30;47m ${1} \e[0m ${@:2}"; }        # $1 background white
info()  { echo -e "\e[48;5;28m ${1} \e[0m ${@:2}"; }      # $1 background green
warn()  { echo -e "\e[48;5;202m ${1} \e[0m ${@:2}" >&2; } # $1 background orange
error() { echo -e "\e[48;5;196m ${1} \e[0m ${@:2}" >&2; } # $1 background red

usage() {
    echo -ne "\033[0;4musage\033[0m "
    echo "$(basename $0) <directory>"
}

[[ $# -lt 1 || ! -d $1 ]] && { error abort argument error; usage; exit 1; }

CHDIR=$1
log CHDIR "$CHDIR"

# list all TF_VAR_ variables available in enviroment variables
while read line; do
    TF_VAR=$(echo $line | cut -d '=' -f 1)
    VALUE=$(echo $line | cut -d '=' -f 2-)
    log "$TF_VAR" "$VALUE"
done < <(printenv | grep ^TF_VAR_)

# https://www.terraform.io/cli/commands/output
JSON=$(terraform -chdir="$CHDIR" output -json)

while read line; do
    log "$line" $(echo "$JSON" | jq -r ".$line.value")
done < <(echo "$JSON" | jq -r 'keys[]')