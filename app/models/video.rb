class Video < SimpleDB::Base
  
  include LocalStore
  
  set_domain Panda::Config[:sdb_videos_domain]
  properties :filename, :original_filename, :parent, :status, :duration, :container, :width, :height, :video_codec, :video_bitrate, :fps, :audio_codec, :audio_bitrate, :audio_sample_rate, :profile, :profile_title, :player, :queued_at, :started_encoding_at, :encoding_time, :encoded_at, :last_notification_at, :notification, :updated_at, :created_at, :thumbnail_position, :cut_start, :cut_end
  
  # TODO: state machine for status
  # An original video can either be 'empty' if it hasn't had the video file uploaded, or 'original' if it has
  # An encoding will have it's original attribute set to the key of the original parent, and a status of 'queued', 'processing', 'success', or 'error'
  
  def self.create_empty
    video = Video.create
    video.status = 'empty'
    video.save
    
    return video
  end
  
  def to_sym
    'videos'
  end
  
  def clipping(position = nil)
    Clipping.new(self, position)
  end
  
  def clippings
    self.thumbnail_percentages.map do |p|
      Clipping.new(self, p)
    end
  end
  
  # Classification
  # ==============
  
  def encoding?
    ['queued', 'processing', 'success', 'error'].include?(self.status)
  end
  
  def parent?
    ['original', 'empty'].include?(self.status)
  end
  
  # Finders
  # =======
  
  # Only parent videos (no encodings)
  def self.all
    self.query("['status' = 'original'] intersection ['created_at' != ''] sort 'created_at' desc", :load_attrs => true) # TODO: Don't throw an exception if attrs for a record in the search can't be found - it probably means its just been deleted
  end
  
  def self.recent_videos
    self.query("['status' = 'original']", :max_results => 10, :load_attrs => true)
  end
  
  def self.recent_encodings
    self.query("['status' = 'success']", :max_results => 10, :load_attrs => true)
  end
  
  def self.queued_encodings
    self.query("['status' = 'processing' or 'status' = 'queued']", :load_attrs => true)
  end
  
  def self.next_job
    # TODO: change to outstanding_jobs and remove .first
    self.query("['status' = 'queued']").first
  end
  
  def self.outstanding_notifications
    self.query("['notification' != 'success' and 'notification' != 'error'] intersection ['status' = 'success' or 'status' = 'error']") #  sort 'last_notification_at' asc
  end
  
  # def self.recently_completed_videos
  #   self.query("['status' = 'success']")
  # end
  
  def parent_video
    self.class.find(self.parent)
  end
  
  def encodings
    self.class.query("['parent' = '#{self.key}']")
  end
  
  def successful_encodings
    self.class.query("['parent' = '#{self.key}'] intersection ['status' = 'success']")
  end
  
  def find_encoding_for_profile(p)
    self.class.query("['parent' = '#{self.key}'] intersection ['profile' = '#{p.key}']")
  end
  
  # Attr helpers
  # ============
  
  # Delete an original video and all it's encodings.
  def obliterate!
    # TODO: should this raise an exception if the file does not exist?
    self.delete_from_store
    self.encodings.each do |e|
      e.delete_from_store
      e.destroy!
    end
    self.destroy!
  end

  # Location to store video file fetched from S3 for encoding
  def tmp_filepath
    private_filepath(self.filename)
  end
  
  # Has the actual video file been uploaded for encoding?
  def empty?
    self.status == 'empty'
  end
  
  def upload_redirect_url
    Panda::Config[:upload_redirect_url].gsub(/\$id/,self.key)
  end
  
  def state_update_url
    Panda::Config[:state_update_url].gsub(/\$id/,self.key)
  end
  
  def duration_str
    s = (self.duration.to_i || 0) / 1000
    "#{sprintf("%02d", s/60)}:#{sprintf("%02d", s%60)}"
  end
  
  def resolution
    self.width ? "#{self.width}x#{self.height}" : nil
  end
  
  def video_bitrate_in_bits
    self.video_bitrate.to_i * 1024
  end
  
  def audio_bitrate_in_bits
    self.audio_bitrate.to_i * 1024
  end
  
  # Encding attr helpers
  # ====================
  
  def url
    Store.url(self.filename)
  end
  
  def embed_html
    return nil unless self.encoding?
    %(<embed src="#{Store.url('flvplayer.swf')}" width="#{self.width}" height="#{self.height}" allowfullscreen="true" allowscriptaccess="always" flashvars="&displayheight=#{self.height}&file=#{self.url}&width=#{self.width}&height=#{self.height}&image=#{self.clipping.url(:screenshot)}" />)
  end
  
  def embed_js
    return nil unless self.encoding?
  	%(
  	<div id="flash_container_#{self.key[0..4]}"><a href="http://www.macromedia.com/go/getflashplayer">Get the latest Flash Player</a> to watch this video.</div>
  	<script type="text/javascript">
      var flashvars = {};
      
      flashvars.file = "#{self.url}";
      flashvars.image = "#{self.clipping.url(:screenshot)}";
      flashvars.width = "#{self.width}";
      flashvars.height = "#{self.height}";
      flashvars.fullscreen = "true";
      flashvars.controlbar = "over";
      var params = {wmode:"transparent",allowfullscreen:"true"};
      var attributes = {};
      attributes.align = "top";
      swfobject.embedSWF("#{Store.url('player.swf')}", "flash_container_#{self.key[0..4]}", "#{self.width}", "#{self.height}", "9.0.115", "#{Store.url('expressInstall.swf')}", flashvars, params, attributes);
  	</script>
  	)
	end
  
  # Interaction with store
  # ======================
  
  def upload_to_store
    Store.set(self.filename, self.tmp_filepath)
  end
  
  def fetch_from_store
    Store.get(self.filename, self.tmp_filepath)
  end
  
  # Deletes the video file without raising an exception if the file does 
  # not exist.
  def delete_from_store
    Store.delete(self.filename)
    self.clippings.each { |c| c.delete_from_store }
    Store.delete(self.clipping.filename(:screenshot, :default => true))
    Store.delete(self.clipping.filename(:thumbnail, :default => true))
  rescue AbstractStore::FileDoesNotExistError
    false
  end
  
  # Returns configured number of 'middle points', for example [25,50,75]
  def thumbnail_percentages
    n = Panda::Config[:choose_thumbnail]
    
    return [50] if n == false
    
    # Interval length
    interval = 100.0 / (n + 1)
    # Points is [0,25,50,75,100] for example
    points = (0..(n + 1)).map { |p| p * interval }.map { |p| p.to_i }
    
    # Don't include the end points
    return points[1..-2]
  end
  
  def generate_thumbnail_selection
    self.thumbnail_percentages.each do |percentage|
      self.clipping(percentage).capture
      self.clipping(percentage).resize
    end
  end
  
  def upload_thumbnail_selection
    self.thumbnail_percentages.each do |percentage|
      begin
        self.clipping(percentage).upload_to_store
      rescue
        Merb.logger.info "Clipping at #{percentage}% wasn't uploaded to store"
      end
      
      begin
        self.clipping(percentage).delete_locally
      rescue
        Merb.logger.info "Clipping at #{percentage}% wasn't deleted locally"
      end
    end
  end
  
  # Checks that video can accept new file, checks that the video is valid, 
  # reads some metadata from it, and moves video into a private tmp location.
  # 
  # File is the tempfile object supplied by merb. It looks like
  # {
  #   "content_type"=>"video/mp4", 
  #   "size"=>100, 
  #   "tempfile" => @tempfile,  # Also tempfile my be string with full path
  #   "filename" => "file.mov"
  # }
  # 
  def initial_processing(file)
    raise NoFileSubmitted if !file || file.blank?
    raise NotValid unless self.empty?

    # Convert all keys to symbols if they are strings
    file.symbolize_keys!
    
    # Set filename and original filename
    self.filename = self.key + File.extname(file[:filename])
    # Split out any directory path Windows adds in
    self.original_filename = file[:filename].split("\\\\").last

    if file[:tempfile].class == String
      # Make link to file into tmp location
      FileUtils.ln file[:tempfile], self.tmp_filepath
    else
      # Move file into tmp location
      FileUtils.mv file[:tempfile].path, self.tmp_filepath      
    end
    
    self.read_metadata
    self.status = "original"
    self.save
  end
  
  # Uploads video to store, generates thumbnails if required, cleans up 
  # tempoary file, and adds encodings to the encoding queue.
  # 
  def finish_processing_and_queue_encodings
    self.upload_to_store
    
    # Generate thumbnails before we add to encoding queue
    self.generate_thumbnail_selection
    self.clipping(self.thumbnail_percentages.first).set_as_default
    self.upload_thumbnail_selection
    
    self.thumbnail_position = self.thumbnail_percentages.first
    self.save
    
    FileUtils.rm self.tmp_filepath
  end
  
  # Reads information about the video into attributes.
  # 
  # Raises FormatNotRecognised if the video is not valid
  # 
  def read_metadata
    Merb.logger.info "#{self.key}: Reading metadata of video file"
    
    inspector = RVideo::Inspector.new(:file => self.tmp_filepath)
    
    raise FormatNotRecognised unless inspector.valid? and inspector.video?
    
    self.duration = (inspector.duration rescue nil)
    self.container = (inspector.container rescue nil)
    self.width = (inspector.width rescue nil)
    self.height = (inspector.height rescue nil)
    
    self.video_codec = (inspector.video_codec rescue nil)
    self.video_bitrate = (inspector.bitrate rescue nil)
    self.fps = (inspector.fps rescue nil)
    
    self.audio_codec = (inspector.audio_codec rescue nil)
    self.audio_sample_rate = (inspector.audio_sample_rate rescue nil)
    
    # Don't allow videos with a duration of 0
    raise FormatNotRecognised if self.duration == 0
  end
  #FIXME this method should be deleted
  def create_encoding_for_profile(p)
    encoding = Video.new
    encoding.status = 'queued'
    encoding.filename = "#{encoding.key}.#{p.container}"
    
    # Attrs from the parent video
    encoding.parent = self.key
    [:original_filename, :duration].each do |k|
      encoding.send("#{k}=", self.get(k))
    end
    
    # Attrs from the profile
    encoding.profile = p.key
    encoding.profile_title = p.title
    [:container, :width, :height, :video_codec, :video_bitrate, :fps, :audio_codec, :audio_bitrate, :audio_sample_rate, :player].each do |k|
      encoding.send("#{k}=", p.get(k))
    end
    
    encoding.save
    return encoding
  end

  def create_encoding(p, options)
    encoding = Video.new
    encoding.status = 'queued'
    encoding.filename = "#{encoding.key}.#{p["container"]}"
    
    # Attrs from the parent video
    encoding.parent = self.key
    [:original_filename, :duration].each do |k|
      encoding.send("#{k}=", self.get(k))
    end
    
    # Attrs from the profile
    encoding.profile_title = p["title"]
    encoding.profile = p["id"]
    [:container, :video_codec, :audio_codec].each do |k|
      encoding.send("#{k}=", p[k.to_s])
    end
    
    [:width, :height, :video_bitrate, :fps, :audio_bitrate].each do |k| 
      encoding.send("#{k}=", p[k.to_s].to_i)
    end

    if options[:start] && options[:end]
      encoding.cut_start = options['start']
      encoding.cut_end = options['end']
    end

    encoding.save
    return encoding
  end
  
 
  # Exceptions
  
  class VideoError < StandardError; end
  class NotificationError < StandardError; end
  
  # 404
  class NotValid < VideoError; end
  
  # 500
  class NoFileSubmitted < VideoError; end
  class FormatNotRecognised < VideoError; end
  
  # API
  # ===
  
  # Hash of paramenters for video and encodings when video.xml/yaml requested.
  # 
  # See the specs for an example of what this returns
  # 
  def show_response
    r = {
      :video => {
        :id => self.key,
        :status => self.status
      }
    }
    
    # Common attributes for originals and encodings
    if self.status == 'original' or self.encoding?
      [:filename, :original_filename, :width, :height, :duration].each do |k|
        r[:video][k] = self.send(k)
      end
      r[:video][:screenshot]  = self.clipping.filename(:screenshot)
      r[:video][:thumbnail]   = self.clipping.filename(:thumbnail)
    end
    
    # If the video is a parent, also return the data for all its encodings
    if self.status == 'original'
      r[:video][:encodings] = self.encodings.map {|e| e.show_response}
      r[:video][:thumbnails] = self.clippings.map { |c| c.filename(:thumbnail) }.join(',')
    end
    
    # Reutrn extra attributes if the video is an encoding
    if self.encoding?
      extra_attrs =  [:parent, :profile, :profile_title, :encoded_at, :encoding_time,
        :video_codec, :video_bitrate, :fps, :audio_codec, :audio_bitrate, :audio_sample_rate]
      r[:video].merge! extra_attrs.map_to_hash { |k| {k => self.send(k)} }
    end

    return r
  end
  
  def create_response
    {:video => {
        :id => self.key
      }
    }
  end

  def destroy_response
    {}
  end
  
  # Notifications
  # =============
  
  def notification_wait_period
    (Panda::Config[:notification_frequency] * self.notification.to_i)
  end
  
  def time_to_send_notification?
    return true if self.last_notification_at.nil?
    Time.now > (self.last_notification_at + self.notification_wait_period)
  end
  
  def send_notification
    raise "You can only send the status of encodings" unless self.encoding?
    
    self.last_notification_at = Time.now
    begin
      self.parent_video.send_status_update_to_client
      self.notification = 'success'
      self.save
      Merb.logger.info "Notification successfull"
    rescue
      # Increment num retries
      if self.notification.to_i >= Panda::Config[:notification_retries]
        self.notification = 'error'
      else
        self.notification = self.notification.to_i + 1
      end
      self.save
      raise
    end
  end
  
  def send_status_update_to_client
    Merb.logger.info "Sending notification to #{self.state_update_url}"
    
    params = {"video" => self.show_response.to_yaml}
    
    uri = URI.parse(self.state_update_url)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.port == 443)
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    req = Net::HTTP::Post.new(uri.path)
    req.form_data = params
    response = http.request(req)
    
    unless response.code.to_i == 200# and response.body.match /ok/
      ErrorSender.log_and_email("notification error", "Error sending notification for parent video #{self.key} to #{self.state_update_url} (POST)

REQUEST PARAMS
#{"="*60}\n#{params.to_yaml}\n#{"="*60}

RESPONSE
#{response.code} #{response.message} (#{response.body.length})
#{"="*60}\n#{response.body}\n#{"="*60}")
      
      raise NotificationError
    end
  end
  
  # Encoding
  # ========
  
  def ffmpeg_resolution_and_padding
    # Calculate resolution and any padding
    in_w = self.parent_video.width.to_f
    in_h = self.parent_video.height.to_f
    out_w = self.width.to_f
    out_h = self.height.to_f

    begin
      aspect = in_w / in_h
    rescue
      Merb.logger.error "Couldn't do w/h to caculate aspect. Just using the output resolution now."
      return %(-s #{self.width}x#{self.height})
    end

    height = (out_w / aspect.to_f).to_i
    height -= 1 if height % 2 == 1

    opts_string = %(-s #{self.width}x#{height} )

    # Crop top and bottom is the video is too tall, but add top and bottom bars if it's too wide (aspect wise)
    if height > out_h
      crop = ((height.to_f - out_h) / 2.0).to_i
      crop -= 1 if crop % 2 == 1
      opts_string += %(-croptop #{crop} -cropbottom #{crop})
    elsif height < out_h
      pad = ((out_h - height.to_f) / 2.0).to_i
      pad -= 1 if pad % 2 == 1
      opts_string += %(-padtop #{pad} -padbottom #{pad})
    end

    return opts_string
  end
  
  def ffmpeg_resolution_and_padding_no_cropping
    # Calculate resolution and any padding
    in_w = self.parent_video.width.to_f
    in_h = self.parent_video.height.to_f
    out_w = self.width.to_f
    out_h = self.height.to_f

    begin
      aspect = in_w / in_h
      aspect_inv = in_h / in_w
    rescue
      Merb.logger.error "Couldn't do w/h to caculate aspect. Just using the output resolution now."
      return %(-s #{self.width}x#{self.height} )
    end

    height = (out_w / aspect.to_f).to_i
    height -= 1 if height % 2 == 1

    opts_string = %(-s #{self.width}x#{height} )

    # Keep the video's original width if the height
    if height > out_h
      width = (out_h / aspect_inv.to_f).to_i
      width -= 1 if width % 2 == 1

      opts_string = %(-s #{width}x#{self.height} )
      self.width = width
      self.save
    # Otherwise letterbox it
    elsif height < out_h
      pad = ((out_h - height.to_f) / 2.0).to_i
      pad -= 1 if pad % 2 == 1
      opts_string += %(-padtop #{pad} -padbottom #{pad})
    end

    return opts_string
  end
  
  def recipe_options(input_file, output_file)
    cut_options = ""
    if self.cut_start && self.cut_end
      cut_options = "-ss #{self.cut_start} -t #{self.cut_end.to_i - self.cut_start.to_i}"
    end

    {
      :input_file => input_file,
      :output_file => output_file,
      :container => self.container, 
      :video_codec => self.video_codec,
      :video_bitrate_in_bits => self.video_bitrate_in_bits.to_s, 
      :fps => self.fps,
      :audio_codec => self.audio_codec.to_s, 
      :audio_bitrate => self.audio_bitrate.to_s, 
      :audio_bitrate_in_bits => self.audio_bitrate_in_bits.to_s, 
      :audio_sample_rate => self.audio_sample_rate.to_s, 
      :resolution => self.resolution,
      :resolution_and_padding => self.ffmpeg_resolution_and_padding_no_cropping,
      :cut_options => cut_options
    }
  end
  
  def encode_flv_flash
    Merb.logger.info "Encoding with encode_flv_flash"
    transcoder = RVideo::Transcoder.new
    recipe = "ffmpeg -i $input_file$ -ar 22050 -ab $audio_bitrate$k -f flv -b $video_bitrate_in_bits$ -r 24 $resolution_and_padding$ $cut_options$ -y $output_file$"
    recipe += "\nflvtool2 -U $output_file$"
    transcoder.execute(recipe, self.recipe_options(self.parent_video.tmp_filepath, self.tmp_filepath))
  end
  
  def encode_mp4_aac_flash
    Merb.logger.info "Encoding with encode_mp4_aac_flash"
    transcoder = RVideo::Transcoder.new
    # Just the video without audio
    temp_video_output_file = "#{self.tmp_filepath}.temp.video.mp4"
    temp_audio_output_file = "#{self.tmp_filepath}.temp.audio.mp4"
    temp_audio_output_wav_file = "#{self.tmp_filepath}.temp.audio.wav"

    recipe = "ffmpeg -i $input_file$ -b $video_bitrate_in_bits$ -an -vcodec libx264 -rc_eq 'blurCplx^(1-qComp)' $cut_options$ -qcomp 0.6 -qmin 10 -qmax 51 -qdiff 4 -coder 1 -flags +loop -cmp +chroma -partitions +parti4x4+partp8x8+partb8x8 -me hex -subq 5 -me_range 16 -g 6 -keyint_min 25 -sc_threshold 40 -i_qfactor 0.71 $resolution_and_padding$ -r 24 -threads 4 -y $output_file$"
    recipe_audio_extraction = "ffmpeg -i $input_file$ -ar 48000 -ac 2 $cut_options$ -y $output_file$"

    transcoder.execute(recipe, self.recipe_options(self.parent_video.tmp_filepath, temp_video_output_file))
    
    Merb.logger.info "Video encoding done"
    unless self.parent_video.audio_codec.blank?
      # We have to use nero to encode the audio as ffmpeg doens't support HE-AAC yet
      transcoder.execute(recipe_audio_extraction, recipe_options(self.parent_video.tmp_filepath, temp_audio_output_wav_file))
      Merb.logger.info "Audio extraction done"

      # Convert to HE-AAC
      %x(neroAacEnc -br #{self.audio_bitrate_in_bits} -he -if #{temp_audio_output_wav_file} -of #{temp_audio_output_file})
      Merb.logger.info "Audio encoding done"

      # Squash the audio and video together
      FileUtils.rm(self.tmp_filepath) if File.exists?(self.tmp_filepath) # rm, otherwise we end up with multiple video streams when we encode a few times!!
      %x(MP4Box -add #{temp_video_output_file}#video #{self.tmp_filepath})
      %x(MP4Box -add #{temp_audio_output_file}#audio #{self.tmp_filepath})

      # Interleave meta data
      %x(MP4Box -inter 500 #{self.tmp_filepath})
      Merb.logger.info "Squashing done"
    else
      Merb.logger.info "This video does't have an audio stream"
      FileUtils.mv(temp_video_output_file, self.tmp_filepath)
    end
  end
  
  def encode_unknown_format
    Merb.logger.info "Encoding with encode_unknown_format"
    transcoder = RVideo::Transcoder.new
    recipe = "ffmpeg -i $input_file$ -f $container$ -vcodec $video_codec$ -b $video_bitrate_in_bits$ $cut_options$ -ar $audio_sample_rate$ -ab $audio_bitrate$k -acodec $audio_codec$ -r 24 $resolution_and_padding$ -y $output_file$"
    Merb.logger.info "Unknown encoding format given but trying to encode anyway."
    transcoder.execute(recipe, recipe_options(self.parent_video.tmp_filepath, self.tmp_filepath))
  end
  
  def encode
    raise "You can only encode encodings" unless self.encoding?
    self.status = "processing"
    self.save
    
    begun_encoding = Time.now
    
    begin
      encoding = self
      parent_obj = self.parent_video
      Merb.logger.info "(#{Time.now.to_s}) Encoding #{self.key}"
    
      parent_obj.fetch_from_store

      if self.container == "flv" 
        self.encode_flv_flash
      elsif self.container == "mp4" and self.audio_codec == "aac"
        self.encode_mp4_aac_flash
      else # Try straight ffmpeg encode
        self.encode_unknown_format
      end
      
      Merb.logger.info "Uploading to store"
      self.upload_to_store

      Merb.logger.info "Generating thumbnail selection"
      self.generate_thumbnail_selection
      self.clipping.set_as_default

      Merb.logger.info "Uploading thumbnail selection"
      self.upload_thumbnail_selection
      
      self.notification = 0
      self.status = "success"
      self.encoded_at = Time.now
      self.encoding_time = (Time.now - begun_encoding).to_i
      self.save

      Merb.logger.info "Removing tmp video files"
      FileUtils.rm self.tmp_filepath
      FileUtils.rm parent_obj.tmp_filepath
      
      Merb.logger.info "Encoding successful"
    rescue
      self.notification = 0
      self.status = "error"
      self.save
      FileUtils.rm parent_obj.tmp_filepath
      
      Merb.logger.error "Unable to transcode file #{self.key}: #{$!.class} - #{$!.message}"
        
      raise
    end
  end

end
