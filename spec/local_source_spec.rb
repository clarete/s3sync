require 'spec_helper.rb'
require 's3sync/sync'

include S3Sync


describe "Local file system IO" do

  it "should list local files" do

    # Given that I have remote source and a local destination with a couple
    # files
    destination = directory "directory2"
    file destination, "file1.txt", "First file"
    file destination, "file2.txt", "Second file"

    # When I create a new local directory based on that path
    local = LocalDirectory.new destination

    # Then I see that the directory nodes contain both their parent paths and
    # their names
    expect(local.list_files).to eql({
      "file1.txt" => Node.new(fixture("directory2"), "file1.txt", 10),
      "file2.txt" => Node.new(fixture("directory2"), "file2.txt", 11),
    })

    rm destination
  end

  it "should skip local folders while listing files" do
    # Given that I have remote source and a local destination with files
    destination = directory "directory2"
    file destination, "file1.txt", "First file"
    file destination, "file2.txt", "Second file"

    # And with a sub-directory
    subdir = directory "directory2/subd"
    file subdir, "sub1.txt", "Sub content"

    # When I create a new local directory based on that path
    local = LocalDirectory.new destination

    # Then I see that the directory nodes contain both their parent paths and
    # their names
    expect(local.list_files).to eql({
      "file1.txt" => Node.new(fixture("directory2"), "file1.txt", 10),
      "file2.txt" => Node.new(fixture("directory2"), "file2.txt", 11),
      "subd/sub1.txt" => Node.new(fixture("directory2"), "subd/sub1.txt", 11),
    })

    rm destination
  end
end
