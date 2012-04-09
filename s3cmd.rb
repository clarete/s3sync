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

   # always look "here" for include files (thanks aktxyz)
   $LOAD_PATH << File.expand_path(File.dirname(__FILE__)) 

	require 's3try'
	
	$S3CMD_VERSION = '1.2.6'
   
	require 'getoptlong'

   # after other mods, so we don't overwrite yaml vals with defaults
   require 's3config'
   include S3Config
	
	def S3sync.s3cmdMain 	
		# ---------- OPTIONS PROCESSING ---------- #	
	
		$S3syncOptions = Hash.new
		optionsParser = GetoptLong.new(
			  [ '--help',    '-h',	GetoptLong::NO_ARGUMENT ],
			  [ '--ssl',     '-s',	GetoptLong::NO_ARGUMENT ],
			  [ '--verbose', '-v',	GetoptLong::NO_ARGUMENT ],
			  [ '--dryrun',  '-n',	GetoptLong::NO_ARGUMENT ], 
			  [ '--debug',   '-d',	GetoptLong::NO_ARGUMENT ],
			  [ '--progress',       GetoptLong::NO_ARGUMENT ],
           [ '--expires-in', GetoptLong::REQUIRED_ARGUMENT ]
			  )
			  
		def S3sync.s3cmdUsage(message = nil)
			$stderr.puts message if message
			name = $0.split('/').last
			$stderr.puts <<"ENDUSAGE"
