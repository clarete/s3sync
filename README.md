# S3Sync

## Intro

I needed to backup some stuff once when I was in the woods. Unfortunately, I
didn't find anything easy but elegant enough to sync my stuff with Amazon S3.

S3Sync uses the [official aws sdk for ruby](https://github.com/aws/aws-sdk-ruby)
so we expect it to be stable. The most sensitive parts of the code are tested
and that only tends to get better, I'm crazy about testing code! :)

### Code maturity

This project started as a fork of the original `s3sync` command that had its
last release in 2008. After a while it became a complete rewrite which might be
considered good in a lot of cases, however, it also entails losing the maturity
that the old code used to have.

To overcome this problem, I invested time writing tests for some of the most
hairy part of the code: the sync command.

That being said, I believe there must be a couple stupid bugs around and I
highly appreciate reports and patches (specially if they come with tests).

## Installation

    $ gem install s3sync

## Usage

S3Sync's help command is pretty powerful, so you can get all the help you need
from him. He's always ready to answer your questions:

    $ s3sync help [SUBCOMMAND]

If you want to learn more about a specific command, you just need to inform
the optional [SUBCOMMAND] argument:

    $ s3sync help sync

### Managing buckets

The following commands are used to manage buckets themselves

* `s3sync listbuckets`: Show all available buckets
* `s3sync createbucket <name>`: Create a new bucket
* `s3sync deletebucket <name> [-f]`: Delete a bucket

### Managing content

* `delete <bucket>:<key>`: Delete a key from a bucket
* `list <bucket>[:prefix] [-m] [-d]`: List items filed under a given bucket
* `put <bucket>[:<key>] <file>`: Upload a file to a bucket under a certain prefix
* `get <bucket>:<key> <file>`: Retrieve an object and save to the specified file
* `url <bucket>:<key>`: Generates public urls or authenticated endpoints for the object

### The sync command

If you want to sync up an s3 folder with a local folder (both directions are
accepted), you can use the `sync` command. e.g.:

    $ s3sync sync Work/reports disc.company.com:reports/2013/08

The above line will sync the local folder `Work/reports` with the remote node
`disc.company.com:reports/2013/08`.

The most important options of this command are:

* `--exclude=EXPR`: Skip copying files that matches this pattern. (Accept Ruby REs)
* `--keep`: Keep files in the destination even if they don't exist in the source
* `--dry-run`: Do not download or exclude anything, just prints out what was planned

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

### Feedback

Reporting bugs and giving any other feedback is highly appreciated. Feel free
to [create a new issue](https://github.com/clarete/s3sync/issues/new) if you
find anything wrong or if you have any ideas to improve the ranger!


[![Bitdeli Badge](https://d2weczhvl823v0.cloudfront.net/clarete/s3sync/trend.png)](https://bitdeli.com/free "Bitdeli Badge")

