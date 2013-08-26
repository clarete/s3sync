#!/usr/bin/env ruby
# This software code is made available "AS IS" without warranties of any
# kind.  You may copy, display, modify and redistribute the software
# code either by itself or as incorporated into your code; provided that
# you do not remove any proprietary notices.  Your use of this software
# code is at your own risk and you waive any claim against the author
# with respect to your use of this software code.
# (c) 2007 s3sync.net
#

require 'getoptlong'


module S3sync

  include S3Config

  def S3sync.s3cmdMain
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

    S3sync::s3trySetup

    command, path, file = ARGV

    s3cmdUsage("You didn't set up your environment variables; see README.txt") if not($AWS_ACCESS_KEY_ID and $AWS_SECRET_ACCESS_KEY)
    s3cmdUsage("Need a command (etc)") if not command

    path = '' unless path
    path = path.dup # modifiable
    path += ':' unless path.match(':')
    bucket = (/^(.*?):/.match(path))[1]
    path.replace((/:(.*)$/.match(path))[1])

    case command
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
          key = utf8(item.key)
          $stderr.puts "delete #{bucket}:#{key} #{headers.inspect if headers}" if $S3syncOptions['--verbose']
          S3try(:delete, bucket, key) unless $S3syncOptions['--dryrun']
        end
        more = res.properties.is_truncated
        marker = (res.properties.next_marker)? res.properties.next_marker : ((res.entries.length > 0) ? res.entries.last.key : nil)
        # get this into local charset; when we pass it to s3 that is what's expected
        marker = utf8(marker) if marker
      end
    when "location"
      s3cmdUsage("Need a bucket") if bucket == ''
      headers = hashPairs(ARGV[2...ARGV.length])
      query = Hash.new
      query['location'] = 'location'
      $stderr.puts "location request bucket #{bucket} #{query.inspect} #{headers.inspect if headers}" if $S3syncOptions['--verbose']
      S3try(:get_query_stream, bucket, '', query, headers, $stdout) unless $S3syncOptions['--dryrun']
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
