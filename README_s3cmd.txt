Welcome to s3cmd.rb 
------------------- 
This is a ruby program that wraps S3 operations into a simple command-line tool.
It is inspired by things like rsh3ll, #sh3ll, etc., but shares no code from
them. It's meant as a companion utility to s3sync.rb but could be used on its
own (provided you have read the other readme file and know how to use s3sync in
theory).

I made this even though lots of other "shell"s exist, because I wanted a
single-operation utility, instead of a shell "environment".  This lends itself
more to scripting, etc.  Also the delete operation on rsh3ll seems to be borken
at the moment? =(

Users not yet familiar with s3sync should read about that first, since s3cmd and
s3sync share a tremendous amount of conventions and syntax. Particularly you
have to set up environment variables prior to calling s3cmd, and s3cmd also uses
the "bucket:key" syntax popularized by s3sync. Many of the options are the same
too. Really, go read the other readme first if you haven't used s3sync yet.
Otherwise you will become confused.  It's OK, I'll wait.

....

In general, s3sync and s3cmd complement each other. s3sync is useful to perform
serious synchronization operations, and s3cmd allows you to do simple things
such as bucket management, listing, transferring single files, and the like.

Here is the usage, with examples to follow.

s3cmd.rb [options] <command> [arg(s)]           version 1.0.0
  --help    -h        --verbose     -v     --dryrun    -n
  --ssl     -s        --debug       -d

Commands:
s3cmd.rb  listbuckets  [headers]
s3cmd.rb  createbucket|deletebucket  <bucket>  [headers]
s3cmd.rb  list  <bucket>[:prefix]  [max/page]  [delimiter]  [headers]
s3cmd.rb  delete  <bucket>:key  [headers]
s3cmd.rb  deleteall  <bucket>[:prefix]  [headers]
s3cmd.rb  get|put  <bucket>:key  <file>  [headers]


A note about [headers]
----------------------
For some S3 operations, such as "put", you might want to specify certain headers
to the request such as Cache-Control, Expires, x-amz-acl, etc.  Rather than
supporting a load of separate command-line options for these, I just allow
header specification.  So to upload a file with public-read access you could
say:
	s3cmd.rb  put  MyBucket:TheFile.txt  x-amz-acl:public-read

If you don't need to add any particular headers then you can just ignore this
whole [headers] thing and pretend it's not there.  This is somewhat of an
advanced option.


Examples
--------
List all the buckets your account owns:
	s3cmd.rb listbuckets

Create a new bucket:
	s3cmd.rb createbucket BucketName

Create a new bucket in the EU:
	s3cmd.rb createbucket BucketName EU
   
Find out the location constraint of a bucket:
   s3cmd.rb location BucketName

Delete an old bucket you don't want any more:
	s3cmd.rb deletebucket BucketName
	
Find out what's in a bucket, 10 lines at a time:
	s3cmd.rb list BucketName 10
	
Only look in a particular prefix:
	s3cmd.rb list BucketName:startsWithThis
	
Look in the virtual "directory" named foo;
lists sub-"directories" and keys that are at this level.
Note that if you specify a delimiter you must specify a max before it.
(until I make the options parsing smarter)
	s3cmd.rb list BucketName:foo/  10  /

Delete a key:
	s3cmd.rb delete BucketName:AKey

Delete all keys that match (like a combo between list and delete):
	s3cmd.rb deleteall BucketName:SomePrefix
	
Only pretend you're going to delete all keys that match, but list them: 
	s3cmd.rb  --dryrun  deleteall  BucketName:SomePrefix
	
Delete all keys in a bucket (leaving the bucket):
	s3cmd.rb deleteall BucketName
	
Get a file from S3 and store it to a local file
	s3cmd.rb get BucketName:TheFileOnS3.txt  ALocalFile.txt
	
Put a local file up to S3 
Note we don't automatically set mime type, etc.
NOTE that the order of the options doesn't change. S3 stays first!
	s3cmd.rb put BucketName:TheFileOnS3.txt ALocalFile.txt

	
Change Log:
-----------
2006-10-14:
Created.
-----------

2006-10-16
Version 1.0.1
Force content length to a string value since some ruby's don't convert it right.
-----------

2006-10-25
UTF-8 fixes.
-----------

2006-11-28
Version 1.0.3
Added a couple more error catches to s3try.
----------

2007-01-25
Version 1.0.4
Peter Fales' marker fix.
Also, markers should be decoded into native charset (because that's what s3
expects to see).
----------

2007-02-19
- Updated s3try and s3_s3sync_mod to allow SSL_CERT_FILE
----------

2007-2-25
Added --progress
----------

2007-07-12
Version 1.0.6
Added Alastair Brunton's yaml config code.
----------

2007-11-17
Version 1.2.1
Compatibility for S3 API revisions.
When retries are exhausted, emit an error.
----------

2007-11-20
Version 1.2.2
Handle EU bucket 307 redirects (in s3try.rb)
----------

2007-11-20
Version 1.2.3
Fix SSL verification settings that broke in new S3 API.
----------

2008-01-06
Version 1.2.4
Run from any dir (search "here" for includes).
Search out s3config.yml in some likely places.
Reset connection (properly) on retry-able non-50x errors.
Fix calling format bug preventing it from working from yml.
Added http proxy support.
----------


FNORD