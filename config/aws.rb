Amazon::SDB::Base::BASE_PATH = 'http://127.0.0.1:8088'
#Amazon::SDB::Base::BASE_PATH = Panda::Config[:sdb_base_url]

SimpleDB::Base.establish_connection!(
  :access_key_id     => Panda::Config[:access_key_id],
  :secret_access_key => Panda::Config[:secret_access_key]
)
