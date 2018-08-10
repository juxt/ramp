#!/bin/bash

peakUsers=2000
totalDuration=600
url=\"http://website.staging.trustedshops.kermit.cloud\"
bucketName=juxthug-load-test
selfDestruct=false

yum install -y java-1.8.0
echo "1" > /proc/sys/net/ipv4/tcp_tw_reuse
echo "16000   64000" > /proc/sys/net/ipv4/ip_local_port_range
cd /
wget https://repo1.maven.org/maven2/io/gatling/highcharts/gatling-charts-highcharts-bundle/2.3.1/gatling-charts-highcharts-bundle-2.3.1-bundle.zip
unzip gatling-charts-highcharts-bundle-2.3.1-bundle.zip
rm -f gatling-charts-highcharts-bundle-2.3.1-bundle.zip
mv gatling-charts-highcharts-bundle-2.3.1/ gatling/
cd gatling/
rm -rf user-files/simulations/
mkdir user-files/simulations/

cat << EOF >  user-files/simulations/KermitSimulation.scala
package computerdatabase
import io.gatling.core.Predef._
import io.gatling.http.Predef._
import scala.concurrent.duration._

object Params {
  val peakUsers = $peakUsers
  val totalDuration = $totalDuration
  val url = $url}

object Get {
  val get = repeat(Params.totalDuration * 3/5, "n") {
    exec(http("Get")
      .get("/"))
      .pause(1)}}

class KermitSimulation extends Simulation {
  val httpConf = http
    .baseURL(Params.url)
    .acceptHeader("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
    .doNotTrackHeader("1")
    .acceptLanguageHeader("en-US,en;q=0.5")
    .acceptEncodingHeader("gzip, deflate")
    .userAgentHeader("Mozilla/5.0 (Macintosh; Intel Mac OS X 10.8; rv:16.0) Gecko/20100101 Firefox/16.0")
  val headers_10 = Map("Content-Type" -> "application/x-www-form-urlencoded")
  val scn = scenario("Single GET").exec(Get.get)

  setUp(scn.inject(
    // atOnceUsers(Params.peakUsers)
    rampUsers(Params.peakUsers) over (Params.totalDuration/3 seconds)
  )).protocols(httpConf)}
EOF

./bin/gatling.sh -m > results/gatling.out
aws s3 cp --recursive results/ s3://$bucketName/

if [ $selfDestruct == true ]; then
    shutdown -P now
fi
