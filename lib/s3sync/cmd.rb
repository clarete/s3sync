# (c) 2013  Lincoln de Sousa <lincoln@clarete.li>
# (c) 2007 s3sync.net
#
# This software code is made available "AS IS" without warranties of any
# kind.  You may copy, display, modify and redistribute the software
# code either by itself or as incorporated into your code; provided that
# you do not remove any proprietary notices.  Your use of this software
# code is at your own risk and you waive any claim against the author
# with respect to your use of this software code.

require 'getoptlong'
require 'aws/s3'

require 's3sync/util'
require 'debugger'

module S3sync

  EXISTING_ACLS = [:public_read, :public_read_write, :private]

  class Cmd
    @con = nil

    def initialize(conf = conf)
      # The chain that initializes our command and find the right action
      options, command, bucket, key, file = read_info_from_args(parse_args())

      # Connecting to S3 with parameters received from the config obj
      @s3 = AWS::S3.new(
        :access_key_id     => conf[:AWS_ACCESS_KEY_ID],
        :secret_access_key => conf[:AWS_SECRET_ACCESS_KEY],
      )

      # Finding the right command to run
      case command

      when "listbuckets"
        @s3.buckets.each do |bkt|
          puts "#{bkt.name}"
        end

      when "createbucket"
        raise WrongUsage.new(nil, "You need to inform a bucket") if not bucket or bucket.empty?

        begin
          params = {}
          if acl = options['--acl']
            raise WrongUsage.new(nil, "Invalid ACL. Should be any of #{EXISTING_ACLS.join ', '}") if not EXISTING_ACLS.include? acl
            params.merge!({:acl => acl.to_sym})
          end

          @s3.buckets.create bucket, params
        rescue AWS::S3::Errors::BucketAlreadyExists => exc
          raise FailureFeedback.new("Bucket `#{bucket}' already exists")
        end

      when "deletebucket"
        raise WrongUsage.new(nil, "You need to inform a bucket") if not bucket or bucket.empty?

        # Getting the bucket
        bucket_obj = @s3.buckets[bucket]

        # Do not kill buckets with content unless explicitly asked
        if not options['--force'] and bucket_obj.objects.count > 0
          raise FailureFeedback.new("Cowardly refusing to remove non-empty bucket `#{bucket}'. Try with -f.")
        end

        begin
          bucket_obj.delete!
        rescue AWS::S3::Errors::AccessDenied => exc
          raise FailureFeedback.new("Access Denied")
        end

      when "list"
        raise WrongUsage.new(nil, "You need to inform a bucket") if not bucket or bucket.empty?
        @s3.buckets[bucket].objects.with_prefix(key || "").each do |object|
          puts "#{object.key}\t#{object.content_length}\t#{object.last_modified}"
        end

      when "delete"
        raise WrongUsage.new(nil, "You need to inform a bucket") if not bucket or bucket.empty?
        raise WrongUsage.new(nil, "You need to inform a key") if not key or key.empty?
        @s3.buckets[bucket].objects[key].delete

      when "put"
        raise WrongUsage.new(nil, "You need to inform a bucket") if not bucket or bucket.empty?
        raise WrongUsage.new(nil, "You need to inform a file") if not file or file.empty?

        # key + file name
        name = S3sync.safe_join [key, File.basename(file)]
        @s3.buckets[bucket].objects[name].write Pathname.new(file)

      when "get"
        raise WrongUsage.new(nil, "You need to inform a bucket") if not bucket or bucket.empty?
        raise WrongUsage.new(nil, "You need to inform a key") if not key or key.empty?
        raise WrongUsage.new(nil, "You need to inform a file") if not file or file.empty?

        File.open(file, 'wb') do |file|
          begin
            @s3.buckets[bucket].objects[key].read do |chunk| file.write(chunk) end
          rescue AWS::S3::Errors::NoSuchBucket
            raise FailureFeedback.new("There's no bucket named `#{bucket}'")
          rescue AWS::S3::Errors::NoSuchKey
            raise FailureFeedback.new("There's no key named `#{key}' in the bucket `#{bucket}'")
          end
        end
      else
        raise WrongUsage.new(nil, "Command `#{command}' does not exist" )
      end
    end

    def parse_args
      options = Hash.new

      args = [
        ['--help',       '-h', GetoptLong::NO_ARGUMENT],
        ['--force',      '-f', GetoptLong::NO_ARGUMENT],
        ['--acl',        '-a', GetoptLong::REQUIRED_ARGUMENT],

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
