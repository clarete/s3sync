require 's3sync/exceptions'
require 'aws/s3'

module Commands

  include S3sync

  AVAILABLE_ACLS = [:public_read, :public_read_write, :private]

  def Commands._cmd_listbuckets args
    args[:s3].buckets.each do |bkt|
      puts "#{bkt.name}"
    end
  end

  def Commands._cmd_createbucket args
    raise WrongUsage.new(nil, "You need to inform a bucket") if not args[:bucket] or args[:bucket].empty?

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
    raise WrongUsage.new(nil, "You need to inform a bucket") if not args[:bucket] or args[:bucket].empty?

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
    raise WrongUsage.new(nil, "You need to inform a bucket") if not args[:bucket] or args[:bucket].empty?
    args[:s3].buckets[args[:bucket]].objects.with_prefix(args[:key] || "").each do |object|
      puts "#{object.key}\t#{object.content_length}\t#{object.last_modified}"
    end
  end

  def Commands._cmd_delete args
    raise WrongUsage.new(nil, "You need to inform a bucket") if not args[:bucket] or args[:bucket].empty?
    raise WrongUsage.new(nil, "You need to inform a key") if not args[:key] or args[:key].empty?
    args[:s3].buckets[args[:bucket]].objects[args[:key]].delete
  end

  def Commands._cmd_put args
    raise WrongUsage.new(nil, "You need to inform a bucket") if not args[:bucket] or args[:bucket].empty?
    raise WrongUsage.new(nil, "You need to inform a file") if not args[:file] or args[:file].empty?

    # key + file name
    name = S3sync.safe_join [args[:key], File.basename(args[:file])]
    args[:s3].buckets[args[:bucket]].objects[name].write Pathname.new(args[:file])
  end

  def Commands._cmd_get args
    raise WrongUsage.new(nil, "You need to inform a bucket") if not args[:bucket] or args[:bucket].empty?
    raise WrongUsage.new(nil, "You need to inform a key") if not args[:key] or args[:key].empty?
    raise WrongUsage.new(nil, "You need to inform a file") if not args[:file] or args[:file].empty?

    # Saving the content to be downloaded to the current directory if the
    # destination is a directory
    path = File.absolute_path args[:file]
    path = S3sync.safe_join [path, File.basename(args[:key])] if File.directory? path

    File.open(path, 'wb') do |f|
      begin
        args[:s3].buckets[args[:bucket]].objects[args[:key]].read do |chunk| f.write(chunk) end
      rescue AWS::S3::Errors::NoSuchBucket
        raise FailureFeedback.new("There's no bucket named `#{bucket}'")
      rescue AWS::S3::Errors::NoSuchKey
        raise FailureFeedback.new("There's no key named `#{key}' in the bucket `#{bucket}'")
      end
    end
  end
end
