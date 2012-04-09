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

	$AWS_ACCESS_KEY_ID = ENV["AWS_ACCESS_KEY_ID"]           
	$AWS_SECRET_ACCESS_KEY = ENV["AWS_SECRET_ACCESS_KEY"]   
	$AWS_S3_HOST = (ENV["AWS_S3_HOST"] or "s3.amazonaws.com")
   $HTTP_PROXY_HOST = ENV["HTTP_PROXY_HOST"]
   $HTTP_PROXY_PORT = ENV["HTTP_PROXY_PORT"]
   $HTTP_PROXY_USER = ENV["HTTP_PROXY_USER"]
   $HTTP_PROXY_PASSWORD = ENV["HTTP_PROXY_PASSWORD"]
	$SSL_CERT_DIR = ENV["SSL_CERT_DIR"]
	$SSL_CERT_FILE = ENV["SSL_CERT_FILE"]
	$S3SYNC_RETRIES = (ENV["S3SYNC_RETRIES"] or 100).to_i # number of errors to tolerate 
	$S3SYNC_WAITONERROR = (ENV["S3SYNC_WAITONERROR"] or 30).to_i # seconds
	$S3SYNC_NATIVE_CHARSET = (ENV["S3SYNC_NATIVE_CHARSET"] or "ISO-8859-1")
	$AWS_CALLING_FORMAT = (ENV["AWS_CALLING_FORMAT"] or "REGULAR")
   
	require 'S3'

	require 'HTTPStreaming'
	require 'S3encoder'
	CGI::exemptSlashesInEscape = true
	CGI::usePercent20InEscape = true
	CGI::useUTF8InEscape = true
	CGI::nativeCharacterEncoding = $S3SYNC_NATIVE_CHARSET
	require 'S3_s3sync_mod'


	$S3syncRetriesLeft = $S3SYNC_RETRIES.to_i
	
	def S3sync.s3trySetup 	
		
		# ---------- CONNECT ---------- #

		$S3syncConnection = S3::AWSAuthConnection.new($AWS_ACCESS_KEY_ID, $AWS_SECRET_ACCESS_KEY, $S3syncOptions['--ssl'], $AWS_S3_HOST)
      $S3syncConnection.calling_format = S3::CallingFormat::string_to_format($AWS_CALLING_FORMAT)
		if $S3syncOptions['--ssl']
			if $SSL_CERT_DIR
				$S3syncConnection.verify_mode = OpenSSL::SSL::VERIFY_PEER
				$S3syncConnection.ca_path = $SSL_CERT_DIR
			elsif $SSL_CERT_FILE
				$S3syncConnection.verify_mode = OpenSSL::SSL::VERIFY_PEER
				$S3syncConnection.ca_file = $SSL_CERT_FILE
			end
		end
	end
	def S3sync.s3urlSetup 	
		$S3syncGenerator = S3::QueryStringAuthGenerator.new($AWS_ACCESS_KEY_ID, $AWS_SECRET_ACCESS_KEY, $S3syncOptions['--ssl'], $AWS_S3_HOST)
      $S3syncGenerator.calling_format = S3::CallingFormat::string_to_format($AWS_CALLING_FORMAT)
      $S3syncGenerator.expires_in = $S3syncOptions['--expires-in']
	end
   
   def S3sync.S3tryConnect(bucket, host='')
         $S3syncHttp = $S3syncConnection.make_http(bucket, host, $HTTP_PROXY_HOST, $HTTP_PROXY_PORT, $HTTP_PROXY_USER, $HTTP_PROXY_PASSWORD)
   end
	
	def S3sync.S3try(command, bucket, *args)
      if(not $S3syncHttp or (bucket != $S3syncLastBucket))
         $stderr.puts "Creating new connection" if $S3syncOptions['--debug']
         $S3syncLastBucket = bucket
         while $S3syncRetriesLeft > 0 do
            begin
               S3sync.S3tryConnect(bucket)
               break
            rescue Errno::ECONNRESET => e
               $stderr.puts "Connection reset: #{e}" 
            rescue Errno::ECONNABORTED => e
               $stderr.puts "Connection aborted: #{e}" 
            rescue Errno::ETIMEDOUT => e
               $stderr.puts "Connection timed out: #{e}"
            rescue Timeout::Error => e
               $stderr.puts "Connection timed out: #{e}" 
            end
            $S3syncRetriesLeft -= 1
            $stderr.puts "#{$S3syncRetriesLeft} retries left, sleeping for #{$S3SYNC_WAITONERROR} seconds"
            Kernel.sleep $S3SYNC_WAITONERROR.to_i
         end
      end
      
		result = nil
		delim = $,
		$,=' '
		while $S3syncRetriesLeft > 0 do
         $stderr.puts "Trying command #{command} #{bucket} #{args} with #{$S3syncRetriesLeft} retries left" if $S3syncOptions['--debug']
			forceRetry = false
         now = false
         hush = false
			begin
				result = $S3syncConnection.send(command, bucket, *args)
			rescue Errno::EPIPE => e
				forceRetry = true
				$stderr.puts "Broken pipe: #{e}" 
			rescue Errno::ECONNRESET => e
				forceRetry = true
				$stderr.puts "Connection reset: #{e}" 
			rescue Errno::ECONNABORTED => e
				forceRetry = true
				$stderr.puts "Connection aborted: #{e}" 
			rescue Errno::ETIMEDOUT => e
				forceRetry = true
				$stderr.puts "Connection timed out: #{e}"
			rescue Timeout::Error => e
				forceRetry = true
				$stderr.puts "Connection timed out: #{e}" 
			rescue EOFError => e
				# i THINK this is happening like a connection reset
				forceRetry = true
				$stderr.puts "EOF error: #{e}"
			rescue OpenSSL::SSL::SSLError => e
				forceRetry = true
				$stderr.puts "SSL Error: #{e}"
			rescue NoMethodError => e
				# we get this when using --progress, and the local item is something unreadable
				$stderr.puts "Null stream error: #{e}"
				break
			end
         if forceRetry
				# kill and reset connection when we receive a non-50x yet retry-able error
				S3sync.S3tryConnect(bucket)
         end
			begin
				debug("Response code: #{result.http_response.code}")
				break if ((200...300).include? result.http_response.code.to_i) and (not forceRetry)
            if result.http_response.code.to_i == 301
               $stderr.puts "Permanent redirect received. Try setting AWS_CALLING_FORMAT to SUBDOMAIN"
            elsif result.http_response.code.to_i == 307
               # move to the other host
               host = %r{https?://([^/]+)}.match(result.http_response['Location'])[1]
               $stderr.puts("Temporary Redirect to: " + host)
               debug("Host: " + host)
               S3sync.S3tryConnect(bucket, host)
               $S3syncRetriesLeft = $S3syncRetriesLeft+1 # don't use one up below
               forceRetry = true
               now = true
               hush = true
            else
               $stderr.puts "S3 command failed:\n#{command} #{args}"
               $stderr.puts "With result #{result.http_response.code} #{result.http_response.message}\n"
               debug(result.http_response.body)
            end
				# only retry 500's, per amazon
				break unless ((500...600).include? result.http_response.code.to_i) or forceRetry
			rescue NoMethodError
				debug("No result available")
			end
			$S3syncRetriesLeft -= 1
			$stderr.puts "#{$S3syncRetriesLeft} retries left, sleeping for #{$S3SYNC_WAITONERROR} seconds" unless hush
			Kernel.sleep $S3SYNC_WAITONERROR.to_i unless now
		end
      if $S3syncRetriesLeft <= 0
         $stderr.puts "Ran out of retries; operations did not complete!"
      end
		$, = delim
		result
	end
   
	def S3sync.S3url(command, bucket, *args)
      S3sync.s3urlSetup() unless $S3syncGenerator
		result = nil
		delim = $,
		$,=' '
      $stderr.puts "Calling command #{command} #{bucket} #{args}" if $S3syncOptions['--debug']
      result = $S3syncGenerator.send(command, bucket, *args)
		$, = delim
		result
	end
	
end #module

