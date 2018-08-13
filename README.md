# Ramping Load Test

A tiny AWS CloudFormation stack that performs basic load testing using [Gatling](https://gatling.io/).

It will create (with ramp-up) a number of users who each connect to a URL and send a GET request every second. It will upload detailed test results to an AWS S3 bucket of your choice, and then the stack will delete itself.

It's fairly easy to adapt to more complex use cases if you provide your own .scala [Gatling simulation script](https://gatling.io/documentation/).

## Usage

You will need an S3 bucket. (Optionally, give the bucket public view permissions to view the results html as a static website.)

Go to the AWS CloudFormation console. Click "Create Stack". Upload the .yaml file. Fill in the parameters as instructed.

Alternatively, run the shell script (edit as needed) to launch the stack via AWS Command Line Interface. You will need AWS CLI [installed](https://docs.aws.amazon.com/cli/latest/userguide/installing.html) and [configured](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html).

    $ ./aws-create-stack http://www.google.com my-bucket-name
