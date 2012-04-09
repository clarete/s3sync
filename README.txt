Welcome to s3sync.rb         
--------------------
Home page, wiki, forum, bug reports, etc: http://s3sync.net

This is a ruby program that easily transfers directories between a local
directory and an S3 bucket:prefix. It behaves somewhat, but not precisely, like
the rsync program. In particular, it shares rsync's peculiar behavior that
trailing slashes on the source side are meaningful. See examples below.

One benefit over some other comparable tools is that s3sync goes out of its way
to mirror the directory structure on S3.  Meaning you don't *need* to use s3sync
later in order to view your files on S3.  You can just as easily use an S3
shell, a web browser (if you used the --public-read option), etc.  Note that
s3sync is NOT necessarily going to be able to read files you uploaded via some
other tool.  This includes things uploaded with the old perl version!  For best
results, start fresh!

s3sync runs happily on linux, probably other *ix, and also Windows (except that
symlinks and permissions management features don't do anything on Windows). If
you get it running somewhere interesting let me know (see below)

s3sync is free, and license terms are included in all the source files. If you
decide to make it better, or find bugs, please let me know.

The original inspiration for this tool is the perl script by the same name which
was made by Thorsten von Eicken (and later updated by me). This ruby program
does not share any components or logic from that utility; the only relation is
that it performs a similar task.


Examples: 
---------
(using S3 bucket 'mybucket' and prefix 'pre')
  Put the local etc directory itself into S3
        s3sync.rb  -r  /etc  mybucket:pre
        (This will yield S3 keys named  pre/etc/...)
  Put the contents of the local /etc dir into S3, rename dir:
        s3sync.rb  -r  /etc/  mybucket:pre/etcbackup
        (This will yield S3 keys named  pre/etcbackup/...)
  Put contents of S3 "directory" etc into local dir
        s3sync.rb  -r  mybucket:pre/etc/  /root/etcrestore
        (This will yield local files at  /root/etcrestore/...)
  Put the contents of S3 "directory" etc into a local dir named etc
        s3sync.rb  -r  mybucket:pre/etc  /root
        (This will yield local files at  /root/etc/...)
  Put S3 nodes under the key pre/etc/ to the local dir etcrestore
  **and create local dirs even if S3 side lacks dir nodes**
        s3sync.rb  -r  --make-dirs  mybucket:pre/etc/  /root/etcrestore
        (This will yield local files at  /root/etcrestore/...)


Prerequisites:
--------------
You need a functioning Ruby (>=1.8.4) installation, as well as the OpenSSL ruby 
library (which may or may not come with your ruby).

How you get these items working on your system is really not any of my 
business, but you might find the following things helpful.  If you're using 
Windows, the ruby site has a useful "one click installer" (although it takes 
more clicks than that, really).  On debian (and ubuntu, and other debian-like 
things), there are apt packages available for ruby and the open ssl lib.


Your environment:
-----------------
s3sync needs to know several interesting values to work right.  It looks for 
them in the following environment variables -or- a s3config.yml file.
In the yml case, the names need to be lowercase (see example file).
Furthermore, the yml is searched for in the following locations, in order:
   $S3CONF/s3config.yml
   $HOME/.s3conf/s3config.yml
   /etc/s3conf/s3config.yml

Required:
	AWS_ACCESS_KEY_ID
	AWS_SECRET_ACCESS_KEY
	
	If you don't know what these are, then s3sync is probably not the
	right tool for you to be starting out with.
Optional:
	AWS_S3_HOST - I don't see why the default would ever be wrong
   HTTP_PROXY_HOST,HTTP_PROXY_PORT,HTTP_PROXY_USER,HTTP_PROXY_PASSWORD - proxy
	SSL_CERT_DIR - Where your Cert Authority keys live; for verification
	SSL_CERT_FILE - If you have just one PEM file for CA verification
	S3SYNC_RETRIES - How many HTTP errors to tolerate before exiting
	S3SYNC_WAITONERROR - How many seconds to wait after an http error
	S3SYNC_MIME_TYPES_FILE - Where is your mime.types file
	S3SYNC_NATIVE_CHARSET - For example Windows-1252.  Defaults to ISO-8859-1.
   AWS_CALLING_FORMAT - Defaults to REGULAR
       REGULAR   # http://s3.amazonaws.com/bucket/key
       SUBDOMAIN # http://bucket.s3.amazonaws.com/key
       VANITY    # http://<vanity_domain>/key  

Important: For EU-located buckets you should set the calling format to SUBDOMAIN
Important: For US buckets with CAPS or other weird traits set the calling format 
to REGULAR

I use "envdir" from the daemontools package to set up my env 
variables easily: http://cr.yp.to/daemontools/envdir.html
For example:
	envdir /root/s3sync/env /root/s3sync/s3sync.rb -etc etc etc
I know there are other similar tools out there as well.  

You can also just call it in a shell script where you have exported the vars 
first such as:
#!/bin/bash
export AWS_ACCESS_KEY_ID=valueGoesHere
...
s3sync.rb -etc etc etc

But by far the easiest (and newest) way to set this up is to put the name:value
pairs in a file named s3config.yml and let the yaml parser pick them up. There
is an .example file shipped with the tar.gz to show what a yaml file looks like.
Thanks to Alastair Brunton for this addition.

You can also use some combination of .yaml and environment variables, if you
want. Go nuts.


Management tasks
----------------
For low-level S3 operations not encapsulated by the sync paradigm, try the
companion utility s3cmd.rb. See README_s3cmd.txt.


About single files
------------------
s3sync lacks the special case code that would be needed in order to handle a
source/dest that's a single file. This isn't one of the supported use cases so
don't expect it to work. You can use the companion utility s3cmd.rb for single
get/puts.


About Directories, the bane of any S3 sync-er
--------------------------------------------- 
In S3 there's no actual concept of folders, just keys and nodes. So, every tool
uses its own proprietary way of storing dir info (my scheme being the best
naturally) and in general the methods are not compatible.

If you populate S3 by some means *other than* s3sync and then try to use s3sync
to "get" the S3 stuff to a local filesystem, you will want to use the
--make-dirs option. This causes the local dirs to be created even if there is no
s3sync-compatible directory node info stored on the S3 side. In other words,
local folders are conjured into existence whenever they are needed to make the
"get" succeed.


About MD5 hashes
----------------
s3sync's normal operation is to compare the file size and MD5 hash of each item
to decide whether it needs syncing.  On the S3 side, these hashes are stored and
returned to us as the "ETag" of each item when the bucket is listed, so it's
very easy.  On the local side, the MD5 must be calculated by pushing every byte
in the file through the MD5 algorithm.  This is CPU and IO intensive!  

Thus you can specify the option --no-md5. This will compare the upload time on
S3 to the "last modified" time on the local item, and not do md5 calculations
locally at all. This might cause more transfers than are absolutely necessary.
For example if the file is "touched" to a newer modified date, but its contents
didn't change. Conversely if a file's contents are modified but the date is not
updated, then the sync will pass over it.  Lastly, if your clock is very
different from the one on the S3 servers, then you may see unanticipated
behavior.


A word on SSL_CERT_DIR:
-----------------------
On my debian install I didn't find any root authority public keys.  I installed
some by running this shell archive: 
http://mirbsd.mirsolutions.de/cvs.cgi/src/etc/ssl.certs.shar
(You have to click download, and then run it wherever you want the certs to be
placed).  I do not in any way assert that these certificates are good,
comprehensive, moral, noble, or otherwise correct.  But I am using them.

If you don't set up a cert dir, and try to use ssl, then you'll 1) get an ugly
warning message slapped down by ruby, and 2) not have any protection AT ALL from
malicious servers posing as s3.amazonaws.com.  Seriously... you want to get
this right if you're going to have any sensitive data being tossed around.
--
There is a debian package ca-certificates; this is what I'm using now.
apt-get install ca-certificates
and then use:
SSL_CERT_DIR=/etc/ssl/certs

