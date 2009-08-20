require File.dirname(__FILE__) + '/lib/jab_logger'

# Railsへ登録
ActionController::Base.send(:include, JabLogger::RailsHooks)
ActiveRecord::Base.send(:include, JabLogger::RailsHooks)