#{name} [options] <command> [arg(s)]\t\tversion #{$S3CMD_VERSION}
  --help    -h        --verbose     -v     --dryrun    -n	
  --ssl     -s        --debug       -d     --progress
  --expires-in=( <# of seconds> | [#d|#h|#m|#s] )
  
Commands:
#{name}  listbuckets  [headers]
#{name}  createbucket  <bucket>  [constraint (i.e. EU)]
#{name}  deletebucket  <bucket>  [headers]
#{name}  list  <bucket>[:prefix]  [max/page]  [delimiter]  [headers]
#{name}  location  <bucket> [headers]
#{name}  delete  <bucket>:key  [headers]
#{name}  deleteall  <bucket>[:prefix]  [headers]
#{name}  get|put  <bucket>:key  <file>  [headers]
ENDUSAGE
		exit
		end #usage
		
		begin
			optionsParser.each {|opt, arg| $S3syncOptions[opt] = (arg || true)}
		rescue StandardError
			s3cmdUsage # the parser already printed an error message
		end
		s3cmdUsage if $S3syncOptions['--help']
		$S3syncOptions['--verbose'] = true if $S3syncOptions['--dryrun'] or $S3syncOptions['--debug'] or $S3syncOptions['--progress']
		$S3syncOptions['--ssl'] = true if $S3syncOptions['--ssl'] # change from "" to true to appease s3 port chooser
      
      if $S3syncOptions['--expires-in'] =~ /d|h|m|s/
         e = $S3syncOptions['--expires-in']
         days = (e =~ /(\d+)d/)? (/(\d+)d/.match(e))[1].to_i : 0
         hours = (e =~ /(\d+)h/)? (/(\d+)h/.match(e))[1].to_i : 0
         minutes = (e =~ /(\d+)m/)? (/(\d+)m/.match(e))[1].to_i : 0
         seconds = (e =~ /(\d+)s/)? (/(\d+)s/.match(e))[1].to_i : 0
         $S3syncOptions['--expires-in'] = seconds + 60 * ( minutes + 60 * ( hours + 24 * ( days ) ) )
      end

		# ---------- CONNECT ---------- #
		S3sync::s3trySetup 
		# ---------- COMMAND PROCESSING ---------- #		

		command, path, file = ARGV
		
		s3cmdUsage("You didn't set up your environment variables; see README.txt") if not($AWS_ACCESS_KEY_ID and $AWS_SECRET_ACCESS_KEY) 
		s3cmdUsage("Need a command (etc)") if not command

		path = '' unless path
		path = path.dup # modifiable
		path += ':' unless path.match(':')
		bucket = (/^(.*?):/.match(path))[1]
		path.replace((/:(.*)$/.match(path))[1])

		case command
			when "delete"
				s3cmdUsage("Need a bucket") if bucket == ''
				s3cmdUsage("Need a key") if path == ''
				headers = hashPairs(ARGV[2...ARGV.length])
				$stderr.puts "delete #{bucket}:#{path} #{headers.inspect if headers}" if $S3syncOptions['--verbose']
				S3try(:delete, bucket, path) unless $S3syncOptions['--dryrun']
			when "deleteall"
				s3cmdUsage("Need a bucket") if bucket == ''
				headers = hashPairs(ARGV[2...ARGV.length])
				$stderr.puts "delete ALL entries in #{bucket}:#{path} #{headers.inspect if headers}" if $S3syncOptions['--verbose']
				more = true
				marker = nil
				while more do
					res = s3cmdList(bucket, path, nil, nil, marker)
					res.entries.each do |item|
						# the s3 commands (with my modified UTF-8 conversion) expect native char encoding input
						key = Iconv.iconv($S3SYNC_NATIVE_CHARSET, "UTF-8", item.key).join
						$stderr.puts "delete #{bucket}:#{key} #{headers.inspect if headers}" if $S3syncOptions['--verbose']
						S3try(:delete, bucket, key) unless $S3syncOptions['--dryrun']		
					end
					more = res.properties.is_truncated
					marker = (res.properties.next_marker)? res.properties.next_marker : ((res.entries.length > 0) ? res.entries.last.key : nil)
					# get this into local charset; when we pass it to s3 that is what's expected
					marker = Iconv.iconv($S3SYNC_NATIVE_CHARSET, "UTF-8", marker).join if marker
				end
			when "list"
				s3cmdUsage("Need a bucket") if bucket == ''
				max, delim = ARGV[2..3]
				headers = hashPairs(ARGV[4...ARGV.length])
				$stderr.puts "list #{bucket}:#{path} #{max} #{delim} #{headers.inspect if headers}" if $S3syncOptions['--verbose']
				puts "--------------------"
				
				more = true
				marker = nil
				while more do
					res = s3cmdList(bucket, path, max, delim, marker, headers)
					if delim
						res.common_prefix_entries.each do |item|
							
							puts "dir: " + Iconv.iconv($S3SYNC_NATIVE_CHARSET, "UTF-8", item.prefix).join
						end
						puts "--------------------"
					end
					res.entries.each do |item|
						puts Iconv.iconv($S3SYNC_NATIVE_CHARSET, "UTF-8", item.key).join
					end
					if res.properties.is_truncated
						printf "More? Y/n: "
						more = (STDIN.gets.match('^[Yy]?$'))
						marker = (res.properties.next_marker)? res.properties.next_marker : ((res.entries.length > 0) ? res.entries.last.key : nil)
						# get this into local charset; when we pass it to s3 that is what's expected
						marker = Iconv.iconv($S3SYNC_NATIVE_CHARSET, "UTF-8", marker).join if marker
						
					else
						more = false
					end
				end # more
			when "listbuckets"
				headers = hashPairs(ARGV[1...ARGV.length])
				$stderr.puts "list all buckets #{headers.inspect if headers}" if $S3syncOptions['--verbose']
            if $S3syncOptions['--expires-in']
               $stdout.puts S3url(:list_all_my_buckets, headers)
            else
               res = S3try(:list_all_my_buckets, headers)
               res.entries.each do |item|
					   puts item.name
               end
            end
			when "createbucket"
				s3cmdUsage("Need a bucket") if bucket == ''
            lc = ''
            if(ARGV.length > 2)
               lc = '<CreateBucketConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01"><LocationConstraint>' + ARGV[2] + '</LocationConstraint></CreateBucketConfiguration>'
            end
				$stderr.puts "create bucket #{bucket} #{lc}" if $S3syncOptions['--verbose']
				S3try(:create_bucket, bucket, lc) unless $S3syncOptions['--dryrun']
			when "deletebucket"
				s3cmdUsage("Need a bucket") if bucket == ''
				headers = hashPairs(ARGV[2...ARGV.length])
				$stderr.puts "delete bucket #{bucket} #{headers.inspect if headers}" if $S3syncOptions['--verbose']
				S3try(:delete_bucket, bucket, headers) unless $S3syncOptions['--dryrun']
			when "location"
				s3cmdUsage("Need a bucket") if bucket == ''
				headers = hashPairs(ARGV[2...ARGV.length])
            query = Hash.new
            query['location'] = 'location'
				$stderr.puts "location request bucket #{bucket} #{query.inspect} #{headers.inspect if headers}" if $S3syncOptions['--verbose']
				S3try(:get_query_stream, bucket, '', query, headers, $stdout) unless $S3syncOptions['--dryrun']
			when "get"
				s3cmdUsage("Need a bucket") if bucket == ''
				s3cmdUsage("Need a key") if path == ''
				s3cmdUsage("Need a file") if file == ''
				headers = hashPairs(ARGV[3...ARGV.length])
				$stderr.puts "get from key #{bucket}:#{path} into #{file} #{headers.inspect if headers}" if $S3syncOptions['--verbose']
				unless $S3syncOptions['--dryrun']
               if $S3syncOptions['--expires-in']
                  $stdout.puts S3url(:get, bucket, path, headers)
               else
                  outStream = File.open(file, 'wb')
                  outStream = ProgressStream.new(outStream) if $S3syncOptions['--progress']
                  S3try(:get_stream, bucket, path, headers, outStream)
                  outStream.close
               end
				end
			when "put"
				s3cmdUsage("Need a bucket") if bucket == ''
				s3cmdUsage("Need a key") if path == ''
				s3cmdUsage("Need a file") if file == ''
				headers = hashPairs(ARGV[3...ARGV.length])
				stream = File.open(file, 'rb')
				stream = ProgressStream.new(stream, File.stat(file).size) if $S3syncOptions['--progress']
				s3o = S3::S3Object.new(stream, {}) # support meta later?
				headers['Content-Length'] = FileTest.size(file).to_s
				$stderr.puts "put to key #{bucket}:#{path} from #{file} #{headers.inspect if headers}" if $S3syncOptions['--verbose']
				S3try(:put, bucket, path, s3o, headers) unless $S3syncOptions['--dryrun']
				stream.close
			else
				s3cmdUsage
		end

	end #main
	def S3sync.s3cmdList(bucket, path, max=nil, delim=nil, marker=nil, headers={})
		debug(max)
		options = Hash.new
		options['prefix'] = path # start at the right depth
		options['max-keys'] = max ? max.to_s : 100
		options['delimiter'] = delim if delim
		options['marker'] = marker if marker
		S3try(:list_bucket, bucket, options, headers)
	end
	
	# turn an array into a hash of pairs
	def S3sync.hashPairs(ar)
		ret = Hash.new
		ar.each do |item|
			name = (/^(.*?):/.match(item))[1]
			item = (/^.*?:(.*)$/.match(item))[1]
			ret[name] = item
		end if ar
		ret
	end
end #module



def debug(str)
	$stderr.puts str if $S3syncOptions['--debug']
end

S3sync::s3cmdMain #go!
