require 'spec_helper.rb'
require 's3sync/cli'
require 's3sync/config'
require 's3sync/sync'

include S3Sync

describe "Parsing command line arguments" do

  describe "Processing the final destination based on how the user expressed the source" do

    it "Put the local etc directory itself into S3" do
      source = "/etc"
      destination = "mybucket:pre"

      # This will yield S3 keys named  pre/etc/...
      expect(SyncCommand.process_destination(source, destination)).to eql(["/etc", ["pre/etc/", "mybucket"]])
    end

    it "Put the contents of the local /etc dir into S3, rename dir" do
      source = "/etc/"
      destination = "mybucket:pre/etcbackup"

      # This will yield S3 keys named  pre/etcbackup/...
      expect(SyncCommand.process_destination(source, destination)).to eql(["/etc/", ["pre/etcbackup/", "mybucket"]])
    end

    it "Put the contents of the local /tmp/sync/ in to the root of an S3 bucket" do
      source = "/tmp/sync/"
      destination = "mybucket:"

      # This will yield S3 keys named  '...' (The root is just empty)
      expect(SyncCommand.process_destination(source, destination)).to eql(["/tmp/sync/", ["", "mybucket"]])
    end

    it "Put contents of S3 \"directory\" etc into local dir" do
      source = "mybucket:pre/etc/"
      destination = "/root/etcrestore"

      # This will yield local files at  /root/etcrestore/...
      expect(SyncCommand.process_destination(source, destination)).to eql([["pre/etc/", "mybucket"], "/root/etcrestore/"])
    end

    it "Put the contents of S3 \"directory\" etc into a local dir named etc" do
      source = "mybucket:pre/etc"
      destination = "/root"

      # This will yield local files at  /root/etc/...
      expect(SyncCommand.process_destination(source, destination)).to eql([["pre/etc", "mybucket"], "/root/etc/"])
    end

    it "Put S3 nodes under the key pre/etc/ to the local dir etcrestore" do
      source = "mybucket:pre/etc/"
      destination = "/root/etcrestore"

      # This will yield local files at  /root/etcrestore/...
      expect(SyncCommand.process_destination(source, destination)).to eql([["pre/etc/", "mybucket"], "/root/etcrestore/"])
    end

    it "Put S3 nodes under an empty key (root) to the local dir /tmp/lib" do
      source = "mybucket:"
      destination = "/tmp/lib"

      # This will yield local files at  /root/etcrestore/...
      expect(SyncCommand.process_destination(source, destination)).to eql([["", "mybucket"], "/tmp/lib/"])
    end
  end

  it "Should calculate the right destination for each path" do
    file = "pre/etc/sub/path/blah.txt"   # This is how it comes from s3
    source = "mybucket:pre/etc/"
    destination = "/root/etcrestore"

    expect(SyncCommand.process_file_destination(source, destination, file)).to eql("/root/etcrestore/sub/path/blah.txt")
  end

  it "Put S3 files under an empty key (root) to the local dir /tmp/lib" do
    source = "mybucket:"
    destination = "/tmp/lib"
    file = "myfile.rb"

    # This will yield local files at  /tmp/lib/...
    expect(SyncCommand.process_file_destination(source, destination, file)).to eql("/tmp/lib/myfile.rb")
  end

  it "Returning locations based on the parsed destination" do
    source = "/etc"
    destination = "mybucket:pre"

    # When I parse the above arguments using the SyncCommand
    src_location, dst_location = SyncCommand.parse_params [source, destination]

    # Then I see I got the locations with the right params
    expect(src_location).to eql(S3Sync::Location.new("/etc"))
    expect(dst_location).to eql(S3Sync::Location.new("pre/etc/", "mybucket"))
  end

  it "Location should be parsed when it is remote with no path" do
    source = "/etc"
    destination = "mybucket:"

    # When I parse the above arguments using the SyncCommand
    src_location, dst_location = SyncCommand.parse_params [source, destination]

    # Then I see I got the locations with the right params
    expect(src_location).to eql(S3Sync::Location.new("/etc"))
    expect(dst_location).to eql(S3Sync::Location.new("etc/", "mybucket"))
  end

  it "should be possible to detect if a location is remote" do
    expect(SyncCommand.remote_prefix?("bucket:prefix")).to be(true)
    expect(SyncCommand.remote_prefix?("path")).to be(false)
    expect(SyncCommand.remote_prefix?("C://blah")).to be(false)  # We support windows, LOL
  end
end

describe "Comparing file lists" do

  it "should be possible to describe nodes with their paths and size" do

    # Full test
    node = Node.new "path/to", "file1", 10
    expect(node.path).to eql("file1")
    expect(node.full).to eql("path/to/file1")
    expect(node.size).to eql(10)

    # Alternative constructor scenarios
    node = Node.new "", "file1", 10
    expect(node.path).to eql("file1")
  end

  it "should be possible to compare two lists of files" do

    # Given that I have two lists of Nodes to compare
    hash1 = {
      "file1" => Node.new("", "file1", 10),
      "file2" => Node.new("", "file2", 12),
      "file3" => Node.new("", "file3", 12),
    }

    hash2 = {
      "file1" => Node.new("", "file1", 10),
      "file2" => Node.new("", "file2", 22),
      "file4" => Node.new("", "file4", 22),
    }

    # When I compare those two file lists
    same_in_both, to_be_added_to_list2, to_be_removed_from_list2 = SyncCommand.cmp hash1, hash2

    # Then I see that the three lists that I requested were returned with the
    # right content
    expect(same_in_both).to eq([Node.new("", "file1", 10)])  # Just testing our == operator
    expect(same_in_both).to eql([Node.new("", "file1", 10)])
    expect(to_be_added_to_list2).to eql([Node.new("", "file2", 12), Node.new("", "file3", 12)])
    expect(to_be_removed_from_list2).to eql([Node.new("", "file4", 22)])
  end

  it 'can compare small files with an extra comparator' do
    large_file_size = S3Sync::Node::SMALL_FILE + 1024
    # Given that I have two lists of Nodes to compare
    hash1 = {
      "file1" => Node.new("", "file1", 10, -> { 'same' }),
      "file2" => Node.new("", "file2", 22, -> { 'abc' }),
      "file3" => Node.new("", "file3", 12, -> { fail }),
      "file5" => Node.new("", "file5", large_file_size, -> { 'abc' }),
    }

    hash2 = {
      "file1" => Node.new("", "file1", 10, -> { 'same' }),
      "file2" => Node.new("", "file2", 22, -> { 'def' }),
      "file4" => Node.new("", "file4", 22, -> { fail }),
      "file5" => Node.new("", "file5", large_file_size, -> { 'def' }),
    }

    # When I compare those two file lists
    same_in_both, to_be_added_to_list2, to_be_removed_from_list2 = SyncCommand.cmp hash1, hash2

    # Then I see that the three lists that I requested were returned with the
    # right content
    expect(same_in_both).to eq([Node.new("", "file1", 10), Node.new('', 'file5', large_file_size)])
    expect(to_be_added_to_list2).to eql([Node.new("", "file2", 22), Node.new("", "file3", 12)])
    expect(to_be_removed_from_list2).to eql([Node.new("", "file4", 22)])
  end
end
