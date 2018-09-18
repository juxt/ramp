package ramp
import io.gatling.core.Predef._
import io.gatling.http.Predef._
import scala.concurrent.duration._

object Params {
  val targetUrl = System.getProperty("TargetUrl")
  val peakUsers = Integer.getInteger("PeakUsers")
  val duration = Integer.getInteger("Duration").toInt}

object Visitor {
  val frontPage = exec(http("FrontPage")
    .get("/"))}

class LoadSimulation extends Simulation {
  val httpConf = http
    .baseURL(Params.targetUrl)
    .acceptHeader("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
    .doNotTrackHeader("1")
    .acceptLanguageHeader("en-US,en;q=0.5")
    .acceptEncodingHeader("gzip, deflate")
    .userAgentHeader("Mozilla/5.0 (Macintosh; Intel Mac OS X 10.8; rv:16.0) Gecko/20100101 Firefox/16.0")
  val headers_10 = Map("Content-Type" -> "application/x-www-form-urlencoded")

  val visitor = scenario("Refresh front page")
    .repeat(Params.duration * 3/5, "n") {
      exec(Visitor.frontPage)
        .pause(1)}

  setUp(visitor.inject(
    // atOnceUsers(Params.peakUsers)
    rampUsers(Params.peakUsers) over (Params.duration/3 seconds)
  )).protocols(httpConf)}
