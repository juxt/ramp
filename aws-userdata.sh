#!/bin/bash

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
