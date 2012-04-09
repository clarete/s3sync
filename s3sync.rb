#!/usr/bin/env ruby 
# This software code is made available "AS IS" without warranties of any        
# kind.  You may copy, display, modify and redistribute the software            
# code either by itself or as incorporated into your code; provided that        
# you do not remove any proprietary notices.  Your use of this software         
# code is at your own risk and you waive any claim against the author
# with respect to your use of this software code. 
# (c) 2007 s3sync.net
#

module S3sync

	$S3SYNC_MIME_TYPES_FILE = (ENV["S3SYNC_MIME_TYPES_FILE"] or '/etc/mime.types')
	
	$S3SYNC_VERSION = '1.2.6'

   # always look "here" for include files (thanks aktxyz)
   $LOAD_PATH << File.expand_path(File.dirname(__FILE__)) 
   
	require 'getoptlong'
	#require 'generator' # http://www.ruby-doc.org/stdlib/libdoc/generator/rdoc/classes/Generator.html
	require 'thread_generator' # memory doesn't leak with this one, at least nothing near as bad
	require 'md5'
	require 'tempfile'
	require 's3try'
   
   # after other mods, so we don't overwrite yaml vals with defaults
   require 's3config'
   include S3Config
	
	$S3syncDirString = '{E40327BF-517A-46e8-A6C3-AF51BC263F59}'
	$S3syncDirTag = 'd66759af42f282e1ba19144df2d405d0'
	$S3syncDirFile = Tempfile.new("s3sync")
	$S3syncDirFile.puts $S3syncDirString
	$S3syncDirFile.close # not final; we need this file again to 'put' directory nodes
	
	if $S3SYNC_MIME_TYPES_FILE and FileTest.exist?($S3SYNC_MIME_TYPES_FILE)
		File.open($S3SYNC_MIME_TYPES_FILE, 'r') do |f|
			$mimeTypes = {}
			f.each_line do |l|
				if l =~ /^(\w\S+)\s+(\S.*)$/
					type = $1
					exts = $2.split
					exts.each do |e|
						$mimeTypes[e.to_s] = type.to_s
					end
				end
			end
		end
	end
	
	def S3sync.main 	
		# ---------- OPTIONS PROCESSING ---------- #	
	
		$S3syncOptions = Hash.new
		optionsParser = GetoptLong.new(
			  [ '--help',    '-h',	GetoptLong::NO_ARGUMENT ],
			  [ '--ssl',     '-s',	GetoptLong::NO_ARGUMENT ],
			  [ '--recursive','-r',	GetoptLong::NO_ARGUMENT ],
			  [ '--public-read','-p', GetoptLong::NO_ARGUMENT ],
			  [ '--delete',			GetoptLong::NO_ARGUMENT ],
			  [ '--verbose', '-v',	GetoptLong::NO_ARGUMENT ],
			  [ '--dryrun',  '-n',	GetoptLong::NO_ARGUMENT ], 
			  [ '--debug',   '-d',	GetoptLong::NO_ARGUMENT ],
			  [ '--memory',   '-m',	GetoptLong::NO_ARGUMENT ],
			  [ '--progress',	GetoptLong::NO_ARGUMENT ],
           [ '--expires',        GetoptLong::REQUIRED_ARGUMENT ],
           [ '--cache-control',  GetoptLong::REQUIRED_ARGUMENT ],
           [ '--exclude',        GetoptLong::REQUIRED_ARGUMENT ],
			  [ '--make-dirs',	GetoptLong::NO_ARGUMENT ],
			  [ '--no-md5',	GetoptLong::NO_ARGUMENT ]           
			  )
			  
		def S3sync.usage(message = nil)
			$stderr.puts message if message
			name = $0.split('/').last
			$stderr.puts <<"ENDUSAGE"
#{name} [options] <source> <destination>\t\tversion #{$S3SYNC_VERSION}
  --help    -h          --verbose     -v     --dryrun    -n	
  --ssl     -s          --recursive   -r     --delete
  --public-read -p      --expires="<exp>"    --cache-control="<cc>"
  --exclude="<regexp>"  --progress           --debug   -d
  --make-dirs           --no-md5
One of <source> or <destination> must be of S3 format, the other a local path.
Reminders:
* An S3 formatted item with bucket 'mybucket' and prefix 'mypre' looks like:
    mybucket:mypre/some/key/name
