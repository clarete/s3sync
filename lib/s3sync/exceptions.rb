# s3sync - Tool belt for managing your S3 buckets
#
# The MIT License (MIT)
#
# Copyright (c) 2013  Lincoln de Sousa <lincoln@clarete.li>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

module S3Sync

  class SyncException < StandardError
  end

  class NoConfigFound < SyncException

    attr_accessor :missing_vars
    attr_accessor :paths_checked

    def initialize missing_vars, paths_checked
      @missing_vars = missing_vars
      @paths_checked = paths_checked
    end
  end

  class WrongUsage < SyncException

    attr_accessor :error_code
    attr_accessor :msg

    def initialize(error_code, msg)
      @error_code = error_code || 1
      @msg = msg
    end
  end

  class FailureFeedback < SyncException
  end

end
