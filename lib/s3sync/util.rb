module S3sync
  def S3sync.utf8(content, charset = $S3SYNC_NATIVE_CHARSET)
    "#{content}".encode(charset, :invalid => :replace, :undef => :replace, :replace => '')
  end
end
