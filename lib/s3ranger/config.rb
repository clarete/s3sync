# s3ranger - Tool belt for managing your S3 buckets
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

# This software code is made available "AS IS" without warranties of any
# kind.  You may copy, display, modify and redistribute the software
# code either by itself or as incorporated into your code; provided that
# you do not remove any proprietary notices.  Your use of this software
# code is at your own risk and you waive any claim against the author
# with respect to your use of this software code.
# (c) 2007 alastair brunton
#
# modified to search out the yaml in several places, thanks wkharold.

require 'yaml'
require 's3ranger/exceptions'


module S3Ranger

  class Config < Hash

    REQUIRED_VARS = [:AWS_ACCESS_KEY_ID, :AWS_SECRET_ACCESS_KEY]

    CONFIG_PATHS = ["#{ENV['S3RANGER_PATH']}", "#{ENV['HOME']}/.s3ranger.yml", "/etc/s3ranger.yml"]

    def read_from_file
      paths_checked = []

      CONFIG_PATHS.each do |path|

        # Filtering some garbage
        next if path.nil? or path.strip.empty?

        # Feeding the user feedback in case of failure
        paths_checked << path

        # Time for the dirty work, let's parse the config file and feed our
        # internal hash
        if File.exists? path
          config = YAML.load_file path
          config.each_pair do |key, value|
            self[key.upcase.to_sym] = value
          end
          return 
        end
      end

      return paths_checked
    end

    def read_from_env
      REQUIRED_VARS.each do |v|
        self[v] = ENV[v.to_s] unless ENV[v.to_s].nil?
      end
    end

    def read
      # Reading from file and then trying from env
      paths_checked = read_from_file
      read_from_env

      # Checking which variables we have
      not_found = []

      REQUIRED_VARS.each {|v|
        not_found << v if self[v].nil?
      }

      # Cleaning possibly empty env var from CONFIG_PATH
      paths = (paths_checked || CONFIG_PATHS).select {|e| !e.empty?}
      raise NoConfigFound.new(not_found, paths) if not_found.count > 0
    end
  end
end
