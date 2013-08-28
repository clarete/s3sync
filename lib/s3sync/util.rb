module S3sync
  def S3sync.safe_join(parts)
    File.join *(parts.select {|v| !v.nil? && !v.empty? })
  end
end
