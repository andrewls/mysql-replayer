# MysqlReplayer

This gem can be used to replay a mysql log file against a different MySQL database, allowing for performance testing of various configurations.

## Installation
    gem install mysql_replayer

## Usage
There are a number of steps involved in actually replaying a DB here, so we'll go ahead and go through them all one at a time.

First is that you'll need to collect some logs to replay. Once you have these, you can [use the AWS console to export the logs from cloudwatch to S3](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/S3ExportTasksConsole.html). Make sure you also take a snapshot from around the same time these logs started so that you can replay the logs against that snapshot in the future.

To download the logs from S3 to a local logs folder, use the aws cli, as demonstrated by the command

    aws s3 cp s3://mu-mysql-logs/march/mutual-production ./logs --recursive  
To then unzip all those files in parallel (assuming you're in the same directory as the files):

    ls | parallel "gzip -d {}"
To merge all the individual files into one massive file:

    cat * > logs-unsorted.txt
To sort that file (this is _very_ resource intensive so beware):

    sort --parallel 16 -S 90% logs-unsorted.txt > logs.txt
To remove any lines in the file that are malformatted:

    cat logs.txt | grep '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z' -P > logs-groomed.txt

If you're feeling adventurous, you _can_ chain all of these commands together. However, doing so can really screw over your sort performance (sort seems to perform drastically better when given a file than a pipe, for some reason). It does have the advantage that you can run it and come back 5 hours later to a finished file, though, rather than having to babysit the script.

    cat * | ruby join-multi-line-logs.rb | grep '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z' -P | sort --parallel 8 -S 90% > logs.txt

## Preparing to run the script

**Make sure you run this part on the machine you intend to execute the test from (likely an EC2 instance), not your local machine**

After checking out the repo, run `bin/setup` to install dependencies. Depending on what libraries you already have on your system, you may need to install a few dependencies for this to work. Off the top of my head, I know you need the mysql client libraries installed. You may run into other dependencies.

## Actually running a test
The following steps can be followed to run a test of a configuration from start to finish:
1. Create a new database instance in RDS from the snapshot you created during setup
2. Either create a new EC2 instance in the same VPC as your DB, or use one of the existing ones. Make sure that whatever instance you use has enough network bandwidth to not be a bottleneck on the test and enough CPU / RAM to keep up with the demands of firing off requests from 400+ DB connections at once.
3. Once all dependencies are installed and ready to go, start up the replay script using `bin/replay`. It will print a help message describing all of its different command-line options, which you can then use to configure the test the way that you want. (One of the main things that you might want to configure that does _not_ have a command line flag associated with it is how many reader threads and writer threads there are. You can change this setting by editing the constants `READER_THREADS` and `WRITER_THREADS` near the top of the `lib/mysql_replayer/executor.rb` file).
4. Wait for however long is needed for the test to finish.
5. Collect whatever metrics you want from the DB about how the test performed.
6. Copy the logs from the EC2 instance. They'll be located in the base folder of this project, in a file called query-metrics.txt. Feed this file as input to the `process_metrics.py` python script located in this repo. It will return a JSON object representing the results of the test run. You can then feed this info to the `graph-metric-results.py` script, and it will generate some nice graphs that are relatively easy to reason about for the metrics collected from the logs.
7. Clean up the EC2 instance and DB instance once you're sure you've collected all the data you want from them.
8. That's it, you're done.
