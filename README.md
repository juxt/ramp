# ramp - Ramping load test

A tiny AWS CloudFormation stack that performs basic load testing using [Gatling](https://gatling.io/).

It will create (with ramp-up) a number of users who each connect to a URL and send a GET request every second. It will upload detailed test results to an AWS S3 bucket of your choice, and then the stack will delete itself.

It's fairly easy to adapt to more complex use cases if you provide your own .scala [Gatling simulation script](https://gatling.io/documentation/).

## Usage

. [Install](https://docs.aws.amazon.com/cli/latest/userguide/installing.html) and [configure](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html) the Amazon Command Line Interface.
. Create an S3 bucket (if you don't already have one).
.. Optionally, [give the bucket public view permissions](https://docs.aws.amazon.com/AmazonS3/latest/dev/WebsiteAccessPermissionsReqd.html) to view the results html as a static website.
. Run the `aws-create-stack.sh` script with your target url and bucket name as parameters.

    $ ./aws-create-stack.sh http://www.google.com my-bucket-name

You can edit that script to change the duration and max number of concurrent users. A better command line interface is coming Extremely Soon.
