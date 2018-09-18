#!/bin/bash

# aws ssm send-command \
#     --document-name "AWS-RunShellScript" \
#     --document-version "\$DEFAULT" \
#     --targets "Key=instanceids,Values=$InstanceId" \
#     --parameters '{"workingDirectory":["/gatling"],
# "executionTimeout":["3600"],
# "commands":[
# "JAVA_OPTS=\"-DPeakUsers=$PeakUsers -DDuration=$Duration -DTargetUrl=$TargetUrl\" ./bin/gatling.sh -m > results/gatling.out",
# "aws s3 cp --recursive results/ s3://$BucketName/"]}' \
#     --comment "run simulation" \
#     --timeout-seconds 600 \
#     --max-concurrency "50" \
#     --max-errors "0" \
#     --output-s3-bucket-name "$BucketName" \
#     --region eu-west-1

############################################
# Utils
function vecho() {
    if [ $Verbose == true ]; then
        echo $1
    fi
}

############################################
# Run locally
function runLocally() {
    if [ ! -d "gatling" ]; then
        vecho "Downloading Gatling..."
        wget https://repo1.maven.org/maven2/io/gatling/highcharts/gatling-charts-highcharts-bundle/2.3.1/gatling-charts-highcharts-bundle-2.3.1-bundle.zip
        unzip gatling-charts-highcharts-bundle-2.3.1-bundle.zip
        rm -f gatling-charts-highcharts-bundle-2.3.1-bundle.zip
        mv gatling-charts-highcharts-bundle-2.3.1/ gatling/
        rm -rf gatling/user-files/simulations/
        mkdir gatling/user-files/simulations/
    fi

    vecho "Preparing simulation files..."
    cp LoadSimulation.scala gatling/user-files/simulations/LoadSimulation.scala
    loadParams
    
    vecho "Running simulation..."
    if [ $Verbose == true ]; then
        JAVA_OPTS="-DPeakUsers=$PeakUsers -DDuration=$Duration -DTargetUrl=$TargetUrl" gatling/bin/gatling.sh\
                 -s "LoadSimulation"
    else
        JAVA_OPTS="-DPeakUsers=$PeakUsers -DDuration=$Duration -DTargetUrl=$TargetUrl" gatling/bin/gatling.sh\
                 -s "LoadSimulation"\
                 -m\
                 > gatling/results/gatling.out
    fi

    printSimulationResultsLocation
}

############################################
# Run on AWS
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

function runOnAWS() {
    createBucket
    ###when bucket doesn't exist
    #####create bucket (Q: with what name???)
    #####set bucket permissions
    ###when stack doesn't exist
    #####upload aws-cft-ramp.yaml
    #####upload aws-userdata.sh
    #####create stack
    ####@run aws-userdata.sh
    ###upload params.txt
    ###upload LoadSimulation.scala
    ###send-command:
    ####@download params.txt
    ####@download LoadSimulation.scala
    ####@run gatling with LoadSimulation & params.txt
    ####@upload results to bucket
    ####@upload simulation results url to bucket
    ###download simulation results url
    ###print simulation results url
    ###if self-destruct
    #####destroy stack
}

############################################
# Arguments parsing
#script params:
# -b bucketname
# -h help
# -k keypair
# -l local
# -n stack name
# -p make bucket public
# -r delete old stack
# -s self-destruct
# -v verbose

#simulation params: (+ arbitrary ones)
# TargetUrl
# PeakUsers
# Duration

############################################
# Main
updateParams
if [ $Local == true ]; then
    runLocally
else
    runOnAWS
fi

#Improvements:
###Choose which simulation file to run
###Add comments to simulation results
