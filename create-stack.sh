#!/bin/bash

TargetUrl=
PeakUsers=3000
Duration=360
BucketName=ramping-load-test-$(uuidgen)
BucketWebsiteAccess=false
ReplaceStack=false
SelfDestruct=false
StackName=ramping-load-test
Region=eu-west-1
Verbose=false

function usage() {
    printf "
Options:\n\
  -b <string>   Bucket: mame of an S3 bucket to upload test results to. Will be created if needed\n\
  -d <int>      Duration: total duration of the test in seconds\n\
  -h            Help\n\
  -n <string>   Name of the stack\n\
  -p            Public: give the results S3 bucket public-read permissions\n\
  -r            Replace: first delete any existing stack with the same name
  -s            Self-destruct: delete the stack once testing is complete\n\
  -t <string>   MANDATORY - Target url. Must start with http:// or https:// and end without a /\n\
  -u <int>      Users: peak number of concurrent users\n\
  -v            Verbose: prints details of the stack launch\n"
}

############################################
# Utils
function vecho() {
    if [ $Verbose == true ]; then
        echo $1
    fi
}

############################################
# Steps of the stack creation
function createBucket() {
    vecho "Uploading files to setup bucket $BucketName..."

    aws s3api create-bucket \
        --bucket $BucketName \
        --create-bucket-configuration \
        LocationConstraint=$Region \
        >/dev/null
    
    aws s3 cp aws-userdata.sh s3://$BucketName \
        --acl public-read \
        >/dev/null
    aws s3 cp LoadSimulation.scala s3://$BucketName \
        --acl public-read \
        >/dev/null
    
    if [ $BucketWebsiteAccess == true ]; then
        aws s3api put-bucket-policy \
            --bucket $BucketName \
            --policy "{ \"Version\":\"2012-10-17\", \"Statement\":[{ \"Sid\":\"PublicReadGetObject\", \"Effect\":\"Allow\", \"Principal\": \"*\", \"Action\":[\"s3:GetObject\"], \"Resource\":[\"arn:aws:s3:::$BucketName/*\" ] } ] }"
    fi
}

function deleteOldStack() {
    vecho "Deleting any existing stack called $StackName..."
    aws cloudformation delete-stack \
        --stack-name $StackName \
        >/dev/null

    aws cloudformation wait stack-delete-complete \
        --stack-name $StackName \
        >/dev/null
}

function createStack() {
    vecho "Creating the stack..."
    aws cloudformation create-stack \
        --stack-name $StackName \
        --region $Region \
        --template-body file://aws-cft-ramp.yaml \
        --capabilities CAPABILITY_NAMED_IAM \
        --parameters \
        ParameterKey=TargetUrl,ParameterValue=$TargetUrl \
        ParameterKey=PeakUsers,ParameterValue=$PeakUsers \
        ParameterKey=Duration,ParameterValue=$Duration \
        ParameterKey=BucketName,ParameterValue=$BucketName \
        ParameterKey=SelfDestruct,ParameterValue=$SelfDestruct \
        ParameterKey=SSHKeyName,ParameterValue=hugo-load-testing \
        > /dev/null

    aws cloudformation wait stack-create-complete \
        --stack-name $StackName \
        >/dev/null

    StackStatus=$(aws cloudformation describe-stacks \
                       --stack-name $StackName \
                       --query 'Stacks[0].StackStatus' \
                       --output text)
}

############################################
# Arguments parsing
while getopts ":b:d:hn:prst:u:v" opt; do
    case "${opt}" in
        b )
            BucketName=$OPTARG;;
        d )
            Duration=$OPTARG;;
        h )
            usage
            exit 0;;
        n )
            StackName=$OPTARG;;
        p )
            BucketWebsiteAccess=true;;
        r )
            ReplaceStack=true;;
        s )
            SelfDestruct=true;;
        t )
            TargetUrl=$OPTARG;;
        u )
            PeakUsers=$OPTARG;;
        v )
            Verbose=true;;
        \? )
            echo "Invalid option: -$OPTARG"
            echo "Use -h to list valid options"
            exit 1;;
        : )
            echo "Missing option argument for -$OPTARG"
            exit 1;;
    esac
done

if [ -z "$TargetUrl" ]; then
    echo "-t [target url] is required"
    exit 1
fi

############################################
# Main
if [ $ReplaceStack == true ]; then
    deleteOldStack
fi
createBucket
createStack
vecho "Results will be uploaded to https://s3.console.aws.amazon.com/s3/buckets/$BucketName/ as soon as the test is complete"
