require 'singleton'
require 'logger'
require 'xmpp4r/client'
require 'memcache'


module JabLogger
    
    class Client
        include Singleton
        
        cattr_accessor :config
        @@config = {}
        
        
        def initialize
            Rails.logger.debug "JabLogger initilize."
            #raise unless @@config
            
            @@config[:server_port] ||= 5222
            
            # 監視コマンドの初期化
            self.init_commands
            
            # サーバーへ接続
            @client = self.connect
            if self.connected?
                # オンラインを通知する
                self.send_presence
                self.start_heartbeat
                
                self.notice("#{@@config[:server]}にログインしました。\nJabLoggerが利用可能です。")
            end
        end
        
        
        def connect
            client = nil
            begin
                client = Jabber::Client.new(Jabber::JID.new(@@config[:login]))
                client.connect(@@config[:server], @@config[:server_port])
                client.auth(@@config[:password])
                # メッセージ受信時のコールバックを定義
                client.add_message_callback do |message|
                    self.recv_callback(message)
                end
                Rails.logger.debug "JabLogger connected."
                Rails.logger.debug " -> Login:#{@@config[:login]}"
                Rails.logger.debug " -> Server:#{@@config[:server]}:#{@@config[:server_port]}"
                
            rescue
                client.close if client
                client = nil
            end
            return client
        end
        
        def connected?
            @client && @client.is_connected?
        end
        
        def disconnect
            if self.connected?
                self.send(@@config[:report_users], "#{@@config[:server]}からログアウトしました。")
                @client.close if @client
            end
            @client = nil
        end
        
        def send_presence
            @client = connect unless connected?
            presence = Jabber::Presence.new.set_status(`uptime`).set_show(:chat)
            @client.send(presence) if connected?
        end
        
        def debug(msg)
            out = "[DEBUG] #{Time.now.to_formatted_s(:db)}\n#{msg}"
            self.send(@@config[:report_users], out)
#            Rails.logger.debug(out)
        end
        
        def notice(msg)
            out = "[NOTICE] #{Time.now.to_formatted_s(:db)}\n#{msg}"
            self.send(@@config[:report_users], out)
#            Rails.logger.debug(out)
        end
        
        
        def send(to, body)
            to ||= @@config[:report_users]
            @client = connect unless self.connected?
            return nil unless self.connected?
            
            to = to.split if to.kind_of?(String)
            begin
                message = Jabber::Message.new(to, body).set_type(:chat)
                @client.send(message)
            rescue
                return nil
            end
        end
        
        
        protected
            
            def start_heartbeat
                return nil if @watcher
                @heartbeat_end = false
                @watcher = Thread.new do
                    while not @heartbeat_end
                        self.send_presence
                        sleep(10)
                    end
                end
                @watcher = nil
            end
            
            def stop_heartbeat
                return nil if @watcher
                @heartbeat_end = true
                @watcher.join
            end
            
            
            #==== メッセージ受信時のコールバック関数
            #
            def recv_callback(message)
                unless message.type == :error
                    command = message.body.strip
                    from, body = self.parse_command(command, message)
                    self.send(from, body)
                else
                    self.send(@@config[:report_users], "すいません、エラーっす\n#{message.body}")
                end
            end
            
            
            def parse_command(command, message)
                from = message.from
                case command
                when '@presence normal'
                    @client.send(Jabber::Presence.new.set_status(`uptime`).set_type(:probe))
                    body = ">>#{command}\npresence to normal"
                when '@presence busy'
                    @client.send(Jabber::Presence.new.set_status(`uptime`).set_type(:subscribed))
                    body = ">>#{command}\npresence to busy"
                when '@ps'
                    out = `ps aux`
                    body = ">>#{command}\n#{out}"
                when '@free'
                    out = `free`
                    body = ">>#{command}\n#{out}"
                when '@whoami'
                    out = `whoami`
                    body = ">>#{command}\n#{out}"
                when '@pwd'
                    out = `pwd`
                    body = ">>#{command}\n#{out}"
                when '@hostname'
                    out = `hostname`
                    body = ">>#{command}\n#{out}"
                when '@ifconfig'
                    out = `ifconfig`
                    body = ">>#{command}\n#{out}"
                when '@vmstat'
                    out = `vmstat`
                    body = ">>#{command}\n#{out}"
                when '@uptime'
                    out = `uptime`
                    body = ">>#{command}\n#{out}"
                when '@apache status'
                    out = `apache2ctl status`
                    body = ">>#{command}\n#{out}"
                when '@app about'
                    out = `script/about`
                    body = ">>#{command}\n#{out}"
                when '@app restart'
                    out = `touch tmp/restart.txt`
                    out = `wget --spider http://admin.nitro-core.jp/remote_restart`
                    body = ">>#{command}\n#{out}"
                when '@rake routes'
                    out = `rake routes`
                    body = ">>#{command}\n#{out}"
                when '@help'
                    out = "ググれカス"
                    body = ">>#{command}\n#{out}"
                else
                    from = @@config[:report_users]
                    body = ">>#{message.from}さんからメッセージです。\n「#{message.body}」"
                end
                return [from, body]
            end
            
            def init_commands
                @commands ||= []
                #@commands << RemoteCommand.new('@help', :help, Proc.new)
                #@commands << RemoteCommand.new('@uptime', :command, Proc.new)
            end
            
    end
    
    
    class RemoteCommand
        attr_accessor :command, :command_type, :out_format
        def initialize(command, command_type, proc)
            @command = command
            @command_type = command_type
            @proc = proc
            self
        end
    end
    
    
    class Worker
        
        def initialize
            @client = JabLogger::Client.instance
        end
        
        def run
            # ループしてキューからpop
            # メッセージがあればJabberで送信
        end
        
    end
    
    
    class Logger
        include Singleton
        
        
        def initialize
#            @memcache = Memcache.new 'localhost:11211'
        end
        
        def debug(out)
            # memcacheのキューにpush
            hash = Time.new
            index = "#JABLOG_index" 
            key = "#JABLOG_#{index+1}" 
        end
        
        def notice
            # memcacheのキューにpush
        end
        
        
    end
    
    
    #= Railsへのパッチ
    #
    module RailsHooks #:nodoc:
        def self.included(recipient)
            recipient.extend(ClassMethods)
            recipient.class_eval do
                include InstanceMethods
                @@jablog = nil
            end
        end
        module ClassMethods
            def jablog
                @@jablog ||= JabLogger::Client.instance
            end
        end
        module InstanceMethods
            def jablog
                self.class.jablog
            end
        end
    end

end