You used to be able to use just one certificate, but recently AWS has started
using more than one CA.


Getting started:
----------------
Invoke by typing s3sync.rb and you should get a nice usage screen.
Options can be specified in short or long form (except --delete, which has no 
short form)

ALWAYS TEST NEW COMMANDS using --dryrun(-n) if you want to see what will be
affected before actually doing it. ESPECIALLY if you use --delete. Otherwise, do
not be surprised if you misplace a '/' or two and end up deleting all your
precious, precious files.

If you use the --public-read(-p) option, items sent to S3 will be ACL'd so that
anonymous web users can download them, given the correct URL. This could be
useful if you intend to publish directories of information for others to see.
For example, I use s3sync to publish itself to its home on S3 via the following
command: s3sync.rb -v -p publish/ ServEdge_pub:s3sync Where the files live in a
local folder called "publish" and I wish them to be copied to the URL:
http://s3.amazonaws.com/ServEdge_pub/s3sync/... If you use --ssl(-s) then your
connections with S3 will be encrypted. Otherwise your data will be sent in clear
form, i.e. easy to intercept by malicious parties.

If you want to prune items from the destination side which are not found on the
source side, you can use --delete. Always test this with -n first to make sure
the command line you specify is not going to do something terrible to your
cherished and irreplaceable data.


Updates and other discussion: 
----------------------------- 
The latest version of s3sync should normally be at:
	http://s3.amazonaws.com/ServEdge_pub/s3sync/s3sync.tar.gz 
and the Amazon S3 forums probably have a few threads going on it at any given
time. I may not always see things posted to the threads, so if you want you can
contact me at gbs-s3@10forward.com too.


