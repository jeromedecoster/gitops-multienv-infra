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

[[ -z $(printenv | grep ^S3_BUCKET=) ]] \
    && { error ABORT S3_BUCKET env variable is required; exit 1; } \
    || log S3_BUCKET $S3_BUCKET

[[ -z $(printenv | grep ^CONFIG_KEY=) ]] \
    && { error ABORT CONFIG_KEY env variable is required; exit 1; } \
    || log CONFIG_KEY $CONFIG_KEY

[[ -z $(printenv | grep ^AWS_REGION=) ]] \
    && { error ABORT AWS_REGION env variable is required; exit 1; } \
    || log AWS_REGION $AWS_REGION

# https://www.terraform.io/cli/commands/init
terraform -chdir="$CHDIR" init \
    -input=false \
    -backend=true \
    -backend-config="bucket=$S3_BUCKET" \
    -backend-config="key=$CONFIG_KEY" \
    -backend-config="region=$AWS_REGION" \
    -reconfigure

log END $(date "+%Y-%d-%m %H:%M:%S")
info DURATION $(($SECONDS - $START)) seconds