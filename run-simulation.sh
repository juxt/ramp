#!/bin/bash

BucketName=ramp-load-test-$(uuidgen)
BucketPublicRead=false
Local=false
ReplaceStack=false
SelfDestruct=false
StackName=ramping-load-test
SSHKeyName=
Region=eu-west-1
UseBucket=false
Verbose=false

function usage() {
    printf "
Options:\n\
  -b <string>   Bucket: mame of an S3 bucket to upload test results to. Will be created if it doesn't exist\n\
  -h            Help\n\
  -k <string>   Key: name of an existing EC2 KeyPair to enable SSH access to the instance
  -l            Local: run the simulation locally rather than on AWS
  -n <string>   Name of the stack\n\
  -p            Public: give the results S3 bucket public-read permissions\n\
  -r            Replace: first delete any existing stack with the same name
  -s            Self-destruct: delete the stack once testing is complete\n\
  -v            Verbose: prints details of the stack launch\n"
}

############################################
# Utils
function vecho() {
    if [ $Verbose == true ]; then
        echo $1
    fi
}

function createBucket() {
    vecho "Creating bucket $BucketName if missing..."
    aws s3api create-bucket \
        --bucket $BucketName \
        --create-bucket-configuration \
        LocationConstraint=$Region \
        >/dev/null
    
    if [ $BucketPublicRead == true ]; then
        vecho "Giving $BucketName public-read permissions..."
        aws s3api put-bucket-policy \
            --bucket $BucketName \
            --policy "{ \"Version\":\"2012-10-17\", \"Statement\":[{ \"Sid\":\"PublicReadGetObject\", \"Effect\":\"Allow\", \"Principal\": \"*\", \"Action\":[\"s3:GetObject\"], \"Resource\":[\"arn:aws:s3:::$BucketName/*\" ] } ] }"
    fi
}

function printSimulationResultsLocation() {
    if [ $UseBucket == true ]; then
        #TODO
        echo "https://s3.console.aws.amazon.com/s3/buckets/$BucketName/"
    else
        #TODO
        echo "Results available locally in gatling/results"
    fi
}

############################################
# Run locally
function runLocally() {
    if [ ! -f "gatling/bin/gatling.sh" ]; then
        vecho "Downloading Gatling..."
        rm -rf gatling/
        wget https://repo1.maven.org/maven2/io/gatling/highcharts/gatling-charts-highcharts-bundle/2.3.1/gatling-charts-highcharts-bundle-2.3.1-bundle.zip
        unzip gatling-charts-highcharts-bundle-2.3.1-bundle.zip
        rm -f gatling-charts-highcharts-bundle-2.3.1-bundle.zip
        mv gatling-charts-highcharts-bundle-2.3.1/ gatling/
        rm -rf gatling/user-files/simulations/
        mkdir gatling/user-files/simulations/
    fi

    vecho "Preparing simulation files..."
    cp LoadSimulation.scala gatling/user-files/simulations/LoadSimulation.scala
    
    vecho "Running simulation..."
    if [ $Verbose == true ]; then
        JAVA_OPTS="-DPeakUsers=$PeakUsers -DDuration=$Duration -DTargetUrl=$TargetUrl" ./gatling/bin/gatling.sh \
                 -s "ramp.LoadSimulation" \
                 -rd "ramp load test"
    else
        JAVA_OPTS="-DPeakUsers=$PeakUsers -DDuration=$Duration -DTargetUrl=$TargetUrl" ./gatling/bin/gatling.sh \
                 -s "ramp.LoadSimulation" \
                 -rd "ramp load test" \
                 -m \
                 > gatling/results/gatling.out
    fi

    if [ $UseBucket == true]; then
        createBucket
        vecho "Uploading results to $BucketName..."
        aws s3 cp --recursive gatling/results/ s3://$BucketName/
    fi
}

############################################
# Run on AWS
function deleteStack() {
    vecho "Deleting stack $StackName..."
    aws cloudformation delete-stack \
        --stack-name $StackName \
        >/dev/null

    aws cloudformation wait stack-delete-complete \
        --stack-name $StackName \
        >/dev/null
}

