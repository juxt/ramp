#!/bin/bash

TargetUrl=$1
BucketName=$2

aws s3 cp aws-userdata.sh s3://$BucketName \
    --acl public-read \
    >/dev/null

aws s3 cp LoadSimulation.scala s3://$BucketName \
    --acl public-read \
    >/dev/null

aws cloudformation create-stack \
    --stack-name LoadTest \
    --region eu-west-1 \
    --template-body file://aws-cft-loadtest.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters \
    ParameterKey=TargetUrl,ParameterValue=$TargetUrl \
    ParameterKey=PeakUsers,ParameterValue=3000 \
    ParameterKey=Duration,ParameterValue=60 \
    ParameterKey=BucketName,ParameterValue=$BucketName \
    ParameterKey=SelfDestruct,ParameterValue=true \
    ParameterKey=SSHKeyName,ParameterValue=
