# MysqlReplayer

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/mysql_replayer`. To experiment with that code, run `bin/console` for an interactive prompt.

TODO: Delete this and the text above, and describe your gem

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'mysql_replayer'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install mysql_replayer

## Usage

There are a number of steps involved in actually replaying a DB here, so we'll go ahead and go through them all one at a time.

To download the logs from S3 to a local logs folder:
`aws s3 cp s3://mu-mysql-logs/march/mutual-production ./logs --recursive`
To then unzip all those files in parallel (assuming you're in the same directory as the files):
`ls | parallel "gzip -d {}"`
To merge all the individual files into one massive file:
`cat * > logs-unsorted.txt`
To sort that file (this is _very_ resource intensive so beware):
`sort --parallel 16 -S 90% logs-unsorted.txt > logs.txt`
To remove any lines in the file that are malformatted:
`cat logs.txt | grep '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z' -P > logs-groomed.txt`

If you're feeling adventurous, you _can_ chain all of these commands together. However, doing so can really screw over your sort performance (sort seems to perform drastically better when given a file than a pipe, for some reason). It does have the advantage that you can run it and come back 5 hours later to a finished file, though, rather than having to babysit the script.
`cat * | ruby join-multi-line-logs.rb | grep '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z' -P | sort --parallel 8 -S 90% > logs.txt`


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/mysql_replayer. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/mysql_replayer/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the MysqlReplayer project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/mysql_replayer/blob/master/CODE_OF_CONDUCT.md).
