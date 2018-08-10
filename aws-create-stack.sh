#!/bin/bash

aws cloudformation create-stack \
    --stack-name LoadTest \
    --region eu-central-1 \
    --template-body file://aws-cft-loadtest.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters \
    ParameterKey=TargetUrl,ParameterValue=$1 \
    ParameterKey=PeakUsers,ParameterValue=10000 \
    ParameterKey=Duration,ParameterValue=360 \
    ParameterKey=BucketName,ParameterValue=juxthug-load-test \
    ParameterKey=SelfDestruct,ParameterValue=true \
    ParameterKey=SSHKeyName,ParameterValue=
