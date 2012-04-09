#!/usr/bin/ruby
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

module S3Config
  
  confpath = ["#{ENV['S3CONF']}", "#{ENV['HOME']}/.s3conf", "/etc/s3conf"]
  
  confpath.each do |path|
    if File.exists?(path) and File.directory?(path) and File.exists?("#{path}/s3config.yml")
      config = YAML.load_file("#{path}/s3config.yml")
      config.each_pair do |key, value|
        eval("$#{key.upcase} = '#{value}'")
      end
      break
    end
  end
    
end
