# (c) 2013  Lincoln de Sousa <lincoln@clarete.li>
# (c) 2007 s3sync.net
#
# This software code is made available "AS IS" without warranties of any
# kind.  You may copy, display, modify and redistribute the software
# code either by itself or as incorporated into your code; provided that
# you do not remove any proprietary notices.  Your use of this software
# code is at your own risk and you waive any claim against the author
# with respect to your use of this software code.

require 's3sync/util'
require 'fileutils'

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

    def == other
      @path == other.path and @bucket == other.bucket
    end

    alias eql? ==
  end

  class Node
    include Comparable

    attr_accessor :relative_path
    attr_accessor :path
    attr_accessor :size

    def initialize relative_path, path, size
      @relative_path = relative_path
      @path = path
      @size = size
    end

    def == other
      @path == other.path and @size == other.size
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

    alias eql? ==
  end

  class SyncCommand

    def SyncCommand.cmp list1, list2
      l1 = {}; list1.each {|e| l1[e.relative_path] = e}
      l2 = {}; list2.each {|e| l2[e.relative_path] = e}

      same, to_add_to_2, to_remove_from_2 = [], [], []

      l1.each do |key, value|
        value2 = l2.delete key
        if value2.nil?
          to_add_to_2 << value
        elsif value2.size == value.size
          same << value
        else
          to_add_to_2 << value
        end
      end

      to_remove_from_2 = l2.values

      [same, to_add_to_2, to_remove_from_2]
    end

    def initialize args, source, destination
      @args = args
      @source = source
      @destination = destination
    end

    def run
      # Reading the source and destination using our helper method
      if (source, destination, bucket = SyncCommand.parse_params [@source, @destination]).nil?
        raise WrongUsage.new(nil, 'Need a source and a destination')
      end

      # Getting the trees
      source_tree = read_tree source
      destination_tree = read_tree destination

      # Getting the list of resources to be exchanged between the two peers
      _, to_add, to_remove = SyncCommand.cmp source_tree, destination_tree

      # Removing the items matching the exclude pattern if requested
      to_add.select! { |e|
        begin
          (e.relative_path =~ /#{@args[:options]["--exclude"]}/).nil?
        rescue RegexpError => exc
          raise WrongUsage.new nil, exc.message
        end
      } if @args[:options]["--exclude"]

      if source.local?
        upload_files destination, source, to_add
        remove_files destination, to_remove unless @args[:options]["--keep"]
      else
        download_files destination, source, to_add
        remove_local_files destination, source, to_remove unless @args[:options]["--keep"]
      end
    end

    def SyncCommand.parse_params args
      # Reading the arbitrary parameters from the command line and getting
      # modifiable copies to parse
      source, destination = args; return nil if source.nil? or destination.nil?

      # Sync from one s3 to another is currently not supported
      if SyncCommand.remote_prefix? source and SyncCommand.remote_prefix? destination
        raise WrongUsage.new(nil, 'Both arguments can\'t be on S3')
      end

      # C'mon, there's rsync out there
      if !SyncCommand.remote_prefix? source and !SyncCommand.remote_prefix? destination
        raise WrongUsage.new(nil, 'One argument must be on S3')
      end

      source, destination = SyncCommand.process_destination source, destination
      return [Location.new(*source), Location.new(*destination)]
    end

    def SyncCommand.remote_prefix?(prefix)
      # allow for dos-like things e.g. C:\ to be treated as local even with
      # colon.
      prefix.include?(':') and not prefix.match('^[A-Za-z]:[\\\\/]')
    end

    def SyncCommand.process_destination source, destination
      source, destination = source.dup, destination.dup

      # don't repeat slashes
      source.squeeze! '/'
      destination.squeeze! '/'

      # here's where we find out what direction we're going
      source_is_s3 = remote_prefix? source

      # alias these variables to the other strings (in ruby = does not make
      # copies of strings)
      remote_prefix = source_is_s3 ? source : destination
      local_prefix = source_is_s3 ? destination : source

      # canonicalize the S3 stuff
      bucket = /^(.*?):/.match(remote_prefix)[1]
      remote_prefix.replace(/:(.*)$/.match(remote_prefix)[1])

      # no slash on end of source means we need to append the last src dir to
      # dst prefix testing for empty isn't good enough here.. needs to be
      # "empty apart from potentially having 'bucket:'"
      if source =~ %r{/$}
        final_destination = File.join [destination, ""]
      else
        final_destination =
          if source_is_s3
            File.join [destination, File.basename(source), ""]
          else
            File.join [destination, source, ""]
          end
      end

      # Just making sure we preserve the direction
      if source_is_s3
        [[source, bucket], final_destination]
      else
        [source, [final_destination, bucket]]
      end
    end

    def read_tree location
      if location.local?
        Dir.glob("#{location.path}/**/*").collect { |i|
          file = i.squeeze! '/'
          name = File.join (file.split "/") - (location.path.split "/")
          Node.new(name, file, File.stat(file).size)
        }
      else
        begin
          dir = location.path
          dir += '/' if not dir.end_with? '/'
          l = @args[:s3].buckets[location.bucket].objects.with_prefix(dir || "")
          l.to_a.collect {|i|
            name = File.join (i.key.split "/") - (location.path.split "/")
            Node.new(name, i.key, i.content_length)
          }
        rescue AWS::S3::Errors::NoSuchBucket
          raise FailureFeedback.new("There's no bucket named `#{location.bucket}'")
        rescue AWS::S3::Errors::NoSuchKey
          raise FailureFeedback.new("There's no key named `#{location.path}' in the bucket `#{location.bucket}'")
        rescue AWS::S3::Errors::AccessDenied
          raise FailureFeedback.new("Access denied")
        end
      end
    end

    def upload_files remote, local, list
      puts "Upload"

      list.each do |e|
        path = File.join local.path, e.relative_path
        puts " * #{e.relative_path} => #{path}"
        # @args[:s3].buckets[remote.bucket].objects[e.path].write(Pathname.new e.path) if File.file? e.path
      end
    end

    def remove_files remote, list
      puts "Remove"

      list.each {|e|
        path = File.join local.path, e.relative_path
        puts " * #{e.relative_path} => #{path}"
      }

      # @args[:s3].buckets[remote.bucket].objects.delete_if { |obj| list.include? obj.key }
    end

    def download_files destination, source, list
      puts "Download"

      list.each {|e|
        name = e

        # Removing the base path informed by the user
        path = File.join destination.path, e.relative_path
        puts " * #{e.relative_path} => #{path}"
        obj = @args[:s3].buckets[source.bucket].objects[e.path]

        # Making sure this new file will have a safe shelter
        # FileUtils.mkdir_p File.dirname(path)

        # Downloading and saving the files
        # File.open(path, 'wb') do |file|
        #   obj.read do |chunk|
        #     file.write chunk
        #   end
        # end
      }
    end

    def remove_local_files destination, source, list
      puts "Remove"

      list.each {|e|
        path = File.join destination.path, e.relative_path
        puts " * #{e.relative_path} => #{path}"
        # FileUtils.rm_rf File.join(destination.path, e.path)
      }
    end
  end
end
