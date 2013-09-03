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
