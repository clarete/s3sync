# This software code is made available "AS IS" without warranties of any
# kind.  You may copy, display, modify and redistribute the software
# code either by itself or as incorporated into your code; provided that
# you do not remove any proprietary notices.  Your use of this software
# code is at your own risk and you waive any claim against the author
# with respect to your use of this software code.
# (c) 2007 s3sync.net
#

require 'getoptlong'
require 's3sync/exceptions'
require 's3sync/config'
require 'aws/s3'

require 'rubygems'
require 'debugger'

VERSION = '2.0.0'


module S3sync

  class Cmd

    def initialize(conf = conf)
      # The chain that initializes our command and find the right action
      options, command, bucket, key, file = read_info_from_args(parse_args())

      # Connecting to S3 with parameters received from the config obj
      conn = AWS::S3::Base.establish_connection!(
        :server            => conf[:AWS_S3_HOST] || 's3.amazon.com',
        :use_ssl           => true,
        :access_key_id     => conf[:AWS_ACCESS_KEY_ID],
        :secret_access_key => conf[:AWS_SECRET_ACCESS_KEY],
      )

      # Finding the right command to run
      case command

      when "listbuckets"
        AWS::S3::Service.buckets.each do |bkt|
          puts "#{bkt.name}, #{bkt.creation_date}"
        end

      when "createbucket"
        raise WrongUsage.new(nil, "You need to inform a bucket") if not bucket or bucket.empty?
        AWS::S3::Bucket.create bucket

      when "deletebucket"
        raise WrongUsage.new(nil, "You need to inform a bucket") if not bucket or bucket.empty?
        AWS::S3::Bucket.delete bucket

      when "list"
        raise WrongUsage.new(nil, "You need to inform a bucket") if not bucket or bucket.empty?
        bucket_obj = AWS::S3::Bucket.find bucket
        bucket_obj.each do |object|
          puts "#{object.key}\t#{object.about['content-length']}\t#{object.about['last-modified']}"
        end

      when "delete"
        raise WrongUsage.new(nil, "You need to inform a bucket") if not bucket or bucket.empty?
        raise WrongUsage.new(nil, "You need to inform a key") if not key or key.empty?
        AWS::S3::S3Object.delete key, bucket

      when "put"
        raise WrongUsage.new(nil, "You need to inform a bucket") if not bucket or bucket.empty?
        raise WrongUsage.new(nil, "You need to inform a key") if not key or key.empty?
        raise WrongUsage.new(nil, "You need to inform a file") if not file or file.empty?

        # key + file name
        name = File.join(key, File.basename(file))
        AWS::S3::S3Object.store name, open(file), bucket

      when "get"
        raise WrongUsage.new(nil, "You need to inform a bucket") if not bucket or bucket.empty?
        raise WrongUsage.new(nil, "You need to inform a key") if not key or key.empty?
        raise WrongUsage.new(nil, "You need to inform a file") if not file or file.empty?

        # Requesting the data
        content = AWS::S3::S3Object.value key, bucket

        # Not creating the file until we have the data, so we don't create
        # trash
        file = File.open file, 'wb'
        file.write content
        file.close

      else
        raise WrongUsage.new(nil, "Command `#{command}' does not exist" )
      end
    end

    def parse_args
      options = Hash.new

      args = [
        ['--help',       '-h', GetoptLong::NO_ARGUMENT],
        ['--ssl',        '-s', GetoptLong::NO_ARGUMENT],
        ['--verbose',    '-v', GetoptLong::NO_ARGUMENT],
        ['--dryrun',     '-n', GetoptLong::NO_ARGUMENT],
        ['--debug',      '-d', GetoptLong::NO_ARGUMENT],
        ['--progress',         GetoptLong::NO_ARGUMENT],
        ['--expires-in',       GetoptLong::REQUIRED_ARGUMENT],
      ]

      begin
        GetoptLong.new(*args).each {|opt, arg| options[opt] = (arg || true)}
      rescue StandardError
        raise WrongUsage
      end

      # Let's just show the help to the user
      raise WrongUsage.new(0, nil) if options['--help']

      # Returning the options to the next level
      options
    end

    def read_info_from_args(options)
      # Setting up boolean values
      options['--verbose'] = true if options['--dryrun'] or options['--debug'] or options['--progress']
      options['--ssl'] = true if options['--ssl'] # change from "" to true to appease s3 port chooser

      # Parsing expre date
      if options['--expires-in'] =~ /d|h|m|s/

        val = 0

        options['--expires-in'].scan(/(\d+\w)/) do |track|
          _, num, what = /(\d+)(\w)/.match(track[0]).to_a
          num = num.to_i

          case what
          when "d"; val += num * 86400
          when "h"; val += num * 3600
          when "m"; val += num * 60
          when "s"; val += num
          end
        end

        options['--expires-in'] = val
      end

      # Reading what to do from the user
      bucket = nil
      command, key, file = ARGV

      # We can't proceed from here!
      raise WrongUsage.new(nil, "Need a command (eg.: `list', `createbucket', etc)") if not command

      # Parsing the bucket name
      bucket, key = key.split(':') if key

      # Returning things we need in the next level
      [options, command, bucket, key, file]
    end
  end
end
