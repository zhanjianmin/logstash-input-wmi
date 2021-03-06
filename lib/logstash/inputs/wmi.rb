# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "socket"


# Collect data from WMI query
#
# This is useful for collecting performance metrics and other data
# which is accessible via WMI on a Windows host
#
# Example:
# [source,ruby]
#     input {
#       wmi {
#         query => "select * from Win32_Process"
#         interval => 10
#       }
#       wmi {
#         query => "select PercentProcessorTime from Win32_PerfFormattedData_PerfOS_Processor where name = '_Total'"
#       }
#       wmi { # Connect to a remote host
#         query => "select * from Win32_Process"
#         host => "MyRemoteHost"
#         user => "mydomain\myuser"
#         password => "Password"
#       }
#     }
class LogStash::Inputs::WMI < LogStash::Inputs::Base

  config_name "wmi"

  # WMI query
  config :query, :validate => :string, :required => true
  # Polling interval
  config :interval, :validate => :number, :default => 10
  # Host to connect to ( Defaults to localhost )
  config :host, :validate => :string, :default => 'localhost'
  # Username when doing remote connections
  config :user, :validate => :string
  # Password when doing remote connections
  config :password, :validate => :password
  # Namespace when doing remote connections
  config :namespace, :validate => :string, :default => 'root\cimv2'

  public
  def register

    # @host = Socket.gethostname
    @logger.info("Registering wmi input", :query => @query)

    if RUBY_PLATFORM == "java"
      require "jruby-win32ole"
    else
      require "win32ole"
    end

    # If host is localhost do a local connection
    initialize_host(@host)
  end # def register

  public
  def run(queue)
    initialize_host(@host) # multi thread maybe release the wmi object
    begin
      @logger.debug("Executing WMI query '#{@query}'")
      loop do
        @wmi.ExecQuery(@query).each do |wmiobj|
          # create a single event for all properties in the collection
          event = LogStash::Event.new
          event.set("host", @host)
          decorate(event)
          wmiobj.Properties_.each do |prop|
            event.set(prop.name, prop.value)
          end
          queue << event
        end
        sleep @interval
      end # loop
    rescue Exception => ex
      @logger.error("WMI query error: #{ex}\n#{ex.backtrace}")
      sleep @interval
      retry
    end # begin/rescue
  end # def run
  
  private
  def initialize_host(host)
    # If host is localhost do a local connection
    if (host == "127.0.0.1" || host == "localhost" || host == "::1" || host.nil?)
      @host = Socket.gethostname
      @wmi = WIN32OLE.connect('winmgmts:')
    else
      locator = WIN32OLE.new("WbemScripting.SWbemLocator")
      @host = Socket.gethostbyname(@host).first
      @wmi = locator.ConnectServer(@host, @namespace, @user, @password.value)
    end
  end
end # class LogStash::Inputs::WMI
