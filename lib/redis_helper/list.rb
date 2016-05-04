class Redis
  class List < Redis::RedisObject
    require 'enumerator'
    include Enumerable
    include Redis::RedisHelper::CoreCommands

    attr_reader :key, :options

    def <<(value)
      push(value)
      self
    end

    def [](index, length=nil)
      return range(index.first, index.max) if index.is_a? Range
      return at(index) if length.nil?
      case length <=> 0
        when 1 then range(index, index + length - 1)
        when 0 then []
        when -1 then nil
      end
    end

    def []=(index, value)
      redis.lset(key, index, marshal(value))
    end

    def ==(x)
      values == x
    end

    def -(x)
      values - x
    end

    def insert(where, pivot, value)
      redis.linsert(key, where, marshal(pivot), marshal(value))
    end

    def push(*values)
      redis.rpush(key, values.map{|v| marshal(v)})
      redis.ltrim(key, -options[:max_length], -1) if options[:max_length]
    end

    def pop
      unmarshal redis.rpop(key)
    end

    def pop_push(destination)
      unmarshal redis.rpoplpush(key, destination.is_a?(Redis::List) ? destination.key : destination.to_s)
    end

    # add a member to the head of the list
    def unshift(*values)
      redis.lpush(key, values.map{|v| marshal(v)})
      redis.ltrim(key, 0, options[:max_length] - 1) if options[:max_length]
    end

    # remove a member from the head of the list
    def shift
      unmarshal redis.lpop(key)
    end

    def values
      range(0, -1) || []
    end

    def delete!(name, count=0)
      redis.lrem(key, count, marshal(name))
    end

    def each(&block)
      values.each(&block)
    end

    def range(start_index, end_index)
      redis.lrange(key, start_index, end_index).map {|v| unmarshal(v)}
    end

    def at(index)
      unmarshal redis.lindex(key, index)
    end

    def last
      at(-1)
    end

    def length
      redis.llen(key)
    end

    alias_method :size, :length

    def empty?
      length == 0
    end

    def to_s
      values.join(', ')
    end

    def method_missing(*args)
      self.values.send(*args)
    end

    expiration_filter :[]=, :push, :insert, :unshift
  end
end