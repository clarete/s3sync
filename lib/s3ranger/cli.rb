require 's3ranger/version'
require 's3ranger/exceptions'
require 's3ranger/sync'
require 'aws/s3'
require 'cmdparse'


module S3Ranger
  module CLI

    AVAILABLE_ACLS = [:public_read, :public_read_write, :private]

    AVAILABLE_METHODS = ['read', 'get', 'put', 'write', 'delete']

    class BaseCmd < CmdParse::Command

      @has_prefix = false

      def has_options?
        not options.instance_variables.empty?
      end

      def has_prefix?
        @has_prefix
      end

      def usage
        u = []
        u << "Usage: #{File.basename commandparser.program_name} #{name} "
        u << "[options] " if has_options?
        u << "bucket" if has_args?

        if has_prefix? == 'required'
          u << ':prefix'
        elsif has_prefix?
          u << "[:prefix]"
        end

        u.join ''
      end
    end

    class ListBuckets < BaseCmd
      def initialize
        super 'listbuckets', false, false, false

        @short_desc = "List all available buckets for your user"
      end

      def run s3, bucket, key, file, args
        s3.buckets.each do |bkt|
          puts "#{bkt.name}"
        end
      end
    end

    class CreateBucket < BaseCmd
      attr_accessor :acl

      def initialize
        super 'createbucket', false, false

        @short_desc = "Create a new bucket under your user account"

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

    class DeleteBucket < BaseCmd
      attr_accessor :force

      def initialize
        super 'deletebucket', false, false

        @short_desc = "Remove a bucket from your account"

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

    class List < BaseCmd
      attr_accessor :max_entries

      def initialize
        super 'list', false, false

        @short_desc = "List items filed under a given bucket"

        @max_entries = 0

        @has_prefix = true

        self.options = CmdParse::OptionParserWrapper.new do |opt|
          opt.on("-m", "--max-entries=NUM", "Limit the number of entries to output") {|m|
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

    class Delete < BaseCmd
      def initialize
        super 'delete', false, false

        @short_desc = "Delete a key from a bucket"

        @has_prefix = 'required'
      end

      def run s3, bucket, key, file, args
        raise WrongUsage.new(nil, "You need to inform a bucket") if not bucket
        raise WrongUsage.new(nil, "You need to inform a key") if not key
        s3.buckets[bucket].objects[key].delete
      end
    end

    class Url < BaseCmd
      attr_accessor :method
      attr_accessor :secure

      def initialize
        super 'url', false, false

        @short_desc = "Generates a url pointing to the given key"
        @method = 'read'
        @secure = true
        @expires_in = false
        @has_prefix = 'required'

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

    class Put < BaseCmd
      def initialize
        super 'put', false, false

        @short_desc = 'Upload a file to a bucket under a certain prefix'
        @has_prefix = true
      end

      def run s3, bucket, key, file, args
        raise WrongUsage.new(nil, "You need to inform a bucket") if not bucket
        raise WrongUsage.new(nil, "You need to inform a file") if not file

        name = S3Ranger.safe_join [key, File.basename(file)]
        s3.buckets[bucket].objects[name].write Pathname.new(file)
      end
    end

    class Get < BaseCmd
      def initialize
        super 'get', false, false
        @short_desc = "Retrieve an object and save to the specified file"
        @has_prefix = 'required'
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

    class Sync < BaseCmd
      attr_accessor :s3
      attr_accessor :exclude
      attr_accessor :keep
      attr_accessor :dry_run
      attr_accessor :verbose

      def initialize
        super 'sync', false, false

        @short_desc = "Synchronize an S3 and a local folder"
        @s3 = nil
        @exclude = nil
        @keep = false
        @dry_run = false
        @verbose = false

        self.options = CmdParse::OptionParserWrapper.new do |opt|
          opt.on("-x EXPR", "--exclude=EXPR", "Skip copying files that matches this pattern. (Ruby REs)") {|v|
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

      def usage
        "Usage: #{File.basename commandparser.program_name} #{name} source destination"
      end

      def description
        @description =<<END.strip

Where `source' and `description' might be either local or remote
addresses. A local address is simply a path in your local file
system. e.g:

    /tmp/notes.txt

A remote address is a combination of the `bucket` name and
an optional `prefix`:

    disc.company.com:reports/2013/08/30.html

So, a full example would be something like this

    $ #{File.basename commandparser.program_name} sync Work/reports disc.company.com:reports/2013/08

The above line will update the remote folder `reports/2013/08` with the
contents of the local folder `Work/reports`.
END
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

      cmd.main_command.short_desc = 'Tool belt for managing your S3 buckets'
      cmd.main_command.description = [] \
        << "Below you have a list of commands will allow you to manage your content" \
        << "stored in S3 buckets. For more information on each command, you can always" \
        << "use the `--help' parameter, just like this:" \
        << "" \
        << "   $ #{$0} sync --help"

      # Commands used more often
      cmd.add_command List.new
      cmd.add_command Delete.new
      cmd.add_command Url.new
      cmd.add_command Put.new
      cmd.add_command Get.new
      cmd.add_command Sync.new

      # Bucket related options
      cmd.add_command ListBuckets.new
      cmd.add_command CreateBucket.new
      cmd.add_command DeleteBucket.new

      # Built-in commands
      cmd.add_command CmdParse::HelpCommand.new
      cmd.add_command CmdParse::VersionCommand.new

      # Defining the `execute` method as a closure, so we can forward the
      # arguments needed to run the instance of the chosen command.
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
          rescue AWS::S3::Errors::Base => exc
            raise FailureFeedback.new("Error: `#{exc.message}'")
          end
        }
      end

      cmd.parse
    end

    module_function :run

  end
end
