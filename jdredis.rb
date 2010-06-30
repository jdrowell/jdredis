require 'socket'

class JDRedis
  # Sync driver supporting the Redis protocol as described below
  # http://code.google.com/p/redis/wiki/ProtocolSpecification
  #
  # Copyright 2010 John D. Rowell <me@jdrowell.com>
  # License: MIT
  #
  # Goals:
  #   - DON'T LEAK
  #   - support ruby 1.9+
  #   - be small
  #   - be quick
  #   - don't be dead
  #
  # Ungoals:
  #   - handholding
  
  def initialize
    setup_socket
  end

  def setup_socket
    @socket = TCPSocket.new('localhost', 6379)
    @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
  end

  def write(data)
    begin
      @socket.write(data)
    rescue Errno::EPIPE
      # our socket is no more, probably inactive too long
      debug "  ** Reconnecting socket (data: #{data})"
      setup_socket
      retry
    end
  end
        
  def debug(msg)
    puts "DEBUG: #{msg}"
  end
  
  def inline_cmd(cmd, key = nil)
    key.nil? ? write("#{cmd}\r\n") : write("#{cmd} #{key}\r\n")
  end
  
  def bulk_cmd(cmd, key, arg)
    write("#{cmd} #{key} #{arg.bytesize}\r\n")
    write("#{arg}\r\n")
  end

  def bulk_reply(line)
    size = line[1..-1].to_i
    line = @socket.gets
    # we need _bytes_ -- and fast -- so force 8bit
    line.force_encoding(Encoding::ASCII_8BIT)
    line[0..(size -1)]
  end
    
  def reply()
    line = @socket.gets.strip
    case line[0]
    when '-'
      # error message
      raise line
    when '+'
      # single line reply
      return [line[1..-1], nil]
    when '$'
      # bulk data
      return [ 'OK', bulk_reply(line) ]
    when '*'
      # multi-bulk
      count = line[1..-1].to_i
      all = []
      count.times { all.push bulk_reply(@socket.gets.strip) }
      return [ 'OK', all ]
    when ':'
      # integer number
      return [ 'OK', line[1..-1].to_i ]
    end
    raise 'Unknown reply type'
  end
       
  def ping
    inline_cmd('PING')
    reply[0] == 'PONG'
  end
  
  def exists(key)
    inline_cmd("EXISTS #{key}")
    reply[1] > 0
  end
  alias :has_key? :exists
  
  def del(*keys)
    inline_cmd('DEL', keys.join(' '))
    reply[1] > 0
  end

  def sadd(key, value)
    bulk_cmd('SADD', key, value)
    reply[1] == 1
  end
  
  def scard(key)
    inline_cmd('SCARD', key)
    reply[1]
  end
  
  def sdiff(*keys)
    inline_cmd('SDIFF', keys.join(' '))
    reply[1]
  end
    
  def smembers(key)
    inline_cmd('SMEMBERS', key)
    reply[1]
  end
end

