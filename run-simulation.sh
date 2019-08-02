#!/bin/bash

RandUID=$(uuidgen | cut -c -8)

BucketName=ramp-load-test-$RandUID
BucketPublicRead=false
Local=false
ReplaceStack=false
SelfDestruct=false
RemoveBucket=false
StackName=ramping-load-test-$RandUID
SSHKeyName=
Region=
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
  -d            Delete bucket once testing is complete\n\
  -v            Verbose: prints details of the stack launch\n\
  --<string1> <string2> Pass the argument string1, with value string2, to the scala simulation script. The default script's supported parameters are TargetUrl, PeakUsers, and Duration."
}

############################################
# Utils
function vecho() {
    if [ $Verbose == true ]; then
        echo "$1"
    fi
}

function createBucket() {
    BucketExists=$(aws s3api head-bucket --bucket "$BucketName" 2>&1)
    if [ ! -z "$BucketExists" ]; then
        vecho "Creating bucket $BucketName..."
        aws s3api create-bucket \
            --bucket "$BucketName" \
            --region "$Region" \
            --create-bucket-configuration \
            LocationConstraint="$Region" \
            >/dev/null
    fi
    
    if [ $BucketPublicRead == true ]; then
        aws s3api put-bucket-policy \
            --bucket "$BucketName" \
            --policy "{ \"Version\":\"2012-10-17\", \"Statement\":[{ \"Sid\":\"PublicReadGetObject\", \"Effect\":\"Allow\", \"Principal\": \"*\", \"Action\":[\"s3:GetObject\"], \"Resource\":[\"arn:aws:s3:::$BucketName/*\" ] } ] }" \
            >/dev/null
    fi
}

function printSimulationResultsLocation() {
    if [ $UseBucket == true ]; then
        aws s3api wait object-exists \
            --bucket "$BucketName" \
            --key NewSim.txt \
            >/dev/null
        aws s3 mv s3://"$BucketName"/NewSim.txt NewSim.txt \
            >/dev/null
        NewSim=$(<NewSim.txt)
        rm -f NewSim.txt
        if [ "$NewSim" == "error" ] && [ $Local == false ]; then
            echo "Simulation failed!"
            vecho "For debug purposes, command outputs should be available on bucket $BucketName in a folder whose name is a UUID (a jumble of letters, dashes & numbers)"
        else
			echo 'Downloading results into results-'$RandUID'...'
			aws s3 sync --quiet s3://"$BucketName"/$NewSim results-$RandUID
			aws s3 cp --quiet s3://"$BucketName"/gatling.out results-$RandUID/
			aws s3 cp --quiet s3://"$BucketName"/gatling.err results-$RandUID/
        fi
    else
        if [ $Verbose == false ]; then
            #If Verbose, gatling itself will print the report path
            NewSim=$(ls gatling/results/ | sort | tail -n 1)
            echo "Simulation report: $PWD/gatling/results/$NewSim/index.html"
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
        echo "$key"="${SimParams[$key]}" >> params.txt
    done
}