* Local paths should always use forward slashes '/' even on Windows
* Whether you use a trailing slash on the source path makes a difference.
* For examples see README.
ENDUSAGE
		exit
		end #usage
		
		begin
			optionsParser.each {|opt, arg| $S3syncOptions[opt] = (arg || true)}
		rescue StandardError
			usage # the parser already printed an error message
		end
		usage if $S3syncOptions['--help']
		$S3syncOptions['--verbose'] = true if $S3syncOptions['--dryrun'] or $S3syncOptions['--debug'] or $S3syncOptions['--progress']
		$S3syncOptions['--ssl'] = true if $S3syncOptions['--ssl'] # change from "" to true to appease s3 port chooser

		
		# ---------- CONNECT ---------- #
		S3sync::s3trySetup 

		# ---------- PREFIX PROCESSING ---------- #
	
		def S3sync.s3Prefix?(pre)
			# allow for dos-like things e.g. C:\ to be treated as local even with colon
			pre.include?(':') and not pre.match('^[A-Za-z]:[\\\\/]')
		end
		sourcePrefix, destinationPrefix = ARGV
		usage("You didn't set up your environment variables; see README.txt") if not($AWS_ACCESS_KEY_ID and $AWS_SECRET_ACCESS_KEY) 
		usage('Need a source and a destination') if sourcePrefix == nil or destinationPrefix == nil
		usage('Both arguments can\'t be on S3') if s3Prefix?(sourcePrefix) and s3Prefix?(destinationPrefix)
		usage('One argument must be on S3') if !s3Prefix?(sourcePrefix) and !s3Prefix?(destinationPrefix)

		# so we can modify them
		sourcePrefix, destinationPrefix = sourcePrefix.dup, destinationPrefix.dup

		# handle trailing slash for source properly
		if(sourcePrefix !~ %r{/$})
			# no slash on end of source means we need to append the last src dir to dst prefix
			# testing for empty isn't good enough here.. needs to be "empty apart from potentially having 'bucket:'"
			slash = (destinationPrefix.empty? or destinationPrefix.match(%r{:$}))? "" : "/"
			# not good enough.. sometimes this coughs up the bucket as a prefix destinationPrefix.replace(destinationPrefix + slash + sourcePrefix.split(/(?:\/|:)/).last)
			# take everything at the end after a slash or colon
			destinationPrefix.replace(destinationPrefix + slash + %r{([^/:]*)$}.match(sourcePrefix)[1])
		end
		# no trailing slash on dest, ever.
		destinationPrefix.sub!(%r{/$}, "")
		
		# don't repeat slashes
		sourcePrefix.squeeze!('/')
		destinationPrefix.squeeze!('/')
		
		# here's where we find out what direction we're going
		sourceIsS3 = s3Prefix?(sourcePrefix)
		# alias these variables to the other strings (in ruby = does not make copies of strings)
		s3Prefix = sourceIsS3 ? sourcePrefix : destinationPrefix
		localPrefix = sourceIsS3 ? destinationPrefix : sourcePrefix
		
		# canonicalize the S3 stuff
		s3Bucket = (/^(.*?):/.match(s3Prefix))[1]
		s3Prefix.replace((/:(.*)$/.match(s3Prefix))[1])
		debug("s3Prefix #{s3Prefix}")
		$S3SyncOriginalS3Prefix = s3Prefix.dup
		
		# canonicalize the local stuff
		# but that can kill a trailing slash, which we need to preserve long enough to know whether we mean "the dir" or "its contents"
		# it will get re-stripped by the local generator after expressing this knowledge
		localTrailingSlash = localPrefix.match(%r{/$}) 
		localPrefix.replace(File.expand_path(localPrefix))
		localPrefix += '/' if localTrailingSlash
		debug("localPrefix #{localPrefix}")
		# used for exclusion parsing
		$S3SyncOriginalLocalPrefix = localPrefix.dup
		
		# exclude preparation
		# we don't want to build then throw away this regexp for each node in the universe; do it once globally
		$S3SyncExclude = Regexp.new($S3syncOptions['--exclude']) if $S3syncOptions['--exclude']
		
		
		# ---------- GENERATORS ---------- #
	
		
		# a generator that will return the files/dirs of the local tree one by one
		# sorted and decorated for easy comparison with the S3 tree
		localTree = Generator.new do |g|
			def S3sync.localTreeRecurse(g, prefix, path)
				debug("localTreeRecurse #{prefix} #{path}")
				#if $S3syncOptions['--memory']
				#	$stderr.puts "Starting local recurse"
				#	stats = ostats stats 
				#end
				d = nil
				begin
					slash = prefix.empty? ? "" : "/"
					d = Dir.new(prefix + slash + path)
				rescue Errno::ENOENT
					# ok the dir doesn't exist at all (this only really occurs for the root i.e. first dir)
					return nil
				rescue Errno::EACCES
					# vista won't even let us touch some stuff in our own profile
					return nil
				end
				# do some pre-processing
				# the following sleight of hand is to make the recursion match the way s3 sorts
				# take for example the directory 'foo' and the file 'foo.bar'
				# when we encounter the dir we would want to recurse into it
				# but S3 would just say 'period < slash' and sort 'foo.bar' between the dir node 
				# and the contents in that 'dir'
				#
				# so the solution is to not recurse into the directory until the point where
				# it would come up "next" in the S3 list
				# We have to do these hoops on the local side, because we have very little control
				# over how S3 will return its results
				toAdd = Array.new
				d.each do |name|
					slash = path.empty? ? "" : "/"
					partialPath = path + slash + name
					slash = prefix.empty? ? "" : "/"
					fullPath = prefix + slash + partialPath
					if name == "." or name == ".."
						# skip
					else
						# add a dir node if appropriate
						debug("Test #{fullPath}")
						if ((not FileTest.symlink?(fullPath)) and FileTest.directory?(fullPath)) and $S3syncOptions['--recursive']
							debug("Adding it as a dir node")
							toAdd.push(name + '/') # always trail slash here for sorting purposes (removed below with rindex test)
						end
					end
				end
				dItems = d.collect + toAdd
				d.close
				d = toAdd = nil
				dItems.sort! #aws says we will get alpha sorted results but ruby doesn't
				dItems.each do |name|
					isDirNode = false
					if name.rindex('/') == name.length-1
						name = name.slice(0...name.length-1)
						isDirNode = true
						debug("#{name} is a dir node")
					end
					slash = path.empty? ? "" : "/"
					partialPath = path + slash + name
					slash = prefix.empty? ? "" : "/"
					fullPath = prefix + slash + partialPath
					excludePath = fullPath.slice($S3SyncOriginalLocalPrefix.length...fullPath.length)
					if name == "." or name == ".."
						# skip
					elsif $S3SyncExclude and $S3SyncExclude.match(excludePath)
						debug("skipping local item #{excludePath} because of --exclude")
					elsif isDirNode
						localTreeRecurse(g, prefix, partialPath)
					else
						# a normal looking node we should try to process
						debug("local item #{fullPath}")
						g.yield(LocalNode.new(prefix, partialPath))
					end
				end
				#if $S3syncOptions['--memory']
				#	$stderr.puts "Ending local recurse"
				#	stats = ostats stats 
				#end
			end
			# a bit of a special case for local, since "foo/" and "foo" are essentially treated the same by file systems
			# so we need to think harder about what the user really meant in the command line.
			localPrefixTrim = localPrefix
			if localPrefix !~ %r{/$}
				# no trailing slash, so yield the root itself first, then recurse if appropriate
				# gork this is still not quite good enough.. if local is the dest then we don't know whether s3 will have a root dir node yielded a priori, so we can't know whether to do this.  only matters for --erase though
				g.yield(LocalNode.new(localPrefixTrim, "")) # technically we should check this for exclusion, but excluding the root node is kind of senseless.. and that would be a pain to set up here
				localTreeRecurse(g, localPrefixTrim, "") if $S3syncOptions['--recursive']
			else
				# trailing slash, so ignore the root itself, and just go into the first level
				localPrefixTrim.sub!(%r{/$}, "") # strip the slash because of how we do local node slash accounting in the recurse above
				localTreeRecurse(g, localPrefixTrim, "") 
			end
		end
		
		# a generator that will return the nodes in the S3 tree one by one
		# sorted and decorated for easy comparison with the local tree
		s3Tree = Generator.new do |g|
			def S3sync.s3TreeRecurse(g, bucket, prefix, path)
				if $S3syncOptions['--memory']
					$stderr.puts "Starting S3 recurse"
					GC.start
					stats = ostats stats 
				end
				$stderr.puts "s3TreeRecurse #{bucket} #{prefix} #{path}" if $S3syncOptions['--debug']
				nextPage = true
				marker = ''
				while nextPage do
					fullPrefix = prefix + path
					debug("nextPage: #{marker}") if marker != ''
					options = {}
					options['prefix'] = fullPrefix # start at the right depth
					options['delimiter'] = '/' # only one dir at a time please
					options['max-keys'] = '200' # use manageable chunks
					options['marker'] = marker unless marker == ''
					d = S3sync.S3try(:list_bucket, bucket, options)
					$stderr.puts "S3 ERROR: #{d.http_response}" unless d.http_response.is_a? Net::HTTPSuccess
					# the 'directories' and leaf nodes are in two separate collections
					# because a dir will never have the same name as a node, we can just shove them together and sort
					# it's important to evaluate them alphabetically for efficient comparison to the local tree
					tItems = d.entries + d.common_prefix_entries
					tItems.sort! do |a,b|
						aName = a.respond_to?('key') ? a.key : a.prefix
						bName = b.respond_to?('key') ? b.key : b.prefix
						# the full path will be returned, efficient to ignore the part we know will be in common
						aName.slice(fullPrefix.length..aName.length) <=> bName.slice(fullPrefix.length..bName.length)
					end
					# get rid of the big s3 objects asap, just save light-weight nodes and strings
					items = tItems.collect do |item|
						if item.respond_to?('key')
							key = Iconv.iconv($S3SYNC_NATIVE_CHARSET, "UTF-8", item.key).join
							Node.new(key, item.size, item.etag, item.last_modified)
						else
							Iconv.iconv($S3SYNC_NATIVE_CHARSET, "UTF-8", item.prefix).join
						end
					end
					nextPage = d.properties.is_truncated
					marker = (d.properties.next_marker)? d.properties.next_marker : ((d.entries.length > 0)? d.entries.last.key : '')
					# get this into native char set (because when we feed it back to s3 that's what it will expect)
					marker = Iconv.iconv($S3SYNC_NATIVE_CHARSET, "UTF-8", marker).join
					tItems = nil
					d = nil # get rid of this before recursing; it's big
					item = nil
					GC.start # not sure but I think yielding before doing this is causing evil closure bloat
					items.each do |item|
						if not (item.kind_of? String)
							# this is an item
							excludePath = item.name.slice($S3SyncOriginalS3Prefix.length...item.name.length)
							if $S3SyncExclude and $S3SyncExclude.match(excludePath)
								debug("skipping S3 item #{excludePath} due to --exclude")
							else
								debug("S3 item #{item.name}")
								g.yield(S3Node.new(bucket, prefix, item))
							end
						else
							# it's a prefix (i.e. there are sub keys)
							partialPath = item.slice(prefix.length..item.length) # will have trailing slash
							excludePath = item.slice($S3SyncOriginalS3Prefix.length...item.length)
							# recurse
							if $S3SyncExclude and $S3SyncExclude.match(excludePath)
								debug("skipping prefix #{excludePath} due to --exclude")
							else
								debug("prefix found: #{partialPath}")
								s3TreeRecurse(g, bucket, prefix, partialPath) if $S3syncOptions['--recursive'] 
							end
						end
					end
					items = nil
				end # of while nextPage
				if $S3syncOptions['--memory']
					$stderr.puts "Ending S3 recurse"
					GC.start
					stats = ostats stats 
				end
			end
			# this will yield the root node first and then recurse
			s3TreeRecurse(g, s3Bucket, s3Prefix, "")
			
		end
		
		# alias the tree objects so we don't care below which direction the transfer is going
		if sourceIsS3
			sourceTree, destinationTree = s3Tree, localTree
		else
			sourceTree, destinationTree = localTree, s3Tree
		end
		
		
		# ---------- COMPARATOR ---------- #
		
		# run the comparison engine and act according to what we find for each check
		nodesToDelete = Array.new # a stack. have to delete in reverse order of normal create/update processing
		
		sourceNode = sourceTree.next? ? sourceTree.next : nil
		destinationNode = destinationTree.next? ? destinationTree.next : nil
		while sourceNode or destinationNode do
			debug("source: #{sourceNode.name}") if sourceNode
			debug("dest: #{destinationNode.name}") if destinationNode
			if (!destinationNode) or (sourceNode and (sourceNode.name < destinationNode.name))
				dNode = 
				if sourceNode.kind_of? LocalNode
					S3Node.new(s3Bucket, s3Prefix, sourceNode.name)
				else
					LocalNode.new(localPrefix, sourceNode.name)
				end
				puts "Create node #{sourceNode.name}" if $S3syncOptions['--verbose']
				dNode.updateFrom(sourceNode) unless $S3syncOptions['--dryrun']
				sourceNode = sourceTree.next? ? sourceTree.next : nil
			elsif (!sourceNode) or (destinationNode and (sourceNode.name > destinationNode.name))
				$stderr.puts "Source does not have #{destinationNode.name}" if $S3syncOptions['--debug']
				if $S3syncOptions['--delete']
					if destinationNode.directory?
						# have to wait
						nodesToDelete.push(destinationNode) 
					else
						puts "Remove node #{destinationNode.name}" if $S3syncOptions['--verbose']
						destinationNode.delete unless $S3syncOptions['--dryrun']
					end
				end
				destinationNode = destinationTree.next? ? destinationTree.next : nil
			elsif sourceNode.name == destinationNode.name
				if (sourceNode.size != destinationNode.size) or (($S3syncOptions['--no-md5'])? (sourceNode.date > destinationNode.date) : (sourceNode.tag != destinationNode.tag))
					puts "Update node #{sourceNode.name}" if $S3syncOptions['--verbose']
					destinationNode.updateFrom(sourceNode) unless $S3syncOptions['--dryrun']
				elsif $S3syncOptions['--debug']
					$stderr.puts "Node #{sourceNode.name} unchanged" 
				end
				sourceNode = sourceTree.next? ? sourceTree.next : nil
				destinationNode = destinationTree.next? ? destinationTree.next : nil
			end					
		end
		
		# get rid of the (now empty, except for other directories) directories
		nodesToDelete.reverse_each do |node|
			puts "Remove node #{node.name}" if $S3syncOptions['--verbose']
			node.delete unless $S3syncOptions['--dryrun']
		end
		
	end #main

	
		
	# ---------- NODE ---------- #
	
	class Node
		attr_reader :name
		attr_reader :size 
		attr_reader :tag
      attr_reader :date
		def initialize(name='', size = 0, tag = '', date = Time.now.utc)
			@name = name
			@size = size
			@tag = tag
         @date = date
		end
		def directory?()
			@tag == $S3syncDirTag and @size == $S3syncDirString.length
		end
	end
		
	# ---------- S3Node ---------- #
	
	class S3Node < Node
		@path = nil
		@bucket = nil
		@result = nil
		def initialize(bucket, prefix, itemOrName)
			@bucket = bucket
			if itemOrName.kind_of? String
				@name = itemOrName
				@name.sub!(%r{/$}, "") # don't create directories with a slash on the end
				#6/2007. the prefix can be filled but the name empty, in the case of s3sync -r somedir somebucket:
				if (not prefix.empty? and @name.empty?)
					@name = prefix
					itemOrName = prefix
					prefix = ""
				end
				slash = prefix.empty? ? "" : "/"
				@path = prefix + slash + itemOrName
			else
				@name = (itemOrName.name.slice((prefix.length)..itemOrName.name.length) or '')
				# depending whether the prefix is / tailed, the name might need trimming
				@name.sub!(%r{^/},"") # get rid of leading slash in name if there (from above simplistic split)
				@name.sub!(%r{/$}, "") # don't create directories with a slash on the end
				@path = itemOrName.name
				@path.sub!(%r{/$}, "") # don't create directories with a slash on the end
				@size = itemOrName.size
				@tag = itemOrName.tag.gsub(/"/,'')
            @date = Time.xmlschema(itemOrName.date)
			end
			debug("s3 node object init. Name:#{@name} Path:#{@path} Size:#{@size} Tag:#{@tag} Date:#{@date}")
		end
		# get this item from s3 into the provided stream
		# S3 pushes to the local item, due to how http streaming is implemented
		def to_stream(s) 
			@result = S3sync.S3try(:get_stream, @bucket, @path, {}, s)
		end
		def symlink?() 
			unless @result
				@result = S3sync.S3try(:head, @bucket, @path)
			end
			debug("symlink value is: #{@result.object.metadata['symlink']}")
			@result.object.metadata['symlink'] == 'true'
		end
		def owner
			unless @result
				@result = S3sync.S3try(:head, @bucket, @path)
			end
			debug("Owner of this s3 node is #{@result.object.metadata['owner']}")
			@result.object.metadata['owner'].to_i # if not there, will be nil => 0 which == root so good default
		end
		def group
			unless @result
				@result = S3sync.S3try(:head, @bucket, @path)
			end
			@result.object.metadata['group'].to_i # 0 default ok
		end
		def permissions
			g = @result.object.metadata['permissions']
			g ? g.to_i : 600 # default to owner only
		end
		def updateFrom(fromNode)
			if fromNode.respond_to?(:stream)
				meta = Hash.new
				meta['owner'] = fromNode.owner.to_s
				meta['group'] = fromNode.group.to_s
				meta['permissions'] = fromNode.permissions.to_s
				meta['symlink'] = 'true' if fromNode.symlink?
				begin
					theStream = fromNode.stream
					theStream = ProgressStream.new(theStream, fromNode.size) if $S3syncOptions['--progress']

					s3o = S3::S3Object.new(theStream, meta)
					debug(@path)
					headers = {'Content-Length' => (fromNode.size.respond_to?(:nonzero?) ? fromNode.size.to_s : '0')}
					headers['x-amz-acl'] = 'public-read' if $S3syncOptions['--public-read']
					headers['Expires'] = $S3syncOptions['--expires'] if $S3syncOptions['--expires']
					headers['Cache-Control'] = $S3syncOptions['--cache-control'] if $S3syncOptions['--cache-control']
					fType = @path.split('.').last
					debug("File extension: #{fType}")
					if defined?($mimeTypes) and fType != '' and (mType = $mimeTypes[fType]) and mType != ''
						debug("Mime type: #{mType}")
						headers['Content-Type'] = mType
					end
					@result = S3sync.S3try(:put, @bucket, @path, s3o, headers)
					theStream.close if (theStream and not theStream.closed?)
				rescue NoMethodError
					# when --progress is used and we can't get the stream object, it doesn't report as null
					# so the above .closed? test will break
					$stderr.puts "Skipping #{@path}: " + $!
				rescue SystemCallError
					theStream.close if (theStream and not theStream.closed?)
					$stderr.puts "Skipping #{@path}: " + $!
				end
			else
				raise "Node provided as update source doesn't support :stream"
			end
		end
		def delete
			@result = S3sync.S3try(:delete, @bucket, @path)
		end
	end
		
	# ---------- LocalNode ---------- #
	
	class LocalNode < Node
		@path = nil
		def initialize(prefix, partialPath)
			slash = prefix.empty? ? "" : "/"
			@path = prefix + slash + partialPath
			# slash isn't at the front of this any more @name = (partialPath.slice(1..partialPath.length) or '')
			@name = partialPath or ''
			if FileTest.symlink?(@path)
				# this could use the 'file' case below, but why create an extra temp file
				linkData = File.readlink(@path)
				$stderr.puts "link to: #{linkData}" if $S3syncOptions['--debug']
				@size = linkData.length
				unless $S3syncOptions['--no-md5']
               md5 = Digest::MD5.new()
               md5 << linkData
               @tag = md5.hexdigest
            end
            @date = File.lstat(@path).mtime.utc
			elsif FileTest.file?(@path)
				@size = FileTest.size(@path)
				data = nil
				begin
               unless $S3syncOptions['--no-md5']
                  data = self.stream
                  md5 = Digest::MD5.new()
                  while !data.eof?
                     md5 << data.read(2048) # stream so it's not taking all memory
                  end
                  data.close
                  @tag = md5.hexdigest
               end
               @date = File.stat(@path).mtime.utc
				rescue SystemCallError
					# well we're not going to have an md5 that's for sure
					@tag = nil
				end
			elsif FileTest.directory?(@path)
				# all s3 directories are dummy nodes contain the same directory string
				# so for easy comparison, set our size and tag thusly
				@size = $S3syncDirString.length
				@tag = $S3syncDirTag
            @date = File.stat(@path).mtime.utc
			end
			debug("local node object init. Name:#{@name} Path:#{@path} Size:#{@size} Tag:#{@tag} Date:#{@date}")
		end
		# return a stream that will read the contents of the local item
		# local gets pulled by the S3Node update fn, due to how http streaming is implemented
		def stream
			begin
				# 1.0.8 switch order of these tests because a symlinked file will say yes to 'file?'
				if FileTest.symlink?(@path) or FileTest.directory?(@path)
					tf = Tempfile.new('s3sync')
					if FileTest.symlink?(@path)
						tf.printf('%s', File.readlink(@path))
					elsif FileTest.directory?(@path)
						tf.printf('%s', $S3syncDirString)
					end
					tf.close
					tf.open
					tf
				elsif FileTest.file?(@path)
					File.open(@path, 'rb')
				end
			rescue SystemCallError
				$stderr.puts "Could not read #{@path}: #{$!}"
				raise
			end
		end
		def stat
			FileTest.symlink?(@path) ? File.lstat(@path) : File.stat(@path)
		end
		def exist?
			FileTest.exist?(@path) or FileTest.symlink?(@path)
		end
		def owner
			self.exist? ? self.stat().uid : 0
		end
		def group
			self.exist? ? self.stat().gid : 0
		end
		def permissions
			self.exist? ? self.stat().mode : 600
		end
		def updateFrom(fromNode)
			if fromNode.respond_to?(:to_stream)
				fName = @path + '.s3syncTemp'
            # handle the case where the user wants us to create dirs that don't exist in S3
            if $S3syncOptions['--make-dirs']
               # ensure target's path exists
               dirs = @path.split('/')
               # but the last one is a file name
               dirs.pop()
               current = ''
               dirs.each do |dir|
                  current << dir << '/'
                  begin
                     Dir.mkdir(current) unless FileTest.exist?(current)
                  rescue SystemCallError
                     $stderr.puts "Could not mkdir #{current}: #{$!}"
                  end
               end
            end
				unless fromNode.directory?
					f = File.open(fName, 'wb')
					f = ProgressStream.new(f, fromNode.size) if $S3syncOptions['--progress']

					fromNode.to_stream(f) 
					f.close
				end
				# get original item out of the way
				File.unlink(@path) if File.exist?(@path)
				if fromNode.symlink? 
					linkTo = ''
					File.open(fName, 'rb'){|f| linkTo = f.read}
					debug("#{@path} will be a symlink to #{linkTo}")
					begin
						File.symlink(linkTo, @path)
					rescue NotImplementedError
						# windows doesn't do symlinks, for example
						# just bail
						File.unlink(fName) if File.exist?(fName)
						return
					rescue SystemCallError
						$stderr.puts "Could not write symlink #{@path}: #{$!}"
					end
				elsif fromNode.directory?
					# only get here when the dir doesn't exist.  else they'd compare ==
					debug(@path)
					begin
						Dir.mkdir(@path) unless FileTest.exist?(@path)
					rescue SystemCallError
						$stderr.puts "Could not mkdir #{@path}: #{$!}"
					end
					
				else
					begin
						File.rename(fName, @path)
					rescue SystemCallError
						$stderr.puts "Could not write (rename) #{@path}: #{$!}"
					end
						
				end
				# clean up if the temp file is still there (as for links)
				File.unlink(fName) if File.exist?(fName)
				
				# update permissions
				linkCommand = fromNode.symlink? ? 'l' : ''
				begin
					File.send(linkCommand + 'chown', fromNode.owner, fromNode.group, @path)
					File.send(linkCommand + 'chmod', fromNode.permissions, @path)
				rescue NotImplementedError
					# no one has lchmod, but who really cares
				rescue SystemCallError
					$stderr.puts "Could not change owner/permissions on #{@path}: #{$!}"
				end
			else
				raise "Node provided as update source doesn't support :to_stream"
			end
		end
		def symlink?()
			FileTest.symlink?(@path)
		end
		def delete
         # don't try to delete the restore root dir
         # this is a quick fix to deal with the fact that the tree recurse has to visit the root node
         return unless @name != ''
			return unless FileTest.exist?(@path)
			begin
				if FileTest.directory?(@path)
					Dir.rmdir(@path)
				else
					File.unlink(@path)
				end
			rescue SystemCallError
				$stderr.puts "Could not delete #{@path}: #{$!}"
			end
		end
	end	
	
	
end #module

def debug(str)
	$stderr.puts str if $S3syncOptions['--debug']
end

def ostats(last_stat = nil)
  stats = Hash.new(0)
  ObjectSpace.each_object {|o| stats[o.class] += 1}

  stats.sort {|(k1,v1),(k2,v2)| v2 <=> v1}.each do |k,v|
    $stderr.printf "%-30s  %10d", k, v
    $stderr.printf " delta %10d", (v - last_stat[k]) if last_stat
    $stderr.puts
  end

  stats
end 

# go!
S3sync::main