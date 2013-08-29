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
    def read
      paths_checked = []

      ["#{ENV['S3CONF']}", "#{ENV['HOME']}/.s3conf", "/etc/s3conf"].each do |path|

        # Filtering some garbage
        next if path.nil? or path.strip.empty?

        # Feeding the user feedback in case of failure
        paths_checked << path

        # Time for the dirty work, let's parse the config file and feed our
        # internal hash
        if File.exists?("#{path}/s3config.yml")
          config = YAML.load_file("#{path}/s3config.yml")
          config.each_pair do |key, value|
            self[key.upcase.to_sym] = value
          end
          return
        end
      end

      raise NoConfigFound.new paths_checked
    end
  end
end
