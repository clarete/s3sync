module S3Ranger
  def S3Ranger.safe_join(parts)
    File.join *(parts.select {|v| !v.nil? && !v.empty? })
  end
end
