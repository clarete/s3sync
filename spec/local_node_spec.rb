require 's3sync/sync'

include S3sync

describe "Compare file lists" do

  it "should be possible to compare two lists of files" do

    # Given that I have two lists of Nodes to compare
    list1 = [Node.new("file1", 10), Node.new("file2", 12), Node.new("file3", 12)]
    list2 = [Node.new("file1", 10), Node.new("file2", 22), Node.new("file4", 22),]

    # require 'debugger'; debugger

    # When I compare those two file lists
    same_in_both, to_be_added_to_list2, to_be_removed_from_list2 = SyncCommand.cmp list1, list2

    # Then I see that the three lists that I requested were returned with the
    # right content
    same_in_both.should be_eql ["file1"]
    to_be_added_to_list2.should be_eql ["file2", "file3"]
    to_be_removed_from_list2.should be_eql ["file4"]
  end
end
