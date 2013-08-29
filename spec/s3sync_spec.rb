require 'spec_helper.rb'
require 's3sync/cmd'
require 's3sync/config'
require 's3sync/commands'
require 's3sync/sync'

include S3sync

describe "Parsing command line arguments" do

  describe "Processing the final destination based on how the user expressed the source" do

    it "Put the local etc directory itself into S3" do
      source = "/etc"
      destination = "mybucket:pre"

      # This will yield S3 keys named  pre/etc/...
      SyncCommand.process_destination(source, destination).should be_eql ["/etc", ["pre/etc/", "mybucket"]]
    end

    it "Put the contents of the local /etc dir into S3, rename dir" do
      source = "/etc/"
      destination = "mybucket:pre/etcbackup"

      # This will yield S3 keys named  pre/etcbackup/...
      SyncCommand.process_destination(source, destination).should be_eql ["/etc/", ["pre/etcbackup/", "mybucket"]]
    end

    it "Put contents of S3 \"directory\" etc into local dir" do
      source = "mybucket:pre/etc/"
      destination = "/root/etcrestore"

      # This will yield local files at  /root/etcrestore/...
      SyncCommand.process_destination(source, destination).should be_eql [["pre/etc/", "mybucket"], "/root/etcrestore/"]
    end

    it "Put the contents of S3 \"directory\" etc into a local dir named etc" do
      source = "mybucket:pre/etc"
      destination = "/root"

      # This will yield local files at  /root/etc/...
      SyncCommand.process_destination(source, destination).should be_eql [["pre/etc", "mybucket"], "/root/etc/"]
    end

    it "Put S3 nodes under the key pre/etc/ to the local dir etcrestore" do
      source = "mybucket:pre/etc/"
      destination = "/root/etcrestore"

      # This will yield local files at  /root/etcrestore/...
      SyncCommand.process_destination(source, destination).should be_eql [["pre/etc/", "mybucket"], "/root/etcrestore/"]
    end
  end

  it "Returning locations based on the parsed destination" do
    source = "/etc"
    destination = "mybucket:pre"

    # When I parse the above arguments using the SyncCommand
    src_location, dst_location = SyncCommand.parse_params [source, destination]

    # Then I see I got the locations with the right params
    src_location.should be_eql S3sync::Location.new("/etc")
    dst_location.should be_eql S3sync::Location.new("pre/etc/", "mybucket")
  end
end

describe "Comparing file lists" do
  it "should be possible to compare two lists of files" do

    # Given that I have two lists of Nodes to compare
    list1 = [Node.new("file1", "f", 10), Node.new("file2", "f", 12), Node.new("file3", "f", 12)]
    list2 = [Node.new("file1", "f", 10), Node.new("file2", "f", 22), Node.new("file4", "f", 22),]

    # When I compare those two file lists
    same_in_both, to_be_added_to_list2, to_be_removed_from_list2 = SyncCommand.cmp list1, list2

    # Then I see that the three lists that I requested were returned with the
    # right content
    same_in_both.should == [Node.new("file1", "f", 10)]     # Just testing our == operator
    same_in_both.should be_eql [Node.new("file1", "f", 10)]
    to_be_added_to_list2.should be_eql [Node.new("file2", "f", 12), Node.new("file3", "f", 12)]
    to_be_removed_from_list2.should be_eql [Node.new("file4", "f", 22)]
  end
end
