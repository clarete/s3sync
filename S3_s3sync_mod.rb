#  This software code is made available "AS IS" without warranties of any
#  kind.  You may copy, display, modify and redistribute the software
#  code either by itself or as incorporated into your code; provided that
#  you do not remove any proprietary notices.  Your use of this software
#  code is at your own risk and you waive any claim against Amazon
#  Digital Services, Inc. or its affiliates with respect to your use of
#  this software code. (c) 2006 Amazon Digital Services, Inc. or its
#  affiliates.
#  
# This software code is made available "AS IS" without warranties of any        
# kind.  You may copy, display, modify and redistribute the software            
# code either by itself or as incorporated into your code; provided that        
# you do not remove any proprietary notices.  Your use of this software         
# code is at your own risk and you waive any claim against the author
# with respect to your use of this software code. 
# (c) 2007 s3sync.net
#
require 'S3'
require 'HTTPStreaming'

# The purpose of this file is to overlay the S3 library from AWS
# to add some functionality
# (without changing the file itself or requiring a specific version)
# It still isn't perfectly robust, i.e. if radical changes are made
# to the underlying lib this stuff will need updating.

module S3
	class AWSAuthConnection
	
      def make_http(bucket='', host='', proxy_host=nil, proxy_port=nil, proxy_user=nil, proxy_pass=nil)

         # build the domain based on the calling format
         server = ''
         if host != ''
           server = host           
         elsif bucket.empty?
           # for a bucketless request (i.e. list all buckets)
           # revert to regular domain case since this operation
           # does not make sense for vanity domains
           server = @server
         elsif @calling_format == CallingFormat::SUBDOMAIN
           server = "#{bucket}.#{@server}" 
         elsif @calling_format == CallingFormat::VANITY
           server = bucket 
         else
           server = @server
         end
         # automatically does the right thing when no proxy
         http = Net::HTTP::Proxy(proxy_host, proxy_port, proxy_user, proxy_pass).new(server, @port)
         #http = Net::HTTP.new(server, @port)
         http.use_ssl = @is_secure
         http.verify_mode=@verify_mode
         http.ca_file=@ca_file
         http.ca_path=@ca_path
         http.start
         return http
      end

		# add support for streaming the response body to an IO stream
		alias __make_request__ make_request
      def make_request(method, bucket='', key='', path_args={}, headers={}, data='', metadata={}, streamOut=nil)
         # build the path based on the calling format
         path = ''
         if (not bucket.empty?) and (@calling_format == CallingFormat::REGULAR)
           path << "/#{bucket}"
         end
         # add the slash after the bucket regardless
         # the key will be appended if it is non-empty
         path << "/#{key}"
   
         # build the path_argument string
         # add the ? in all cases since 
         # signature and credentials follow path args
         path << '?'
         path << S3.path_args_hash_to_string(path_args) 
         
         req = method_to_request_class(method).new("#{path}")
   
         set_headers(req, headers)
         set_headers(req, metadata, METADATA_PREFIX)
         set_headers(req, {'Connection' => 'keep-alive', 'Keep-Alive' => '300'})
         
         set_aws_auth_header(req, @aws_access_key_id, @aws_secret_access_key, bucket, key, path_args)
         
         http = $S3syncHttp
            
         if req.request_body_permitted?
           return http.request(req, data, streamOut)
         else
           return http.request(req, nil, streamOut)
         end
      end

		# a "get" operation that sends the body to an IO stream
		def get_stream(bucket, key, headers={}, streamOut=nil)
         return GetResponse.new(make_request('GET', bucket, CGI::escape(key), {}, headers, '', {}, streamOut))
		end
		
		# a "get" operation that sends the body to an IO stream
		def get_query_stream(bucket, key, path_args={}, headers={}, streamOut=nil)
         return GetResponse.new(make_request('GET', bucket, CGI::escape(key), path_args, headers, '', {}, streamOut))
		end
      
		def head(bucket, key=nil, headers={})
         return GetResponse.new(make_request('HEAD', bucket, CGI::escape(key), {}, headers, '', {}))
		end
      undef create_bucket
      def create_bucket(bucket, object)
         object = S3Object.new(object) if not object.instance_of? S3Object
         return Response.new(
            make_request('PUT', bucket, '', {}, {}, object.data, object.metadata)
         )
      end
      # no, because internally the library does not support the header,wait,body paradigm, so this is useless
      #alias __put__ put
      #def put(bucket, key, object, headers={})
      #   headers['Expect'] = "100-continue"
      #   __put__(bucket, key, object, headers)
      #end

               
		# allow ssl validation
      attr_accessor :verify_mode
      attr_accessor :ca_path
      attr_accessor :ca_file      

	end
   module CallingFormat
      def CallingFormat.string_to_format(s)
         case s
         when 'REGULAR'
           return CallingFormat::REGULAR
         when 'SUBDOMAIN'
           return CallingFormat::SUBDOMAIN
         when 'VANITY'
           return CallingFormat::VANITY
         else
           raise "Unsupported calling format #{s}"
         end
      end
   end
   
end
