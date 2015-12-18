require 'fileutils'
require 'simplecov'
SimpleCov.start

def fixture *args
  File.join File.dirname(__FILE__), "fixtures", *args
end

def directory path
  full = fixture(path)
  FileUtils::mkdir_p full
  return full
end

def file *args
  file = File.join(*args[0..-2])
  directory File.dirname(file)
  File.open(file, 'w') {|f| f.write args[-1] }
  return file
end


def rm path
  FileUtils::rm_rf path
end


RSpec::Matchers.define :match_stdout do |check|

  @capture = nil

  match do |block|
    begin
      stdout_saved = $stdout
      $stdout = StringIO.new
      block.call
    ensure
      @capture = $stdout
      $stdout = stdout_saved
    end
    @capture.string.match check
  end

  failure_message do
    "expected to #{description}"
  end

  failure_message_when_negated do
    "expected not to #{description}"
  end

  description do
    "match [#{check}] on stdout [#{@capture.string}]"
  end
end
