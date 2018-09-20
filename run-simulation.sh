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
declare -A SimParams=()

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
  -v            Verbose: prints details of the stack launch\n\
  --<string1> <string2> Pass the argument string1, with value string2, to the scala simulation script. The default script's supported parameters are TargetUrl, PeakUsers, and Duration."
}

############################################
# Utils
function vecho() {
    if [ $Verbose == true ]; then
        echo $1
    fi
}

function createBucket() {
    vecho "Creating bucket $BucketName..."
    aws s3api create-bucket \
        --bucket "$BucketName" \
        --create-bucket-configuration \
        LocationConstraint="$Region" \
        >/dev/null
    
    if [ $BucketPublicRead == true ]; then
        vecho "Giving $BucketName public-read permissions..."
        aws s3api put-bucket-policy \
            --bucket "$BucketName" \
            --policy "{ \"Version\":\"2012-10-17\", \"Statement\":[{ \"Sid\":\"PublicReadGetObject\", \"Effect\":\"Allow\", \"Principal\": \"*\", \"Action\":[\"s3:GetObject\"], \"Resource\":[\"arn:aws:s3:::$BucketName/*\" ] } ] }" \
        >/dev/null
    fi
}

function printSimulationResultsLocation() {
    if [ $UseBucket == true ]; then
        vecho "Waiting for simulation results..."
        aws s3api wait object-exists \
            --bucket $BucketName \
            --key LatestSim.txt \
            >/dev/null
        aws s3 mv s3://$BucketName/LatestSim.txt LatestSim.txt \
            >/dev/null
        LatestSim=$(<LatestSim.txt)
        rm -f LatestSim.txt
        echo "Simulation report: https://s3-eu-west-1.amazonaws.com/hugo-temp-load-test/$LatestSim/index.html"
    else
        if [ $Verbose == false ]; then
            #If Verbose, gatling itself will print the report path
            LatestSim=$(ls gatling/results/ | sort | tail -n 1)
            echo "Simulation report: $PWD/gatling/results/$LatestSim/index.html"
        fi
    fi
}

function fileToArray() {
    while read -r kv
    do
        key=$(echo "$kv" | cut -d '=' -f1)
        val=$(echo "$kv" | cut -d '=' -f2)
        SimParams[$key]=$val
    done < "params.txt"
}

function arrayToFile() {
    rm -f params.txt
    for key in "${!SimParams[@]}"; do
        echo $key=${SimParams[$key]} >> params.txt
    done
}

############################################
# Run locally
function runLocally() {
    vecho "Preparing simulation files..."
    cp LoadSimulation.scala gatling/user-files/simulations/LoadSimulation.scala
    
    vecho "Running simulation locally..."
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

    if [ $UseBucket == true ]; then
        createBucket
        LatestSim=$(ls gatling/results/ | sort | tail -n 1)
        echo $LatestSim > LatestSim.txt
        vecho "Uploading results to $BucketName..."
        aws s3 mv LatestSim.txt s3://$BucketName/ \
            >/dev/null
        aws s3 cp --recursive gatling/results/ s3://"$BucketName"/ \
            >/dev/null
    fi
}

############################################
# Run on AWS
function deleteStack() {
    vecho "Deleting stack $StackName..."
    aws cloudformation delete-stack \
        --stack-name "$StackName" \
        >/dev/null

    aws cloudformation wait stack-delete-complete \
        --stack-name "$StackName" \
        >/dev/null
}

