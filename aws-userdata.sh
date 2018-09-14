#!/bin/bash

TargetUrl=$1
PeakUsers=$2
Duration=$3
BucketName=$4
SelfDestruct=$5
StackName=$6
Region=$7

yum remove -y java-1.7.0-openjdk
yum install -y java-1.8.0
cd /
wget https://repo1.maven.org/maven2/io/gatling/highcharts/gatling-charts-highcharts-bundle/2.3.1/gatling-charts-highcharts-bundle-2.3.1-bundle.zip
unzip gatling-charts-highcharts-bundle-2.3.1-bundle.zip
rm -f gatling-charts-highcharts-bundle-2.3.1-bundle.zip
mv gatling-charts-highcharts-bundle-2.3.1/ gatling/
cd gatling/
rm -rf user-files/simulations/
mkdir user-files/simulations/
wget -P /gatling/user-files/simulations/ http://$BucketName.s3.amazonaws.com/LoadSimulation.scala

JAVA_OPTS="-DPeakUsers=$PeakUsers -DDuration=$Duration -DTargetUrl=$TargetUrl" ./bin/gatling.sh -m > results/gatling.out
aws s3 cp --recursive results/ s3://$BucketName/

if [ $SelfDestruct == true ]; then
    aws cloudformation delete-stack --stack-name $StackName --region $Region
fi
