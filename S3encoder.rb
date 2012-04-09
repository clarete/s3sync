# This software code is made available "AS IS" without warranties of any        
# kind.  You may copy, display, modify and redistribute the software            
# code either by itself or as incorporated into your code; provided that        
# you do not remove any proprietary notices.  Your use of this software         
# code is at your own risk and you waive any claim against the author
# with respect to your use of this software code. 
# (c) 2007 s3sync.net
#

# The purpose of this file is to overlay the cgi class
# to add some functionality
# (without changing the file itself or requiring a specific version)
# It still isn't perfectly robust, i.e. if radical changes are made
# to the underlying lib this stuff will need updating.

require 'cgi'
require 'iconv' # for UTF-8 conversion

# thanks to http://www.redhillconsulting.com.au/blogs/simon/archives/000326.html
module S3ExtendCGI
	def self.included(base)
		base.extend(ClassMethods)
		base.class_eval do
			class << self
				alias_method :S3Extend_escape_orig, :escape unless method_defined?(:S3Extend_escape_orig)
				alias_method :escape, :S3Extend_escape
			end
		end
	end
	module ClassMethods
		@@exemptSlashesInEscape = false
		attr_writer :exemptSlashesInEscape
		@@usePercent20InEscape = false
		attr_writer :usePercent20InEscape
		@@nativeCharacterEncoding = "ISO-8859-1"
		attr_writer :nativeCharacterEncoding
		@@useUTF8InEscape = false
		attr_writer :useUTF8InEscape
		
		def S3Extend_escape(string)
			result = string
			result = Iconv.iconv("UTF-8", @nativeCharacterEncoding, string).join if @useUTF8InEscape 
			result = S3Extend_escape_orig(result)
			result.gsub!(/%2f/i, "/") if @exemptSlashesInEscape
			result.gsub!("+", "%20") if @usePercent20InEscape
			result
		end
	end
end
CGI.send(:include, S3ExtendCGI)
