# (c) 2013  Lincoln de Sousa <lincoln@clarete.li>
# (c) 2007 s3sync.net
#
# This software code is made available "AS IS" without warranties of any
# kind.  You may copy, display, modify and redistribute the software
# code either by itself or as incorporated into your code; provided that
# you do not remove any proprietary notices.  Your use of this software
# code is at your own risk and you waive any claim against the author
# with respect to your use of this software code.

module S3sync

  class Location
    attr_accessor :path
    attr_accessor :bucket

    def initialize path, bucket=nil
      @path = path
      @bucket = bucket || nil
    end

    def to_s
      out = []
      out << @bucket unless @bucket.nil?
      out << @path
      out.join ':'
    end

    def local?
      @bucket.nil?
    end
  end

  class Node
    include Comparable

    attr_accessor :path
    attr_accessor :size

    def initialize path, size
      @path = path
      @size = size
    end

    def == other
      @path == other.path
      @size == other.size
    end

    def <=> other
      if self.size < other.size
        -1
      elsif self.size > other.size
        1
      else
        0
      end
    end
  end

  class SyncCommand

    def SyncCommand.cmp list1, list2
      l1 = {}; list1.each {|e| l1[e.path] = e.size}
      l2 = {}; list2.each {|e| l2[e.path] = e.size}

      same, to_add_to_2, to_remove_from_2 = [], [], []

      l1.each do |key, value|
        value2 = l2.delete key
        if value2.nil?
          to_add_to_2 << key
        elsif value2 == value
          same << key
        else
          to_add_to_2 << key
        end
      end

      to_remove_from_2 = l2.keys

      [same, to_add_to_2, to_remove_from_2]
    end

    def initialize args, argv
      @args = args

      # Reading the source and destination using our helper method
      if (local, remote, bucket = parse_params argv).nil?
        raise WrongUsage.new(nil, 'Need a source and a destination')
      end

      # Getting the trees
      source_tree = read_tree local
      destination_tree = read_tree remote

      # Getting the list of resources to be exchanged between the two peers
      _, upload_list, remove_list = SyncCommand.cmp source_tree, destination_tree

      # Removing the items matching the exclude pattern if requested
      upload_list.select! { |e|
        begin
          (e =~ /#{@args[:options]["--exclude"]}/).nil?
        rescue RegexpError => exc
          raise WrongUsage.new nil, exc.message
        end
      } if @args[:options]["--exclude"]

      upload_files remote, local, upload_list
      remove_files remote, remove_list
    end

    def parse_params args
      # Reading the arbitrary parameters from the command line and getting
      # modifiable copies to parse
      source, destination = args; return nil if source.nil? or destination.nil?

      raise WrongUsage.new(nil, 'Both arguments can\'t be on S3') if remote_prefix?(source) and remote_prefix?(destination)
      raise WrongUsage.new(nil, 'One argument must be on S3') if !remote_prefix?(source) and !remote_prefix?(destination)

      source, destination = source.dup, destination.dup

      # handle trailing slash for source properly
      if (source !~ %r{/$})
        # no slash on end of source means we need to append the last src dir to
        # dst prefix testing for empty isn't good enough here.. needs to be
        # "empty apart from potentially having 'bucket:'"
        slash = (destination.empty? or destination.match(%r{:$}))? "" : "/"

        # not good enough.. sometimes this coughs up the bucket as a prefix
        # destinationPrefix.replace(destinationPrefix + slash +
        # sourcePrefix.split(/(?:\/|:)/).last) take everything at the end after
        # a slash or colon
        destination.replace(destination + slash + %r{([^/:]*)$}.match(source)[1])
      end

      # no trailing slash on dest, ever.
      destination.sub!(%r{/$}, "")

      # don't repeat slashes
      source.squeeze!('/')
      destination.squeeze!('/')

      # here's where we find out what direction we're going
      source_is_s3 = remote_prefix?(source)

      # alias these variables to the other strings (in ruby = does not make
      # copies of strings)
      remote_prefix = source_is_s3 ? source : destination
      local_prefix = source_is_s3 ? destination : source

      # canonicalize the S3 stuff
      bucket = (/^(.*?):/.match(remote_prefix))[1]
      remote_prefix.replace((/:(.*)$/.match(remote_prefix))[1])

      # canonicalize the local stuff but that can kill a trailing slash, which
      # we need to preserve long enough to know whether we mean "the dir" or
      # "its contents" it will get re-stripped by the local generator after
      # expressing this knowledge
      local_trailing_slash = local_prefix.match(%r{/$})
      local_prefix.replace(File.expand_path(local_prefix))
      local_prefix += '/' if local_trailing_slash

      # Reorganizing who is source and who is destination
      if source_is_s3
        [Location.new(remote_prefix, bucket), Location.new(local_prefix)]
      else
        [Location.new(local_prefix), Location.new(remote_prefix, bucket)]
      end
    end

    def remote_prefix?(prefix)
      # allow for dos-like things e.g. C:\ to be treated as local even with
      # colon.
      prefix.include?(':') and not prefix.match('^[A-Za-z]:[\\\\/]')
    end

    def read_tree location
      if location.local?
        Dir.glob("#{location.path}/**/*").collect { |i|
          name = i.gsub /^#{location.path}\//, ''
          Node.new(name, File.stat(i).size)
        }
      else
        begin
          @args[:s3].buckets[location.bucket].objects.with_prefix(location.path || "").to_a.collect {|i|
            Node.new(i.key, i.content_length)
          }
        rescue AWS::S3::Errors::NoSuchBucket
          raise FailureFeedback.new("There's no bucket named `#{location.bucket}'")
        rescue AWS::S3::Errors::NoSuchKey
          raise FailureFeedback.new("There's no key named `#{location.path}' in the bucket `#{location.bucket}'")
        end
      end
    end

    def upload_files remote, local, list
      list.each do |e|
        path = File.join local.path, e
        @args[:s3].buckets[remote.bucket].objects[e].write(Pathname.new path) if File.file? path
      end
    end

    def remove_files remote, list
      @args[:s3].buckets[remote.bucket].objects.delete_if { |obj| list.include? obj.key }
    end
  end
end