function createStack() {
    vecho "Uploading stack setup files to $BucketName..."
    aws s3 cp aws-userdata.sh s3://$BucketName \
            --acl public-read \
            >/dev/null
    
    vecho "Creating stack $StackName if missing..."
    aws cloudformation create-stack \
        --stack-name $StackName \
        --region $Region \
        --template-body file://aws-cft-ramp.yaml \
        --capabilities CAPABILITY_NAMED_IAM \
        --parameters \
        ParameterKey=BucketName,ParameterValue=$BucketName \
        ParameterKey=SSHKeyName,ParameterValue=$SSHKeyName \
        > /dev/null

    aws cloudformation wait stack-create-complete \
        --stack-name $StackName \
        >/dev/null

    StackStatus=$(aws cloudformation describe-stacks \
                       --stack-name $StackName \
                       --query 'Stacks[0].StackStatus' \
                       --output text)
    if [ $StackStatus != CREATE_COMPLETE ]; then
        echo "Stack creation failed!"
        exit 1
    fi
}

function runRemoteSimulation() {
    UseBucket=true
    vecho "Uploading simulation files to $BucketName..."
    aws s3 cp LoadSimulation.scala s3://$BucketName \
            --acl public-read \
            >/dev/null

    vecho "Starting simulation on remote instance..."
    UserName=$(aws iam get-user --query 'User.UserName' --output text)
    aws iam attach-user-policy --user-name $UserName --policy-arn arn:aws:iam::aws:policy/AmazonSSMFullAccess
    # aws s3 cp s3://$BucketName/LoadSimulation.scala \
    #     /gatling/user-files/simulations/ \
    #     >/dev/null
    # JAVA_OPTS="-DPeakUsers=$PeakUsers -DDuration=$Duration -DTargetUrl=$TargetUrl" /gatling/bin/gatling.sh \
    #          -s "LoadSimulation" \
    #          -m \
    #          > /gatling/results/gatling.out
    # aws s3 cp --recursive /gatling/results/ s3://$BucketName/
    aws ssm send-command \
        --document-name "AWS-RunShellScript" \
        --document-version "\$DEFAULT" \
        --targets "Key=instanceids,Values=$InstanceId" \
        --parameters '{"workingDirectory":[""],"executionTimeout":["172800"],"commands":["aws s3 cp s3://$BucketName/LoadSimulation.scala \\"," /gatling/user-files/simulations/ \\"," >/dev/null","JAVA_OPTS=\"-DPeakUsers=$PeakUsers -DDuration=$Duration -DTargetUrl=$TargetUrl\" /gatling/bin/gatling.sh \\"," -s \"LoadSimulation\" \\"," -m \\"," > /gatling/results/gatling.out","aws s3 cp --recursive /gatling/results/ s3://$BucketName/"]}' \
        --comment "console test" \
        --timeout-seconds 600 \
        --max-concurrency "50" \
        --max-errors "0" \
        --output-s3-bucket-name "$BucketName" \
        --region $Region
}

function runOnAWS() {
    if [ $ReplaceStack == true ]; then
        deleteStack
    fi
    createBucket
    createStack
    runRemoteSimulation    
    if [ $SelfDestruct == true ]; then
        deleteStack
    fi
}

############################################
# Arguments parsing
while getopts ":b:hk:ln:prsv" opt; do
    case "${opt}" in
        b )
            BucketName=$OPTARG
            UseBucket=true;;
        h )
            usage
            exit 0;;
        k )
            SSHKeyName=$OPTARG;;
        l )
            Local=true;;
        n )
            StackName=$OPTARG;;
        p )
            BucketPublicRead=true;;
        r )
            ReplaceStack=true;;
        s )
            SelfDestruct=true;;
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

############################################
# Main
source params.txt
if [ $Local == true ]; then
    runLocally
else
    runOnAWS
fi
printSimulationResultsLocation

#Improvements:
##HIGH PRIORITY
###Add Gatling directly to the project instead of downloading it
###Ability to enter simulation params on command line
##LOW PRIORITY
###Choose which simulation file to run (-s gatling option)
###Add comments to simulation results (-rd gatling option)
###Only create-bucket & create-stack (& upload stuff) if they don't exist
###Send arbitrary params to Gatling
###Use any region
###Wait for instance to be in ok state before running commands
