require 's3ranger/exceptions'
require 's3ranger/sync'
require 'aws/s3'


module Commands

  include S3Ranger

  AVAILABLE_ACLS = [:public_read, :public_read_write, :private]

  AVAILABLE_METHODS = ['read', 'get', 'put', 'write', 'delete']

  def Commands._cmd_listbuckets args
    args[:s3].buckets.each do |bkt|
      puts "#{bkt.name}"
    end
  end

  def Commands._cmd_createbucket args
    raise WrongUsage.new(nil, "You need to inform a bucket") if not args[:bucket]

    begin
      params = {}
      if acl = args[:options]['--acl']
        raise WrongUsage.new(nil, "Invalid ACL. Should be any of #{EXISTING_ACLS.join ', '}") if not AVAILABLE_ACLS.include? acl
        params.merge!({:acl => acl.to_sym})
      end

      args[:s3].buckets.create args[:bucket], params
    rescue AWS::S3::Errors::BucketAlreadyExists => exc
      raise FailureFeedback.new("Bucket `#{bucket}' already exists")
    end
  end

  def Commands._cmd_deletebucket args
    raise WrongUsage.new(nil, "You need to inform a bucket") if not args[:bucket]

    # Getting the bucket
    bucket_obj = args[:s3].buckets[args[:bucket]]

    # Do not kill buckets with content unless explicitly asked
    if not args[:options]['--force'] and bucket_obj.objects.count > 0
      raise FailureFeedback.new("Cowardly refusing to remove non-empty bucket `#{bucket}'. Try with -f.")
    end

    begin
      bucket_obj.delete!
    rescue AWS::S3::Errors::AccessDenied => exc
      raise FailureFeedback.new("Access Denied")
    end
  end

  def Commands._cmd_list args
    raise WrongUsage.new(nil, "You need to inform a bucket") if not args[:bucket]

    collection = args[:s3].buckets[args[:bucket]].objects.with_prefix(args[:key] || "")

    if max = args[:options]["--max-entries"]
      collection = collection.page(:per_page => max)
    end

    collection.each {|object|
      puts "#{object.key}\t#{object.content_length}\t#{object.last_modified}"
    }
  end

  def Commands._cmd_delete args
    raise WrongUsage.new(nil, "You need to inform a bucket") if not args[:bucket]
    raise WrongUsage.new(nil, "You need to inform a key") if not args[:key]
    args[:s3].buckets[args[:bucket]].objects[args[:key]].delete
  end

  def Commands._cmd_url args
    raise WrongUsage.new(nil, "You need to inform a bucket") if not args[:bucket]
    raise WrongUsage.new(nil, "You need to inform a key") if not args[:key]

    method = args[:options]['--method'] || 'read'
    raise WrongUsage.new(nil, "") unless AVAILABLE_METHODS.include? method

    opts = {}
    opts.merge!({:secure => args[:options]["--no-ssl"].nil?})
    opts.merge!({:expires => args[:options]["--expires-in"]}) if args[:options]["--expires-in"]
    p (args[:s3].buckets[args[:bucket]].objects[args[:key]].url_for method.to_sym, opts).to_s
  end

  def Commands._cmd_put args
    raise WrongUsage.new(nil, "You need to inform a bucket") if not args[:bucket]
    raise WrongUsage.new(nil, "You need to inform a file") if not args[:file]

    # key + file name
    name = S3Ranger.safe_join [args[:key], File.basename(args[:file])]
    args[:s3].buckets[args[:bucket]].objects[name].write Pathname.new(args[:file])
  end

  def Commands._cmd_get args
    raise WrongUsage.new(nil, "You need to inform a bucket") if not args[:bucket]
    raise WrongUsage.new(nil, "You need to inform a key") if not args[:key]
    raise WrongUsage.new(nil, "You need to inform a file") if not args[:file]

    # Saving the content to be downloaded to the current directory if the
    # destination is a directory
    path = File.absolute_path args[:file]
    path = S3Ranger.safe_join [path, File.basename(args[:key])] if File.directory? path

    File.open(path, 'wb') do |f|
      begin
        args[:s3].buckets[args[:bucket]].objects[args[:key]].read do |chunk| f.write(chunk) end
      rescue AWS::S3::Errors::NoSuchBucket
        raise FailureFeedback.new("There's no bucket named `#{args[:bucket]}'")
      rescue AWS::S3::Errors::NoSuchKey
        raise FailureFeedback.new("There's no key named `#{args[:key]}' in the bucket `#{args[:bucket]}'")
      end
    end
  end

  def Commands._cmd_sync args
    cmd = SyncCommand.new args, *ARGV
    cmd.run
  end
end
