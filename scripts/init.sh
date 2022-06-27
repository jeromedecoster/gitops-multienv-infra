init() {
    if [[ ! -f "$PROJECT_DIR/.env_AWS_ID" ]]; then
        # clear newline : https://stackoverflow.com/a/19345966
        aws sts get-caller-identity \
            --query 'Account' \
            --output text | \
            tr -d '\n' > "$PROJECT_DIR/.env_AWS_ID"

        info created file .env_AWS_ID
    fi

    AWS_ID=$(cat "$PROJECT_DIR/.env_AWS_ID")
    log AWS_ID $AWS_ID

    if [[ ! -f "$PROJECT_DIR/.env_UUID" ]]; then
        uuidgen --random | head --bytes 5 > "$PROJECT_DIR/.env_UUID"
        info created file .env_UUID
    fi

    UUID=$(cat "$PROJECT_DIR/.env_UUID")
    log UUID $UUID

    if [[ ! -f "$PROJECT_DIR/.env_S3_BUCKET" ]]; then

        S3_BUCKET=$PROJECT_NAME-$UUID
        # if the bucket $S3_BUCKET does not exists
        # test s3 bucket : https://docs.aws.amazon.com/cli/latest/reference/s3api/head-bucket.html
        if [[ -n $(aws s3api head-bucket --bucket $S3_BUCKET 2>&1 ) ]];
        then
            info CREATE bucket $S3_BUCKET
            # create s3 bucket : https://awscli.amazonaws.com/v2/documentation/api/latest/reference/s3/mb.html
            aws s3 mb s3://$S3_BUCKET --region $AWS_REGION

            # /!\ important for terraform states : enable bucket versioning
            aws s3api put-bucket-versioning \
                --bucket $S3_BUCKET \
                --versioning-configuration Status=Enabled \
                --region $AWS_REGION

            echo -n $S3_BUCKET > "$PROJECT_DIR/.env_S3_BUCKET"
        fi
    fi
    
    S3_BUCKET=$(cat "$PROJECT_DIR/.env_S3_BUCKET")
    log S3_BUCKET $S3_BUCKET

    if [[ -z $(which jq) ]]; then
        error 'NOT FOUND' jq is required ➜ 'https://github.com/stedolan/jq'
    fi

    if [[ -z $(which yq) ]]; then
        error 'NOT FOUND' yq is required ➜ 'https://github.com/mikefarah/yq'
    fi

    if [[ -z $(which gh) ]]; then
        error 'NOT FOUND' gh is required ➜ 'https://github.com/cli/cli'
    fi
}

init