Change Log:
-----------

2006-09-29:
Added support for --expires and --cache-control. Eg:
--expires="Thu, 01 Dec 2007 16:00:00 GMT"
--cache-control="no-cache"

Thanks to Charles for pointing out the need for this, and supplying a patch
proving that it would be trivial to add =) Apologies for not including the short
form (-e) for the expires. I have a rule that options taking arguments should
use the long form.
----------

2006-10-04
Several minor debugs and edge cases.
Fixed a bug where retries didn't rewind the stream to start over.
----------

2006-10-12
Version 1.0.5
Finally figured out and fixed bug of trying to follow local symlink-to-directory.
Fixed a really nasty sorting discrepancy that caused problems when files started
with the same name as a directory.
Retry on connection-reset on the S3 side.
Skip files that we can't read instead of dying.
----------

2006-10-12
Version 1.0.6
Some GC voodoo to try and keep a handle on the memory footprint a little better.
There is still room for improvement here.
----------

2006-10-13
Version 1.0.7
Fixed symlink dirs being stored to S3 as real dirs (and failing with 400)
Added a retry catch for connection timeout error.
(Hopefully) caught a bug that expected every S3 listing to contain results
----------

2006-10-14
Version 1.0.8
Was testing for file? before symlink? in localnode.stream. This meant that for
symlink files it was trying to shove the real file contents into the symlink
body on s3.
----------

2006-10-14
Version 1.0.9
Woops, I was using "max-entries" for some reason but the proper header is
"max-keys".  Not a big deal.
Broke out the S3try stuff into a separate file so I could re-use it for s3cmd.rb
----------

2006-10-16
Added a couple debug lines; not even enough to call it a version revision.
----------

2006-10-25
Version 1.0.10
UTF-8 fixes.
Catching a couple more retry-able errors in s3try (instead of aborting the
program).
----------

2006-10-26
Version 1.0.11
Revamped some details of the generators and comparator so that directories are
handled in a more exact and uniform fashion across local and S3. 
----------

2006-11-28
Version 1.0.12
Added a couple more error catches to s3try.
----------

2007-01-08
Version 1.0.13
Numerous small changes to slash and path handling, in order to catch several 
cases where "root" directory nodes were not being created on S3.
This makes restores work a lot more intuitively in many cases.
----------

2007-01-25
Version 1.0.14
Peter Fales' marker fix.
Also, markers should be decoded into native charset (because that's what s3
expects to see).
----------

2007-02-19
Version 1.1.0
*WARNING* Lots of path-handling changes. *PLEASE* test safely before you just
swap this in for your working 1.0.x version.

- Adding --exclude (and there was much rejoicing).
- Found Yet Another Leading Slash Bug with respect to local nodes. It was always
"recursing" into the first folder even if there was no trailing slash and -r
wasn't specified. What it should have done in this case is simply create a node
for the directory itself, then stop (not check the dir's contents).
- Local node canonicalization was (potentially) stripping the trailing slash,
which we need in order to make some decisios in the local generator.
- Fixed problem where it would prepend a "/" to s3 key names even with blank
prefix.
- Fixed S3->local when there's no "/" in the source so it doesn't try to create
a folder with the bucket name. 
- Updated s3try and s3_s3sync_mod to allow SSL_CERT_FILE
----------

2007-02-22
Version 1.1.1
Fixed dumb regression bug caused by the S3->local bucket name fix in 1.1.0
----------

2007-02-25
Version 1.1.2
Added --progress
----------

2007-06-02
Version 1.1.3
IMPORTANT!
Pursuant to http://s3sync.net/forum/index.php?topic=49.0 , the tar.gz now
expands into its own sub-directory named "s3sync" instead of dumping all the
files into the current directory.

In the case of commands of the form:
	s3sync -r somedir somebucket:
The root directory node in s3 was being stored as "somedir/" instead of "somedir"
which caused restores to mess up when you say:
	s3sync -r somebucket: restoredir
The fix to this, by coincidence, actually makes s3fox work even *less* well with 
s3sync.  I really need to build my own xul+javascript s3 GUI some day.

Also fixed some of the NoMethodError stuff for when --progress is used
and caught Errno::ETIMEDOUT
----------

2007-07-12
Version 1.1.4
Added Alastair Brunton's yaml config code.
----------

2007-11-17
Version 1.2.1
Compatibility for S3 API revisions.
When retries are exhausted, emit an error.
Don't ever try to delete the 'root' local dir.    
----------

2007-11-20
Version 1.2.2
Handle EU bucket 307 redirects (in s3try.rb)
--make-dirs added
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

2008-05-11
Version 1.2.5
Added option --no-md5
----------

2008-06-16
Version 1.2.6
Catch connect errors and retry.
----------

FNORD