############################################
# Run locally
function runLocally() {
    vecho "Running simulation locally..."
    cp LoadSimulation.scala gatling/user-files/simulations/LoadSimulation.scala
    JavaOpts=''
    for key in "${!SimParams[@]}"; do
        JavaOpts=$JavaOpts-D$key=${SimParams[$key]}' '
    done
    if [ $Verbose == true ]; then
        JAVA_OPTS="$JavaOpts" ./gatling/bin/gatling.sh \
                 -s "ramp.LoadSimulation"
    else
        JAVA_OPTS="$JavaOpts" ./gatling/bin/gatling.sh \
                 -s "ramp.LoadSimulation" \
                 -m \
                 > gatling/results/gatling.out
    fi

    if [ $UseBucket == true ]; then
        Region=$(aws configure get region)
        createBucket
        NewSim=$(ls gatling/results/ | sort | tail -n 1)
        echo "$NewSim" > NewSim.txt
        vecho "Uploading results to bucket $BucketName..."
        aws s3 mv NewSim.txt s3://"$BucketName"/ \
            >/dev/null
        aws s3 sync gatling/results/"$NewSim"/ s3://"$BucketName"/"$NewSim" \
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

function deleteBucket() {
    vecho "Deleting Bucket $BucketName..."
	aws s3 rb s3://$BucketName --force >/dev/null
}

function createStack() {
    vecho "Uploading setup files to bucket $BucketName..."
    aws s3 sync gatling/ s3://"$BucketName"/gatling/ \
        --exclude "gatling/results/*" \
        --exclude "gatling/user-files/*" \
        --acl public-read \
        >/dev/null
    aws s3 cp amilookup.zip s3://"$BucketName"/ \
        >/dev/null
    
    vecho "Creating stack $StackName..."
	sed -i -r 's/LoadTestSG[0-9]*/LoadTestSG'$RANDOM'/g' aws-cft-ramp.yaml
    aws cloudformation create-stack \
	    --disable-rollback \
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
    if [ "$StackStatus" != CREATE_COMPLETE ]; then
        echo "Stack creation failed!"
		aws cloudformation describe-stack-events --stack-name $StackName | egrep "(EventId|ResourceStatus|ResourceStatusReason)"
		deleteStack
        exit 1
    fi
}

function runRemoteSimulation() {
    UseBucket=true
    vecho "Uploading simulation files to bucket $BucketName..."
    aws s3 cp LoadSimulation.scala s3://"$BucketName" \
        --acl public-read \
        >/dev/null

    UserName=$(aws iam get-user --query 'User.UserName' --output text)
    aws iam attach-user-policy \
        --user-name "$UserName" \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMFullAccess \
        >/dev/null
    InstanceId=$(aws ec2 describe-instances \
                     --query "Reservations[*].Instances[0].InstanceId[]" \
                     --filters "Name=tag-key,Values=aws:cloudformation:stack-name" "Name=tag-value,Values=$StackName" \
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
    # With $BucketName and $JavaOpts from the outside:
    # aws s3 cp s3://$BucketName/LoadSimulation.scala /gatling/user-files/simulations
    # LastSim=$(ls /gatling/results/ | sort | tail -n 1)
    # JAVA_OPTS="$JavaOpts" /gatling/bin/gatling.sh \
    #          -s "ramp.LoadSimulation" \
    #          -m > /gatling/results/gatling.out
    # NewSim=$(ls /gatling/results/ | sort | tail -n 1)
    # if [ "$LastSim" == "$NewSim" ]; then
    #     echo "error" > /gatling/NewSim.txt
    # else
    #     mv /gatling/results/gatling.out /gatling/results/$NewSim/
    #     aws s3 sync /gatling/results/$NewSim/ s3://$BucketName/$NewSim/
    #     echo $NewSim > /gatling/NewSim.txt
    # fi
    # aws s3 mv /gatling/NewSim.txt s3://$BucketName/
	COMMANDID=$(
    aws ssm send-command \
        --document-name "AWS-RunShellScript" \
        --document-version "\$DEFAULT" \
        --targets "Key=instanceids,Values=$InstanceId" \
        --parameters '{
"workingDirectory":[""],
"executionTimeout":["172800"],
"commands":[

"aws s3 cp s3://'"$BucketName"'/LoadSimulation.scala /gatling/user-files/simulations",
"LastSim=$(ls /gatling/results/ | sort | tail -n 1)",
"JAVA_OPTS=\"'"$JavaOpts"'\" /gatling/bin/gatling.sh \\",
" -s \"ramp.LoadSimulation\" \\",
" -m > /gatling/results/gatling.out 2> /gatling/results/gatling.err",
"NewSim=$(ls /gatling/results/ | sort | tail -n 1)",
"if [ \"$LastSim\" == \"$NewSim\" ]; then",
" echo \"error\" > /gatling/NewSim.txt",
"else",
" mv /gatling/results/gatling.out /gatling/results/$NewSim/",
" aws s3 sync /gatling/results/$NewSim/ s3://'"$BucketName"'/$NewSim/",
" aws s3 cp /gatling/results/gatling.out s3://'"$BucketName"'/",
" aws s3 cp /gatling/results/gatling.err s3://'"$BucketName"'/",
" echo $NewSim > /gatling/NewSim.txt",
"fi",
"aws s3 mv /gatling/NewSim.txt s3://'"$BucketName"'/"
]}' \
        --comment "load test command" \
        --timeout-seconds 600 \
        --max-concurrency "50" \
        --max-errors "0" \
        --output-s3-bucket-name "$BucketName" \
        --region "$Region" \
		--query Command.CommandId \
        --output text 2>&1
		)

	while true; do
        finished=0
        STATUS=$( aws ssm get-command-invocation --command-id $COMMANDID --instance-id $InstanceId --query Status --output text | tr '[A-Z]' '[a-z]' )
        NOW=$( date +%Y-%m-%dT%H:%M:%S%z )
        echo $NOW $instance: $STATUS
		[ "$STATUS" == "success" ] && break
        sleep 60
    done
}

function runOnAWS() {
    Region=$(aws configure get region)
    if [ $ReplaceStack == true ]; then
        deleteStack
    fi
    createBucket
    createStack
    runRemoteSimulation
}

############################################
# Main
fileToArray

while getopts ":b:hk:ln:prsdv-:" opt; do
    case "$opt" in
        b )
            BucketName="$OPTARG"
            UseBucket=true;;
        h )
            usage
            exit 0;;
        k )
            SSHKeyName="$OPTARG";;
        l )
            Local=true;;
        n )
            StackName="$OPTARG";;
        p )
            BucketPublicRead=true;;
        r )
            ReplaceStack=true;;
        s )
            SelfDestruct=true;;
        d )
            RemoveBucket=true;;
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
if [ $SelfDestruct == true ]; then
    deleteStack
fi
if [ $RemoveBucket == true ]; then
    deleteBucket
fi

#Improvements:
##HIGH PRIORITY
###Add comment to gatling report (-rd)
##MID PRIORITY
###Only create-stack if it doesn't exist
###Better folder management in the bucket
###Don't repeat yourself
##LOW PRIORITY
###Choose which simulation file to run (-s gatling option)
###Instead of always giving the setup files public-read access, find some proper secure way to let the instance download them
###Faster stack creation (use a custom wait?)
###Fix the silly "latestSim" file dance
