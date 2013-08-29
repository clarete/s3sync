# (c) 2013  Lincoln de Sousa <lincoln@clarete.li>
#
# This software code is made available "AS IS" without warranties of any
# kind.  You may copy, display, modify and redistribute the software
# code either by itself or as incorporated into your code; provided that
# you do not remove any proprietary notices.  Your use of this software
# code is at your own risk and you waive any claim against the author
# with respect to your use of this software code.

module S3Ranger

  class SyncException < StandardError
  end

  class NoConfigFound < SyncException

    attr_accessor :paths_checked

    def initialize(paths_checked)
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
