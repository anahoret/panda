require 'image_science'
# Clipping for a given encoding or parent video.
# 
class Clipping
  
  include LocalStore
  
  def initialize(video, position = nil)
    @video = video
    @_position = position
  end
  
  def filename(size, opts = {})
    raise "Invalid size: choose :thumbnail or :screenshot" unless [:thumbnail, :screenshot].include?(size)
    
    name = [@video.filename]
    name << position unless opts[:default]
    name << 'thumb' if size == :thumbnail
    
    return name.join('_') + '.jpg'
  end
  
  # URL of clipping on store. If clipping was initialized without a position 
  # then the default filename is used (without position) to generate the url
  def url(size)
    if @_position
      Store.url(self.filename(size.to_sym))
    else
      Store.url(self.filename(size.to_sym, :default => true))
    end
  end
  
  # URL on the panda instance (before it has been uploaded)
  def tmp_url(size)
    public_url(@video.filename, size, position, '.jpg')
  end
  
  def capture
    raise RuntimeError, "Video must exist to call capture" unless File.exists?(@video.tmp_filepath)
        
    t = RVideo::Inspector.new(:file => @video.tmp_filepath)
    t.capture_frame("#{position}%", tmp_path(:screenshot))
  end

  def resize
    constrain_to_height = Panda::Config[:thumbnail_height_constrain].to_f

    height = constrain_to_height
    width = (@video.width.to_f/@video.height.to_f) * height
    
    ImageScience.with_image(tmp_path(:screenshot)) do |img|
      img.resize(width.to_i, height.to_i) do |img2|
        img2.save tmp_path(:thumbnail)
      end
    end

    # GDResize.new.resize \
    #   tmp_path(:screenshot),
    #   tmp_path(:thumbnail),
    #   [width.to_i, height.to_i]
  end
  
  # Uploads this clipping to the default clipping locations on store (default 
  # url does not contain position)
  # 
  # TODO: Refactor. It's complicated because you're not sure whether the 
  # clipping is available locally before you start.
  def set_as_default
    actual_operation = lambda {
      Store.set \
        filename(:screenshot, :default => true), 
        tmp_path(:screenshot)
      Store.set \
        filename(:thumbnail, :default => true), 
        tmp_path(:thumbnail)
    }
    
    if File.exists?(tmp_path(:screenshot))
      actual_operation.call
    else
      self.fetch_from_store
      actual_operation.call
      self.delete_locally
    end
  end
  
  # Upload this clipping to store (with position info in the url)
  def upload_to_store
    Store.set \
      filename(:screenshot),
      tmp_path(:screenshot)
    Store.set \
      filename(:thumbnail), 
      tmp_path(:thumbnail)
  end
  
  def fetch_from_store
    Store.get(filename(:screenshot), tmp_path(:screenshot))
    Store.get(filename(:thumbnail), tmp_path(:thumbnail))
  end
  
  def delete_locally
    FileUtils.rm(tmp_path(:screenshot))
    FileUtils.rm(tmp_path(:thumbnail))
  end
  
  def delete_from_store
    Store.delete(filename(:screenshot))
    Store.delete(filename(:thumbnail))
  rescue AbstractStore::FileDoesNotExistError
    false
  end
  
  def changeable?
    Panda::Config[:choose_thumbnail] != false
  end
  
  private
  
  def original_video
    @video.parent? ? @video : @video.parent_video
  end
  
  def tmp_path(size)
    public_filepath(@video.filename, size, position, '.jpg')
  end
  
  def position
    @_position || original_video.thumbnail_position || 50
  end
  
end
