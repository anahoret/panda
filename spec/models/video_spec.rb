require File.join( File.dirname(__FILE__), "..", "spec_helper" )

describe Video do
  before :each do
    @video = mock_video
    
    Panda::Config.use do |p|
      p[:private_tmp_path] = '/tmp'
      p[:state_update_url] = "http://localhost:4000/videos/$id/status"
      p[:upload_redirect_url] = "http://localhost:4000/videos/$id/done"
      p[:videos_domain] = "videos.pandastream.com"
      p[:thumbnail_height_constrain] = 125
    end
    
    Store.stub!(:set).and_return(true)
    Store.stub!(:delete).and_return(true)
  end
  
  describe "clipping" do
    it "should return a clipping" do
      @video.clipping.should be_kind_of(Clipping)
    end
  end
  
  # Classification
  # ==============
  
  it "encoding? returns false if video is original" do
    @video.status = 'original'
    @video.encoding?.should be_false
  end
  
  # Finders
  # =======
  
  it "self.all" do
    Video.should_receive(:query).with("['status' = 'original'] intersection ['created_at' != ''] sort 'created_at' desc", {:load_attrs=>true})
    
    Video.all
  end
  
  it "self.recent_videos" do
    Video.should_receive(:query).with("['status' = 'original']", :max_results => 10, :load_attrs => true)
    
    Video.recent_videos
  end
  
  it "self.recent_encodings" do
    Video.should_receive(:query).with("['status' = 'success']", :max_results => 10, :load_attrs => true)
    
    Video.recent_encodings
  end
  
  it "self.queued_encodings" do
    Video.should_receive(:query).with("['status' = 'processing' or 'status' = 'queued']", :load_attrs => true)
    
    Video.queued_encodings
  end
  
  it "self.next_job" do
    Video.should_receive(:query).with("['status' = 'queued']").and_return([])
    Video.next_job
  end
  
  it "parent_video" do
    @video.parent = 'xyz'
    Video.should_receive(:find).with('xyz')
    
    @video.parent_video
  end
  
  it "encodings" do 
    Video.should_receive(:query).with("['parent' = 'abc']")
    @video.encodings
  end
  
  # Attr helpers
  # ============
  
  describe "obliterate!" do
    before :each do
      @encoding = Video.new
      @encoding.filename = 'abc.flv'
      
      @video.should_receive(:encodings).and_return([@encoding])
      
      @video.stub!(:destroy!)
      @encoding.stub!(:destroy!)
    end
    
    it "should delete the original from the store and database" do
      Store.should_receive(:delete).once.with('abc.mov')
      @video.should_receive(:destroy!).once
      
      @video.obliterate!
    end
    
    it "should delete all encodings from the store database" do
      Store.should_receive(:delete).once.with('abc.flv')
      @encoding.should_receive(:destroy!).once
      
      @video.obliterate!
    end
  end
    
  it "tmp_filepath" do
    @video.should_receive(:private_filepath).with('abc.mov').
      and_return('/tmp/abc.mov')
    
    @video.tmp_filepath.should == '/tmp/abc.mov'
  end

  it "empty?" do
    @video.status = 'empty'
    @video.empty?.should be_true
  end
  
  it "should put video key into update_redirect_url" do
    @video.upload_redirect_url.should == "http://localhost:4000/videos/abc/done"
  end
  
  it "should put video key into state_update_url" do
    @video.state_update_url.should == "http://localhost:4000/videos/abc/status"
  end
  
  it "should return 00:00 duration string for nil duration" do
    @video.duration_str.should == "00:00"
  end
  
  it "should return correct duration string" do
    @video.duration = 5586000
    @video.duration_str.should == "93:06"
  end
  
  it "should return nil resolution if there is no width" do
    @video.width = nil
    @video.resolution.should be_nil
  end
  
  # def set_encoded_at
  
  # Encding attr helpers
  # ====================
  
  it "url" do
    @video.url.should == "http://videos.pandastream.com/abc.mov"
  end
  
  it "should not reutrn embed_html for a parent/original video" do
    @video.status = 'original'
    @video.embed_html.should be_nil
  end
  
  it "embed_html" do
    @video.filename = 'abc.flv'
    @video.width = 320
    @video.height = 240
    @video.status = 'success'
    
    @video.embed_html.should == %(<embed src="http://videos.pandastream.com/flvplayer.swf" width="320" height="240" allowfullscreen="true" allowscriptaccess="always" flashvars="&displayheight=240&file=http://videos.pandastream.com/abc.flv&width=320&height=240&image=http://videos.pandastream.com/abc.flv.jpg" />)
  end
  
  describe "storing and fetching from the store" do
    it "should upload" do
      Store.should_receive(:set).with(@video.filename, @video.tmp_filepath)
      @video.upload_to_store
    end

    it "should fetch" do
      Store.should_receive(:get).with(@video.filename, @video.tmp_filepath)
      @video.fetch_from_store
    end
    
    describe "delete" do
      it "should delete" do
        Store.should_receive(:delete).with(@video.filename)
        @video.delete_from_store
      end
      
      it "should not raise error if delete fails" do
        Store.should_receive(:delete).
          and_raise(AbstractStore::FileDoesNotExistError)
        lambda {
          @video.delete_from_store
        }.should_not raise_error
      end
    end
  end
  
  describe "thumbnail_percentages should generate list of percentages" do
    it "should default to [50] if config option not set" do
      Panda::Config[:choose_thumbnail] = false
      @video.thumbnail_percentages.should == [50]
    end
    
    it "should be [50] if 1 thumbnail" do
      Panda::Config[:choose_thumbnail] = 1
      @video.thumbnail_percentages.should == [50]
    end
    
    it "should be [25, 50, 75] if 3 thumbnails" do
      Panda::Config[:choose_thumbnail] = 3
      @video.thumbnail_percentages.should == [25, 50, 75]
    end
    
    it "should be [20,40,60,80] if 4 thumbnails" do
      Panda::Config[:choose_thumbnail] = 4
      @video.thumbnail_percentages.should == [20,40,60,80]
    end
  end
  
  describe "generate_thumbnail_selection" do
    before :each do
      @clipping = mock(Clipping, :capture => true, :resize => true)
      @video.stub!(:clipping).and_return(@clipping)
      @video.stub!(:thumbnail_percentages).and_return([25,50,75])
    end
    
    it "should capture for each thumbnail options" do
      @clipping.should_receive(:capture).exactly(3).times
      @video.generate_thumbnail_selection
    end
    
    it "should resize for each thumbnail option" do
      @clipping.should_receive(:resize).exactly(3).times
      @video.generate_thumbnail_selection
    end
  end
  
  # Uploads
  # =======
  
  describe "initial_processing" do
    before(:each) do
      @tempfile = mock(File, :filename => "tmpfile", :path => "/tump/tmpfile")
      
      @file = Mash.new({"content_type"=>"video/mp4", "size"=>100, "tempfile" => @tempfile, "filename" => "file.mov"})
      @video.status = 'empty'
      
      FileUtils.stub!(:mv)
      @video.stub!(:read_metadata)
      @video.stub!(:save)
    end
    
    it "should raise NotValid if video is not empty" do
      @video.status = 'original'
      
      lambda {
        @video.initial_processing(@file)
      }.should raise_error(Video::NotValid)
      
      @video.status = 'empty'
      
      lambda {
        @video.initial_processing(@file)
      }.should_not raise_error(Video::NotValid)
    end
    
    it "should set filename and original_filename" do
      @video.should_receive(:key).and_return('1234')
      @video.should_receive(:filename=).with("1234.mov")
      @video.should_receive(:original_filename=).with("file.mov")
      
      @video.initial_processing(@file)
    end
    
    it "should move file to tempoary location" do
      FileUtils.should_receive(:mv).with("/tump/tmpfile", "/tmp/abc.mov")
      
      @video.initial_processing(@file)
    end
    
    it "should read metadata" do
      @video.should_receive(:read_metadata).and_return(true)
      
      @video.initial_processing(@file)
    end
    
    it "should save video" do
      @video.should_receive(:status=).with("original")
      @video.should_receive(:save)
      
      @video.initial_processing(@file)
    end
  end
  
  describe "finish_processing_and_queue_encodings" do
    
    before(:each) do
      @clipping = mock(Clipping, {
        :set_as_default => true, :changeable? => true
      })
      
      @video.status = 'original'
      @video.stub!(:upload_to_store)
      @video.stub!(:generate_thumbnail_selection)
      @video.stub!(:clipping).and_return(@clipping)
      @video.stub!(:upload_thumbnail_selection)
      @video.stub!(:save)
      @video.stub!(:add_to_queue)
      @video.stub!(:tmp_filepath).and_return('tmpfile')
      FileUtils.stub!(:rm)
    end
    
    it "should upload original to store" do
      @video.should_receive(:upload_to_store).and_return(true)
      @video.finish_processing_and_queue_encodings
    end
    
    describe "if clipping can be changed" do
      it "should generate and upload clippings" do
        Panda::Config[:choose_thumbnail] = 2
        @video.should_receive(:generate_thumbnail_selection).and_return(true)
        @video.should_receive(:upload_thumbnail_selection).and_return(true)
        @video.finish_processing_and_queue_encodings
      end
      
      it "should set the default clipping position" do
        @video.should_receive(:thumbnail_position=)
        @video.finish_processing_and_queue_encodings
      end
      
      it "should upload default clipping" do
        @clipping.should_receive(:set_as_default)
        @video.finish_processing_and_queue_encodings
      end
    end
    
    it "should add encodings to queue" do
      @video.should_receive(:add_to_queue).and_return(true)
      @video.finish_processing_and_queue_encodings
    end
    
    it "should clean up original video" do
      FileUtils.should_receive(:rm).and_return(true)
      @video.finish_processing_and_queue_encodings
    end
  end
  
  # def read_metadata
  
  # Also test create_encoding_for_profile(p) and find_encoding_for_profile(p)
  it "should create profiles when add_to_queue is called" do
    profile = mock_profile
    Profile.should_receive(:query).twice.and_return([mock_profile])
    Video.should_receive(:query).with("['parent' = 'abc'] intersection ['profile' = 'profile1']").and_return([])
    # We didn't find a video, so the method will create one now
    
    encoding = Video.new('xyz')
    encoding.should_receive(:status=).with("queued")
    encoding.should_receive(:filename=).with("xyz.flv")
    
    # Attrs from the parent video
    encoding.should_receive(:parent=).with("abc")
    encoding.should_receive(:original_filename=).with("original_filename.mov")
    encoding.should_receive(:duration=).with(100)
    
    # Attrs from the profile
    encoding.should_receive(:profile=).with("profile1")
    encoding.should_receive(:profile_title=).with("Flash video HI")
    
    encoding.should_receive(:container=).with("flv")
    encoding.should_receive(:width=).with(480)
    encoding.should_receive(:height=).with(360)
    encoding.should_receive(:video_bitrate=).with(400)
    encoding.should_receive(:fps=).with(24)
    encoding.should_receive(:audio_bitrate=).with(48)
    encoding.should_receive(:player=).with("flash")
    
    encoding.should_receive(:save)
    
    Video.should_receive(:new).and_return(encoding)
    
    @video.add_to_queue
  end
  
  describe "show_response" do
    before :each do
      @encoding = Video.new
      @encoding.filename = 'abc.flv'
      @encoding.key = '1234'
      
      @video.stub!(:encodings).and_return([])
    end
    
    it "should contain a hash of parameters for the video" do
      @video.show_response.should == {
        :video => {
          :thumbnail=>"abc.mov_50_thumb.jpg", 
          :height=>360, 
          :filename=>"abc.mov", 
          :screenshot=>"abc.mov_50.jpg", 
          :status=>"original", 
          :duration=>100, 
          :original_filename=>"original_filename.mov", 
          :width=>480, 
          :encodings=> [], 
          :id=>"abc"
        }
      }
    end
    
    it "should contain an array of encodings if defined" do
      @video.stub!(:encodings).and_return([@encoding])
      
      @video.show_response[:video][:encodings].first.should == {
        :video => {
          :status=>nil, 
          :id=>"1234"
        }
      }
    end
  end
  
  it "should return correct API create response hash" do
    @video.create_response.should == {:video => {:id => 'abc'}}
  end
  
  # Notifications
  # =============
  
  it "should return true if the current time is past the encoding's notification wait period" do
    t = Time.now
    encoding = mock_encoding_flv_flash(:last_notification_at => t - 50, :notification => 1)
    # Default notification_frequency is 1 second
    encoding.time_to_send_notification?.should == true
  end
  
  it "should return false if the current time is not past the encoding's notification wait period" do
    t = Time.now
    encoding = mock_encoding_flv_flash(:last_notification_at => t, :notification => 10)
    Panda::Config[:notification_frequency] = 50
    encoding.time_to_send_notification?.should == false
  end
  
  it "should send notification to client" do
    encoding = mock_encoding_flv_flash
    encoding.stub!(:parent_video).and_return(@video)
    @video.should_receive(:send_status_update_to_client)
    
    encoding.should_receive(:last_notification_at=).with(an_instance_of(Time))
    encoding.should_receive(:notification=).with("success")
    encoding.should_receive(:save)
    
    encoding.send_notification
  end
  
  it "should increment notification retry count if sending the notification fails" do
    encoding = mock_encoding_flv_flash
    encoding.stub!(:parent_video).and_return(@video)
    @video.should_receive(:send_status_update_to_client).and_raise(Video::NotificationError)
    
    encoding.should_receive(:last_notification_at=).with(an_instance_of(Time))
    encoding.should_receive(:notification).twice().and_return(1)
    encoding.should_receive(:notification=).with(2)
    encoding.should_receive(:save)
    
    lambda {encoding.send_notification}.should raise_error(Video::NotificationError)
  end
  
  it "should only allow notifications of encodings to be sent" do
    lambda {@video.send_notification}.should raise_error(StandardError)
  end
  
  # Encoding
  # ========
  
  # def ffmpeg_resolution_and_padding(inspector)
  
  it "should constrain video and preserve aspect ratio (no cropping or pillarboxing) if a 4:3 video is encoded with a 16:9 profile" do
    parent_video = mock_video({:width => 640, :height => 480})
    encoding = mock_encoding_flv_flash({:width => 640, :height => 360})
    encoding.should_receive(:parent_video).twice.and_return(parent_video)
    # We also need to then update the encoding's sizing to the new width
    encoding.should_receive(:width=).with(480)
    encoding.should_receive(:save)
    encoding.ffmpeg_resolution_and_padding_no_cropping.should == "-s 480x360 "
  end
  
  it "should constrain video if a 16:9 video is encoded with a 16:9 profile" do
    parent_video = mock_video({:width => 1280, :height => 720})
    encoding = mock_encoding_flv_flash({:width => 640, :height => 360})
    encoding.should_receive(:parent_video).twice.and_return(parent_video)
    encoding.ffmpeg_resolution_and_padding_no_cropping.should == "-s 640x360 "
  end
  
  it "should letterbox if a 2.40:1 (848x352) video is encoded with a 16:9 profile" do
    parent_video = mock_video({:width => 848, :height => 352})
    encoding = mock_encoding_flv_flash({:width => 640, :height => 360})
    encoding.should_receive(:parent_video).twice.and_return(parent_video)
    encoding.ffmpeg_resolution_and_padding_no_cropping.should == "-s 640x264 -padtop 48 -padbottom 48"
  end
  
  it "should return correct recipe_options hash" do
    encoding = mock_encoding_flv_flash
    encoding.should_receive(:parent_video).twice.and_return(@video)
    encoding.recipe_options('/tmp/abc.mov', '/tmp/xyz.flv').should eql_hash(
      {
        :input_file => '/tmp/abc.mov',
        :output_file => '/tmp/xyz.flv',
        :container => 'flv',
        :video_codec => '',
        :video_bitrate_in_bits => (400*1024).to_s, 
        :fps => 24,
        :audio_codec => '', 
        :audio_bitrate => '48', 
        :audio_bitrate_in_bits => (48*1024).to_s, 
        :audio_sample_rate => '', 
        :resolution => '480x360',
        :resolution_and_padding => "-s 480x360 " # encoding.ffmpeg_resolution_and_padding
      }
    )
  end
    
  it "should call encode_flv_flash when encoding an flv for the flash player" do
    encoding = mock_encoding_flv_flash
    encoding.stub!(:parent_video).and_return(@video)
    @video.should_receive(:fetch_from_store)
  
    encoding.should_receive(:status=).with("processing")
    encoding.should_receive(:save).twice
    encoding.should_receive(:encode_flv_flash)
  
    encoding.should_receive(:upload_to_store)
    encoding.should_receive(:generate_thumbnail_selection)
    encoding.should_receive(:upload_thumbnail_selection)
    clipping = returning(mock(Clipping)) do |c|
      c.should_receive(:set_as_default)
    end
    encoding.should_receive(:clipping).and_return(clipping)
    
    encoding.should_receive(:notification=).with(0)
    encoding.should_receive(:status=).with("success")
    encoding.should_receive(:encoded_at=).with(an_instance_of(Time))
    encoding.should_receive(:encoding_time=).with(an_instance_of(Integer))
    # encoding.should_receive(:save) expected twice above
    
    FileUtils.should_receive(:rm).with('/tmp/xyz.flv')
    FileUtils.should_receive(:rm).with('/tmp/abc.mov')
  
    encoding.encode
  end
  
  it "should set the encoding's status to error if the video fails to encode correctly" do
    encoding = mock_encoding_flv_flash
    encoding.stub!(:parent_video).and_return(@video)
    @video.should_receive(:fetch_from_store)
  
    encoding.should_receive(:status=).with("processing")
    encoding.should_receive(:save).twice
    encoding.should_receive(:encode_flv_flash).and_raise(RVideo::TranscoderError)
    encoding.should_receive(:notification=).with(0)
    encoding.should_receive(:status=).with("error")
    # encoding.should_receive(:save) expected twice above
    FileUtils.should_receive(:rm).with('/tmp/abc.mov')
  
    lambda {encoding.encode}.should raise_error(RVideo::TranscoderError)
  end

  it "should run correct ffmpeg command to encode to an flv for the flash player" do
    encoding = mock_encoding_flv_flash
    encoding.stub!(:parent_video).and_return(@video)
    transcoder = mock(RVideo::Transcoder)
    RVideo::Transcoder.should_receive(:new).and_return(transcoder)
    
    transcoder.should_receive(:execute).with(
      "ffmpeg -i $input_file$ -ar 22050 -ab $audio_bitrate$k -f flv -b $video_bitrate_in_bits$ -r 24 $resolution_and_padding$ -y $output_file$\nflvtool2 -U $output_file$", nil)
    encoding.should_receive(:recipe_options).with('/tmp/abc.mov', '/tmp/xyz.flv')
    
    encoding.encode_flv_flash
  end
  
  it "should run correct ffmpeg command to encode to an mp4 for the flash player" do
    encoding = mock_encoding_mp4_aac_flash
    encoding.stub!(:parent_video).and_return(@video)
    transcoder = mock(RVideo::Transcoder)
    RVideo::Transcoder.should_receive(:new).and_return(transcoder)
    
    transcoder.should_receive(:execute).with(
      "ffmpeg -i $input_file$ -b $video_bitrate_in_bits$ -an -vcodec libx264 -rc_eq 'blurCplx^(1-qComp)' -qcomp 0.6 -qmin 10 -qmax 51 -qdiff 4 -coder 1 -flags +loop -cmp +chroma -partitions +parti4x4+partp8x8+partb8x8 -me hex -subq 5 -me_range 16 -g 250 -keyint_min 25 -sc_threshold 40 -i_qfactor 0.71 $resolution_and_padding$ -r 24 -threads 4 -y $output_file$", nil) # No need to test the 2nd parameter for recepie options which is tested in another test
    encoding.should_receive(:recipe_options).with('/tmp/abc.mov', '/tmp/xyz.mp4.temp.video.mp4')

    # Testing separate audio extraction and encoding for flash h264
    transcoder.should_receive(:execute).with(
      "ffmpeg -i $input_file$ -ar 48000 -ac 2 -y $output_file$", nil)
    encoding.should_receive(:recipe_options).with('/tmp/abc.mov', '/tmp/xyz.mp4.temp.audio.wav')

    # rm video file before we use MP4Box, otherwise we end up with multiple AV streams if the videos has been encoded more than once!
    File.should_receive(:exists?).with('/tmp/xyz.mp4').and_return(true)
    FileUtils.should_receive(:rm).with('/tmp/xyz.mp4')
    
    encoding.encode_mp4_aac_flash
  end
  
  it "should run correct ffmpeg command to encode to an unknown format" do
    encoding = mock_encoding_flv_flash
    encoding.stub!(:parent_video).and_return(@video)
    transcoder = mock(RVideo::Transcoder)
    RVideo::Transcoder.should_receive(:new).and_return(transcoder)
    
    transcoder.should_receive(:execute).with(
      "ffmpeg -i $input_file$ -f $container$ -vcodec $video_codec$ -b $video_bitrate_in_bits$ -ar $audio_sample_rate$ -ab $audio_bitrate$k -acodec $audio_codec$ -r 24 $resolution_and_padding$ -y $output_file$", nil)
    encoding.should_receive(:recipe_options).with('/tmp/abc.mov', '/tmp/xyz.flv')
    
    encoding.encode_unknown_format
  end
  
  private
  
    def mock_profile
      Profile.new("profile1", 
        {
          :title => "Flash video HI", 
          :container => "flv", 
          :video_bitrate => 400, 
          :audio_bitrate => 48, 
          :width => 480, 
          :height => 360, 
          :fps => 24, 
          :position => 1, 
          :player => "flash"
        }
      )
    end
  
  def mock_video(attrs={})
    enc = Video.new("abc", 
      {
        :status => 'original',
        :filename => 'abc.mov',
        :original_filename => 'original_filename.mov',
        :duration => 100,
        :video_codec => 'mp4',
        :video_bitrate => 400, 
        :fps => 24,
        :audio_codec => 'aac', 
        :audio_bitrate => 48, 
        :width => 480,
        :height => 360
      }.merge(attrs)
    )
  end
  
  def mock_encoding_flv_flash(attrs={})
    enc = Video.new('xyz', 
      {
        :status => 'queued',
        :filename => 'xyz.flv',
        :container => 'flv',
        :player => 'flash',
        :video_codec => '',
        :video_bitrate => 400, 
        :fps => 24,
        :audio_codec => '', 
        :audio_bitrate => 48, 
        :width => 480,
        :height => 360
      }.merge(attrs)
    )
  end
  
  def mock_encoding_mp4_aac_flash(attrs={})
    enc = Video.new('xyz', 
      {
        :status => 'queued',
        :filename => 'xyz.mp4',
        :container => 'mp4',
        :player => 'flash',
        :video_codec => '',
        :video_bitrate => 400, 
        :fps => 24,
        :audio_codec => 'aac', 
        :audio_bitrate => 48, 
        :width => 480,
        :height => 360
      }
    )
  end
  
  def mock_encoding_unknown_format(attrs={})
    enc = Video.new('xyz', 
      {
        :status => 'queued',
        :filename => 'xyz.xxx',
        :container => 'xxx',
        :player => 'someplayer',
        :video_codec => '',
        :video_bitrate => 400, 
        :fps => 24,
        :audio_codec => 'yyy', 
        :audio_bitrate => 48, 
        :width => 480,
        :height => 360
      }
    )
  end
end