require 's3ranger/exceptions'
require 's3ranger/sync'
require 'aws/s3'
require 'cmdparse'


module S3Ranger
  module CLI

    AVAILABLE_ACLS = [:public_read, :public_read_write, :private]

    AVAILABLE_METHODS = ['read', 'get', 'put', 'write', 'delete']

    class ListBuckets < CmdParse::Command
      def initialize
        super 'listbuckets', false, false, false
      end

      def run s3, bucket, key, file, args
        s3.buckets.each do |bkt|
          puts "#{bkt.name}"
        end
      end
    end

    class CreateBucket < CmdParse::Command
      attr_accessor :acl

      def initialize
        super 'createbucket', false, false

        @acl = nil

        self.options = CmdParse::OptionParserWrapper.new do |opt|
          opt.on("-a", "--acl=ACL", "Options: #{AVAILABLE_ACLS.join ', '}") {|acl|
            @acl = acl.to_sym
          }
        end
      end

      def run s3, bucket, key, file, args
        raise WrongUsage.new(nil, "You need to inform a bucket") if not bucket

        begin
          params = {}
          if @acl
            raise WrongUsage.new(nil, "Invalid ACL `#{@acl}'. Should be any of #{AVAILABLE_ACLS.join ', '}") if not AVAILABLE_ACLS.include? @acl
            params.merge!({:acl => @acl})
          end

          s3.buckets.create bucket, params
        rescue AWS::S3::Errors::BucketAlreadyExists => exc
          raise FailureFeedback.new("Bucket `#{bucket}' already exists")
        end
      end
    end

    class DeleteBucket < CmdParse::Command
      attr_accessor :force

      def initialize
        super 'deletebucket', false, false

        @force = false

        self.options = CmdParse::OptionParserWrapper.new do |opt|
          opt.on("-f", "--force", "Clean the bucket then deletes it") {|f|
            @force = f
          }
        end
      end

      def run s3, bucket, key, file, args
        raise WrongUsage.new(nil, "You need to inform a bucket") if not bucket

        # Getting the bucket
        bucket_obj = s3.buckets[bucket]

        # Do not kill buckets with content unless explicitly asked
        if not @force and bucket_obj.objects.count > 0
          raise FailureFeedback.new("Cowardly refusing to remove non-empty bucket `#{bucket}'. Try with -f.")
        end

        bucket_obj.delete!
      end
    end

    class List < CmdParse::Command
      attr_accessor :max_entries

      def initialize
        super 'list', false, false

        @max_entries = 0

        self.options = CmdParse::OptionParserWrapper.new do |opt|
          opt.on("-m", "--max-entries", "Limit the number of entries to output") {|m|
            @max_entries = m
          }
        end
      end

      def run s3, bucket, key, file, args
        raise WrongUsage.new(nil, "You need to inform a bucket") if not bucket

        collection = s3.buckets[bucket].objects.with_prefix(key || "")

        if @max_entries > 0
          collection = collection.page(:per_page => max = @max_entries)
        end

        collection.each {|object|
          puts "#{object.key}\t#{object.content_length}\t#{object.last_modified}"
        }
      end
    end

    class Delete < CmdParse::Command
      def initialize
        super 'delete', false, false, false
      end

      def run s3, bucket, key, file, args
        raise WrongUsage.new(nil, "You need to inform a bucket") if not bucket
        raise WrongUsage.new(nil, "You need to inform a key") if not key
        s3.buckets[bucket].objects[key].delete
      end
    end

    class Url < CmdParse::Command
      attr_accessor :method
      attr_accessor :secure

      def initialize
        super 'url', false, false

        @method = 'read'
        @secure = true
        @expires_in = false

        self.options = CmdParse::OptionParserWrapper.new do |opt|
          opt.on("-m", "--method", "Options: #{AVAILABLE_METHODS.join ', '}") {|m|
            @method = m
          }

          opt.on("--no-ssl", "Generate an HTTP link, no HTTPS") {
            @secure = false
          }

          opt.on("--expires-in=EXPR", "How long the link takes to expire. Format: <# of seconds> | [#d|#h|#m|#s]") { |expr|
            val = 0
            expr.scan /(\d+\w)/ do |track|
              _, num, what = /(\d+)(\w)/.match(track[0]).to_a
              num = num.to_i

              case what
              when "d"; val += num * 86400
              when "h"; val += num * 3600
              when "m"; val += num * 60
              when "s"; val += num
              end
            end
            @expires_in = val > 0 ? val : expr.to_i
          }
        end
      end

      def run s3, bucket, key, file, args
        raise WrongUsage.new(nil, "You need to inform a bucket") if not bucket
        raise WrongUsage.new(nil, "You need to inform a key") if not key
        raise WrongUsage.new(nil, "Unknown method #{@method}") unless AVAILABLE_METHODS.include? @method

        opts = {}
        opts.merge!({:secure => @secure})
        opts.merge!({:expires => @expires_in}) if @expires_in
        puts (s3.buckets[bucket].objects[key].url_for @method.to_sym, opts).to_s
      end
    end

    class Put < CmdParse::Command
      def initialize
        super 'put', false, false
      end

      def run s3, bucket, key, file, args
        raise WrongUsage.new(nil, "You need to inform a bucket") if not bucket
        raise WrongUsage.new(nil, "You need to inform a file") if not file

        name = S3Ranger.safe_join [key, File.basename(file)]
        s3.buckets[bucket].objects[name].write Pathname.new(file)
      end
    end

    class Get < CmdParse::Command
      def initialize
        super 'get', false, false
      end

      def run s3, bucket, key, file, args
        raise WrongUsage.new(nil, "You need to inform a bucket") if not bucket
        raise WrongUsage.new(nil, "You need to inform a key") if not key
        raise WrongUsage.new(nil, "You need to inform a file") if not file

        # Saving the content to be downloaded to the current directory if the
        # destination is a directory
        path = File.absolute_path file
        path = S3Ranger.safe_join [path, File.basename(key)] if File.directory? path
        File.open(path, 'wb') do |f|
          s3.buckets[bucket].objects[key].read do |chunk| f.write(chunk) end
        end
      end
    end

    class Sync < CmdParse::Command
      attr_accessor :s3
      attr_accessor :exclude
      attr_accessor :keep
      attr_accessor :dry_run
      attr_accessor :verbose

      def initialize
        super 'sync', false, false

        @s3 = nil
        @exclude = nil
        @keep = false
        @dry_run = false
        @verbose = false

        self.options = CmdParse::OptionParserWrapper.new do |opt|
          opt.on("-x EXPR", "--exclude=EXPR", "") {|v|
            @exclude = v
          }

          opt.on("-k", "--keep", "Keep files even if they don't exist in source") {
            @keep = true
          }

          opt.on("-d", "--dry-run", "Do not download or exclude anything, just show what was planned. Implies `verbose`.") {
            @dry_run = true
            @verbose = true
          }

          opt.on("-v", "--verbose", "Show file names") {
            @verbose = true
          }
        end
      end

      def run s3, bucket, key, file, args
        @s3 = s3
        cmd = SyncCommand.new self, *args
        cmd.run
      end
    end

    def run conf
      cmd = CmdParse::CommandParser.new true
      cmd.program_version = S3Ranger::VERSION
      cmd.options = CmdParse::OptionParserWrapper.new do |opt|
        opt.separator "Global options:"
      end

      # Adding the commands we declared above
      cmd.add_command ListBuckets.new
      cmd.add_command CreateBucket.new
      cmd.add_command DeleteBucket.new
      cmd.add_command List.new
      cmd.add_command Delete.new
      cmd.add_command Url.new
      cmd.add_command Put.new
      cmd.add_command Get.new
      cmd.add_command Sync.new

      # Built-in commands
      cmd.add_command CmdParse::HelpCommand.new
      cmd.add_command CmdParse::VersionCommand.new

      CmdParse::Command.class_eval do
        define_method :execute, lambda { |args|

          # Connecting to amazon
          s3 = AWS::S3.new(
            :access_key_id => conf[:AWS_ACCESS_KEY_ID],
            :secret_access_key => conf[:AWS_SECRET_ACCESS_KEY],
          )

          # From the command line
          key, file = args

          # Parsing the bucket name
          bucket = nil
          bucket, key = key.split(':') if key

          # Running our custom method inside of the command class, taking care
          # of the common errors here, saving duplications in each command;
          begin
            run s3, bucket, key, file, args
          rescue AWS::S3::Errors::AccessDenied
            raise FailureFeedback.new("Access Denied")
          rescue AWS::S3::Errors::NoSuchBucket
            raise FailureFeedback.new("There's no bucket named `#{bucket}'")
          rescue AWS::S3::Errors::NoSuchKey
            raise FailureFeedback.new("There's no key named `#{key}' in the bucket `#{bucket}'")
          end
        }
      end

      cmd.parse
    end

    module_function :run

  end
end
