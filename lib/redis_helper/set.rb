class Redis
  class Set < Redis::RedisObject
    require 'enumerator'
    include Enumerable
    include Redis::RedisHelper::CoreCommands

    attr_reader :key, :options

    def <<(value)
      add(value); self
    end

    def add(value)
      redis.sadd(key, marshal(value)) if value.nil? || !Array(value).empty?
    end

    def pop
      unmarshal redis.spop(key)
    end

    def random_member
      unmarshal redis.srandmember(key)
    end

    def merge(*values)
      values.flatten.each_slice(1000) do |arr|
        redis.sadd(key, arr.map{|v| marshal(v)})
      end
    end

    def members
      vals = redis.smembers(key)
      vals.nil? ? [] : vals.map{|v| unmarshal(v)}
    end

    def member?(value)
      redis.sismember(key, marshal(value))
    end
    alias_method :include?, :member?

    def delete(value)
      redis.srem(key, marshal(value))
    end

    def delete_if(&block)
      res = false
      redis.smembers(key).each do |m|
        if block.call(unmarshal(m))
          res = redis.srem(key, m)
        end
      end
      res
    end

    def each(&block)
      members.each(&block)
    end

    def intersection(*sets)
      redis.sinter(key, *keys_from_objects(sets)).map{|v| unmarshal(v)}
    end
    alias_method :intersect, :intersection
    alias_method :&, :intersection

    def intersection_store(name, *sets)
      sets ||= []
      sets << key
      redis.sinterstore(name, *keys_from_objects(sets))
    end

    def union(*sets)
      redis.sunion(key, *keys_from_objects(sets)).map{|v| unmarshal(v)}
    end
    alias_method :|, :union
    alias_method :+, :union

    def union_store(name, *sets)
      sets ||= []
      sets << key
      redis.sunionstore(name, *keys_from_objects(sets))
    end

    def difference(*sets)
      redis.sdiff(key, *keys_from_objects(sets)).map{|v| unmarshal(v)}
    end
    alias_method :^, :difference
    alias_method :-, :difference

    def difference_store(name, *sets)
      redis.sdiffstore(name, key, *keys_from_objects(sets))
    end

    def move(value, destination)
      redis.smove(key, destination.is_a?(Redis::Set) ? destination.key : destination.to_s, value)
    end

    def length
      redis.scard(key)
    end
    alias_method :size, :length
    alias_method :count, :length

    def empty?
      length == 0
    end

    def ==(x)
      members == x
    end

    def to_s
      members.join(', ')
    end

    expiration_filter :add

    private

    def keys_from_objects(sets)
      raise ArgumentError, "Must pass in one or more set names" if sets.empty?
      sets.collect{|set| set.is_a?(Redis::Set) ? set.key : set}
    end
  end
end