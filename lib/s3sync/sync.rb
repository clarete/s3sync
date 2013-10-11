# s3sync - Tool belt for managing your S3 buckets
#
# The MIT License (MIT)
#
# Copyright (c) 2013  Lincoln de Sousa <lincoln@clarete.li>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

# Part of this software was inspired by the original s3sync, so here's their
# copyright notice:

# (c) 2007 s3sync.net
#
# This software code is made available "AS IS" without warranties of any
# kind.  You may copy, display, modify and redistribute the software
# code either by itself or as incorporated into your code; provided that
# you do not remove any proprietary notices.  Your use of this software
# code is at your own risk and you waive any claim against the author
# with respect to your use of this software code.

require 'find'
require 'fileutils'
require 's3sync/util'

module S3Sync

  class Location
    attr_accessor :path
    attr_accessor :bucket

    def initialize path, bucket=nil
      raise RuntimeError if path.nil?
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

    attr_accessor :base
    attr_accessor :path
    attr_accessor :size

    def initialize base, path, size
      @base = base
      @path = path
      @size = size
    end

    def full
      S3Sync.safe_join [@base, @path]
    end

    def == other
      full == other.full and @size == other.size
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

  class LocalDirectory
    attr_accessor :source

    def initialize source
      @source = source
    end

    def list_files
      nodes = {}
      Find.find(@source) do |file|
        begin
          st = File.stat file        # Might fail
          raise if not st.readable?  # We're not interested in things we can't read
        rescue
          $stderr.puts "WARNING: Skipping unreadable file #{file}"
          Find.prune
        end

        # We don't support following symlinks for now, we don't need to follow
        # folders and I don't think we care about any other thing, right?
        next unless st.file?

        # We only need the relative path here
        file_name = file.gsub(/^#{@source}\/?/, '').squeeze('/')
        node = Node.new(@source.squeeze('/'), file_name, st.size)
        nodes[node.path] = node
      end

      return nodes
    end
  end

  class SyncCommand

    def self.cmp hash1, hash2
      same, to_add_to_2 = [], []

      hash1.each do |key, value|
        value2 = hash2.delete key
        if value2.nil?
          to_add_to_2 << value
        elsif value2.size == value.size
          same << value
        else
          to_add_to_2 << value
        end
      end

      to_remove_from_2 = hash2.values

      [same, to_add_to_2, to_remove_from_2]
    end

    def initialize args, source, destination
      @args = args
      @source = source
      @destination = destination
    end

    def run
      # Reading the source and destination using our helper method
      if (source, destination, bucket = self.class.parse_params [@source, @destination]).nil?
        raise WrongUsage.new(nil, 'Need a source and a destination')
      end

      # Getting the trees
      source_tree, destination_tree = read_trees source, destination

      # Getting the list of resources to be exchanged between the two peers
      _, to_add, to_remove = self.class.cmp source_tree, destination_tree

      # Removing the items matching the exclude pattern if requested
      to_add.select! { |e|
        begin
          (e.path =~ /#{@args.exclude}/).nil?
        rescue RegexpError => exc
          raise WrongUsage.new nil, exc.message
        end
      } if @args.exclude

      # Calling the methods that perform the actual IO
      if source.local?
        upload_files destination, to_add
        remove_files destination, to_remove unless @args.keep
      else
        download_files destination, source, to_add
        remove_local_files destination, source, to_remove unless @args.keep
      end
    end

    def self.parse_params args
      # Reading the arbitrary parameters from the command line and getting
      # modifiable copies to parse
      source, destination = args; return nil if source.nil? or destination.nil?

      # Sync from one s3 to another is currently not supported
      if remote_prefix? source and remote_prefix? destination
        raise WrongUsage.new(nil, 'Both arguments can\'t be on S3')
      end

      # C'mon, there's rsync out there
      if !remote_prefix? source and !remote_prefix? destination
        raise WrongUsage.new(nil, 'One argument must be on S3')
      end

      source, destination = process_destination source, destination
      return [Location.new(*source), Location.new(*destination)]
    end

    def self.remote_prefix?(prefix)
      # allow for dos-like things e.g. C:\ to be treated as local even with
      # colon.
      prefix.include? ':' and not prefix.match '^[A-Za-z]:[\\\\/]'
    end

    def self.process_file_destination source, destination, file=""
      if not file.empty?
        sub = (remote_prefix? source) ? source.split(":")[1] : source
        file = file.gsub(/^#{sub}/, '')
      end

      # no slash on end of source means we need to append the last src dir to
      # dst prefix testing for empty isn't good enough here.. needs to be
      # "empty apart from potentially having 'bucket:'"
      if source =~ %r{/$}
        if remote_prefix? destination and destination.end_with? ':'
          S3Sync.safe_join [destination, file]
        else
          File.join [destination, file]
        end
      else
        if remote_prefix? source
          _, name = source.split ":"
          File.join [destination, File.basename(name || ""), file]
        else
          source = /^\/?(.*)/.match(source)[1]

          # Corner case: the root of the remote path is empty, we don't want to
          # add an unnecessary slash here.
          if destination.end_with? ':'
            File.join [destination + source, file]
          else
            File.join [destination, source, file]
          end
        end
      end
    end

    def self.process_destination source, destination
      source, destination = source.dup, destination.dup

      # don't repeat slashes
      source.squeeze! '/'
      destination.squeeze! '/'

      # Making sure that local paths won't break our stuff later
      source.gsub!(/^\.\//, '')
      destination.gsub!(/^\.\//, '')

      # Parsing the final destination
      destination = process_file_destination source, destination, ""

      # here's where we find out what direction we're going
      source_is_s3 = remote_prefix? source

      # canonicalize the S3 stuff
      remote_prefix = source_is_s3 ? source : destination
      bucket, remote_prefix = remote_prefix.split ":"

      remote_prefix ||= ""

      # Just making sure we preserve the direction
      if source_is_s3
        [[remote_prefix, bucket], destination]
      else
        [source, [remote_prefix, bucket]]
      end
    end

    def read_tree_remote location
      dir = location.path
      dir += '/' if not dir.empty? and not dir.end_with?('/')

      nodes = {}
      @args.s3.buckets[location.bucket].objects.with_prefix(dir || "").to_a.collect do |obj|
        node = Node.new(location.path, obj.key, obj.content_length)
        nodes[node.path] = node
      end
      return nodes
    end

    def read_trees source, destination
      if source.local?
        source_tree = LocalDirectory.new(source.path).list_files
        destination_tree = read_tree_remote destination
      else
        source_tree = read_tree_remote source
        destination_tree = LocalDirectory.new(destination.path).list_files
      end

      [source_tree, destination_tree]
    end

    def upload_files remote, list
      list.each do |e|
        if @args.verbose
          puts " + #{e.full} => #{remote}#{e.path}"
        end

        unless @args.dry_run
          remote_path = "#{remote.path}#{e.path}"
          @args.s3.buckets[remote.bucket].objects[remote_path].write Pathname.new(e.full), :acl => @args.acl
        end
      end
    end

    def remove_files remote, list
      if @args.verbose
        list.each {|e|
          puts " - #{remote}#{e.path}"
        }
      end

      unless @args.dry_run
        @args.s3.buckets[remote.bucket].objects.delete_if { |obj| list.map(&:path).include? obj.key }
      end
    end

    def download_files destination, source, list
      list.each {|e|
        path = File.join destination.path, e.path

        if @args.verbose
          puts " + #{source}#{e.path} => #{path}"
        end

        unless @args.dry_run
          obj = @args.s3.buckets[source.bucket].objects[e.path]

          # Making sure this new file will have a safe shelter
          FileUtils.mkdir_p File.dirname(path)

          # Downloading and saving the files
          File.open(path, 'wb') do |file|
            begin
              obj.read do |chunk|
                file.write chunk
              end
            rescue AWS::Core::Http::NetHttpHandler::TruncatedBodyError => e
              retry
            end
          end
        end
      }
    end

    def remove_local_files destination, source, list
      list.each {|e|
        path = File.join destination.path, e.path

        if @args.verbose
          puts " * #{e.path} => #{path}"
        end

        unless @args.dry_run
          FileUtils.rm_rf path
        end
      }
    end
  end
end
