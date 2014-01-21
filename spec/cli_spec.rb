require 'spec_helper.rb'
require 's3sync/cli'

include S3Sync

describe "S3 Client" do

  it "Should be able to list buckets" do

    # Given a command that lists buckets
    command = CLI::ListBuckets.new

    # And a mock of the S3 connection with a fake list of buckets
    s3 = double(:buckets => [double(:name => "b1"), double(:name => "b2")])

    # Then I see that two names were printed out
    expect {
      # When I execute it with a mocked s3 instance
      command.run(s3, nil, nil, nil, nil)
    }.to match_stdout('b1\nb2\n')
  end

  it "Should be able to create buckets" do
    # Given a command line that creates buckets
    command = CLI::ListBuckets.new

    # And a mock of the S3 connection that can create buckets
    s3 = double(:buckets)
  end

end
