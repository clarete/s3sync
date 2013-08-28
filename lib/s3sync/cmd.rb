# (c) 2013  Lincoln de Sousa <lincoln@clarete.li>
# (c) 2007 s3sync.net
#
# This software code is made available "AS IS" without warranties of any
# kind.  You may copy, display, modify and redistribute the software
# code either by itself or as incorporated into your code; provided that
# you do not remove any proprietary notices.  Your use of this software
# code is at your own risk and you waive any claim against the author
# with respect to your use of this software code.

require 'getoptlong'
require 's3sync/commands'
require 's3sync/util'

module S3sync

  class Cmd

    def initialize(conf = conf)
      # The chain that initializes our command and find the right action
      options, command, bucket, key, file = read_info_from_args(parse_args())

      # Finding the right command to run
      (cmd = find_cmd(command)) || (raise WrongUsage.new(nil, "Command `#{command}' does not exist"))

      # Now that we're sure we have things to do, we need to connect to amazon
      s3 = AWS::S3.new(
        :access_key_id => conf[:AWS_ACCESS_KEY_ID],
        :secret_access_key => conf[:AWS_SECRET_ACCESS_KEY],
      )

      # Calling the actuall command
      cmd.call({
        :options => options,
        :s3 => s3,
        :bucket => bucket,
        :key => key,
        :file => file,
      })
    end

    def find_cmd name
      sym = "_cmd_#{name}".to_sym
      return nil unless Commands.public_methods.include? sym
      return Commands.method sym
    end

    def parse_args
      options = Hash.new

      args = [
        ['--help',       '-h', GetoptLong::NO_ARGUMENT],
        ['--force',      '-f', GetoptLong::NO_ARGUMENT],
        ['--acl',        '-a', GetoptLong::REQUIRED_ARGUMENT],
        ['--method',     '-m', GetoptLong::REQUIRED_ARGUMENT],
        ['--no-ssl',           GetoptLong::NO_ARGUMENT],
        ['--expires-in',       GetoptLong::REQUIRED_ARGUMENT],
      ]

      begin
        GetoptLong.new(*args).each {|opt, arg| options[opt] = (arg || true)}
      rescue StandardError => exc
        raise WrongUsage.new nil, exc.message
      end

      # Let's just show the help to the user
      raise WrongUsage.new(0, nil) if options['--help']

      # Returning the options to the next level
      options
    end

    def read_info_from_args(options)
      # Parsing expre date
      if options['--expires-in'] =~ /d|h|m|s/

        val = 0

        options['--expires-in'].scan(/(\d+\w)/) do |track|
          _, num, what = /(\d+)(\w)/.match(track[0]).to_a
          num = num.to_i

          case what
          when "d"; val += num * 86400
          when "h"; val += num * 3600
          when "m"; val += num * 60
          when "s"; val += num
          end
        end

        options['--expires-in'] = val
      end

      # Reading what to do from the user
      command = ARGV.shift
      raise WrongUsage.new(nil, "Need a command (eg.: `list', `listbuckets', etc)") if not command

      key, file = ARGV

      # Parsing the bucket name
      bucket = nil
      bucket, key = key.split(':') if key

      # Returning things we need in the next level
      [options, command, bucket, key, file]
    end
  end
end