function createStack() {
    vecho "Uploading setup files to $BucketName..."
    aws s3 cp --recursive gatling/ s3://"$BucketName"/gatling/ \
            --acl public-read \
            >/dev/null
    
    vecho "Creating stack $StackName..."
    aws cloudformation create-stack \
        --stack-name "$StackName" \
        --region "$Region" \
        --template-body file://aws-cft-ramp.yaml \
        --capabilities CAPABILITY_NAMED_IAM \
        --parameters \
        ParameterKey=BucketName,ParameterValue="$BucketName" \
        ParameterKey=SSHKeyName,ParameterValue="$SSHKeyName" \
        > /dev/null

    aws cloudformation wait stack-create-complete \
        --stack-name "$StackName" \
        >/dev/null

    StackStatus=$(aws cloudformation describe-stacks \
                      --stack-name "$StackName" \
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
    aws s3 cp LoadSimulation.scala s3://"$BucketName" \
            --acl public-read \
            >/dev/null

    vecho "Preparing simulation command..."
    UserName=$(aws iam get-user --query 'User.UserName' --output text)
    aws iam attach-user-policy \
        --user-name "$UserName" \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMFullAccess \
        >/dev/null
    InstanceId=$(aws ec2 describe-instances \
                     --query "Reservations[*].Instances[0].InstanceId[]" \
                     --filters "Name=tag-key,Values=aws:cloudformation:stack-name" "Name=tag-value,Values=ramping-load-test" \
                     "Name=instance-state-name,Values=running" \
                     --output=text)
    JavaOpts=''
    for key in "${!SimParams[@]}"; do
        JavaOpts=$JavaOpts-D$key=${SimParams[$key]}' '
    done
    
    vecho "Waiting for instance to finish setup..."
    aws ec2 wait instance-status-ok \
        --instance-ids "$InstanceId" \
        >/dev/null

    vecho "Running simulation on remote instance..."
    # aws s3 cp s3://$BucketName/LoadSimulation.scala \
    #     /gatling/user-files/simulations/
    # JAVA_OPTS="$JavaOpts" /gatling/bin/gatling.sh \
    #          -s "ramp.LoadSimulation" \
    #          -m \
    #          > /gatling/results/gatling.out
    # LatestSim=$(ls /gatling/results/ | sort | tail -n 1)
    # mv /gatling/results/gatling.out /gatling/results/$LatestSim/
    # echo $LatestSim > /gatling/LatestSim.txt
    # aws s3 cp /gatling/LatestSim.txt s3://$BucketName/
    # aws s3 cp --recursive /gatling/results/$LatestSim/ s3://$BucketName/$LatestSim/
    aws ssm send-command \
        --document-name "AWS-RunShellScript" \
        --document-version "\$DEFAULT" \
        --targets "Key=instanceids,Values=$InstanceId" \
        --parameters '{
"workingDirectory":[""],
"executionTimeout":["172800"],
"commands":[

"aws s3 cp s3://'"$BucketName"'/LoadSimulation.scala /gatling/user-files/simulations",

"JAVA_OPTS=\"'"$JavaOpts"'\" /gatling/bin/gatling.sh -s \"ramp.LoadSimulation\" -m > /gatling/results/gatling.out",

"LatestSim=$(ls /gatling/results/ | sort | tail -n 1)",
"mv /gatling/results/gatling.out /gatling/results/$LatestSim/",
"echo $LatestSim > /gatling/LatestSim.txt",
"aws s3 cp /gatling/LatestSim.txt s3://'"$BucketName"'/",

"aws s3 cp --recursive /gatling/results/$LatestSim/ s3://'"$BucketName"'/$LatestSim/"

]}' \
        --comment "console test" \
        --timeout-seconds 600 \
        --max-concurrency "50" \
        --max-errors "0" \
        --output-s3-bucket-name "$BucketName" \
        --region "$Region" \
        >/dev/null
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
# Main
fileToArray

while getopts ":b:hk:ln:prsv-:" opt; do
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
        - )
            case "${OPTARG}" in
                *)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    if [ -z "$val" ] || [[ $val == -* ]]; then
                        echo "Missing option argument for --$OPTARG"
                        exit 1
                    fi
                    SimParams[${OPTARG}]=${val};;
            esac;;
        \? )
            echo "Invalid option: -$OPTARG"
            echo "Use -h to list valid options"
            exit 1;;
        : )
            echo "Missing option argument for -$OPTARG"
            exit 1;;
    esac
done

arrayToFile
source params.txt

if [ $Local == true ]; then
    runLocally
else
    runOnAWS
fi
printSimulationResultsLocation

#Improvements:
##MID PRIORITY
###Add comments to simulation results (-rd gatling option)
###Only create-bucket & create-stack (& upload stuff) if they don't exist
###Only upload files that aren't already on bucket
###Use any region
###When uploading gatling to bucket, don't upload simulations or results
##LOW PRIORITY
###Better folder management in the bucket
###Choose which simulation file to run (-s gatling option)
###Instead of always giving the setup files public-read access, find some proper secure way to let the instance download them
###Faster stack creation (use a custom wait?)
