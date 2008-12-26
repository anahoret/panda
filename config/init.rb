# Make the app's "gems" directory a place where gems are loaded from
Gem.clear_paths
Gem.path.unshift(Merb.root / "gems")

# Autoload from lib
$LOAD_PATH.unshift(Merb.root / "lib")
Merb.push_path(:lib, Merb.root / "lib") # uses **/*.rb as path glob.

Merb::Config.use do |c|
  c[:session_id_key] = 'panda'
  c[:session_secret_key]  = '4d5e9b90d9e92c236a2300d718059aef3a9b9cbe'
  c[:session_store] = 'cookie'
end

# Load Panda config
require "config" / "panda_init"

# Gem dependencies
dependency 'merb-assets'
dependency 'merb-mailer'
dependency 'merb_helpers'
dependency 'uuid'
dependency 'amazon_sdb'
dependency 'activesupport'
dependency 'rvideo'

# Dependencies in lib - not autoloaded in time so require them explicitly
require 'simple_db'
require 'local_store'

# Check panda config
Panda::Config.check

Merb::BootLoader.after_app_loads do
  unless Merb.environment == "test"
    require "config" / "aws"
    require "config" / "mailer"
  end
  
  Store = case Panda::Config[:videos_store]
  when :s3
    S3Store.new
  when :filesystem
    FileStore.new
  else
    raise RuntimeError, "You have specified an invalid videos_store configuration option. Valid options are :s3 and :filesystem"
  end
  
  LocalStore.ensure_directories_exist
end
