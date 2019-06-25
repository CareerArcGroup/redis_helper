class Redis
  class SortedSet < Redis::RedisObject
    include Redis::RedisHelper::CoreCommands
    attr_reader :key, :options

    def []=(member, score)
      add(member, score)
    end

    def add(*args)
      if args.size == 1 && args[0].is_a?(Array)
        return redis.zadd(key, args[0].map {|p| [p[1], marshal(p[0])]})
      elsif args.size ==2
        return redis.zadd(key, args[1], marshal(args[0]))
      else
        raise ArgumentError, 'wrong number of arguments'
      end
    end

    def merge(values)
      redis.zadd(key, values.map {|v,s| [s, marshal(v)]})
    end

    alias_method :add_all, :merge

    def [](index, length=nil)
      return range(index.first, index.max) if index.is_a? Range
      return score(index) || 0 unless length

      case length <=> 0
        when 1 then range(index, index + length - 1)
        when 0 then []
        when -1 then nil
      end
    end

    def score(member)
      result = redis.zscore(key, marshal(member))
      result.to_f unless result.nil?
    end

    def rank(member, reverse=false)
      (n = send_reversable(:zrank, reverse, key, marshal(member))) ? n.to_i : nil
    end

    def rev_rank(member)
      rank(member, true)
    end

    def range(start_index, end_index, options={})
      send_reversable(:zrange, options[:reverse], key, start_index, end_index, options).map {|e| (options[:with_scores]) ? [unmarshal(e[0]), e[1]] : unmarshal(e)}
    end

    def rev_range(start_index, end_index, options={})
      range(start_index, end_index, options.merge(reverse: true))
    end

    def range_by_score(min, max, options={})
      args = {}
      args[:limit] = [options[:offset] || 0, options[:limit] || options[:count]] if options[:offset] || options[:limit] || options[:count]
      args[:with_scores] = options[:with_scores] == true

      send_reversable(:zrangebyscore, options[:reverse], key, min, max, args).map {|v| args[:with_scores] ? [unmarshal(v[0]), v[1]] : unmarshal(v)}
    end

    def rev_range_by_score(min, max, options={})
      range_by_score(min, mix, options.merge(reverse: true))
    end

    def rem_range_by_rank(min, max)
      redis.zremrangebyrank(key, min, max)
    end

    def rem_range_by_score(min, max)
      redis.zremrangebyscore(key, min, max)
    end

    def delete!(value)
      redis.zrem(key, marshal(value))
    end

    def delete_if!(&block)
      raise ArgumentError, "Missing block to SortedSet#{delete_if}" unless block_given?
      result = false
      redis.zrange(key, 0, -1).each do |m|
        if block.call(unmarshal(m))
          result = redis.zrem(key, m)
        end
      end
      result
    end

    def increment(member, by=1)
      redis.zincrby(key, by, marshal(member)).to_i
    end

    def decrement(member, by=1)
      redis.zincrby(key, -by, marshal(member)).to_i
    end

    def intersection(*sets)
      redis.zinter(key, *keys_from_objects(sets)).map {|v| unmarshal(v)}
    end

    def intersect_and_store(name, *sets)
      redis.zinterstore(name, keys_from_objects([self] + sets))
    end

    def union(*sets)
      redis.zunion(key, *keys_from_objects(sets)).map {|v| unmarshal(v)}
    end

    alias_method :|, :union
    alias_method :+, :union

    def union_and_store(name, *sets)
      redis.zunionstore(name, keys_from_objects([self] + sets))
    end

    def difference(*sets)
      redis.zdiff(key, *keys_from_objects(sets)).map {|v| unmarshal(v)}
    end

    alias_method :^, :difference
    alias_method :-, :difference

    def difference_and_store(name, *sets)
      redis.zdiffstore(name, key, *keys_from_objects(sets))
    end

    def empty?
      length == 0
    end

    def ==(other)
      members == x
    end

    def to_s
      members.join(', ')
    end

    def at(index)
      range(index, index).first
    end

    def first
      at(0)
    end

    def last
      at(-1)
    end

    def length
      redis.zcard(key)
    end

    alias_method :size, :length
    alias_method :count, :length

    def range_size(min, max)
      redis.zcount(key, min, max)
    end

    def member?(value)
      !redis.zscore(key, marshal(value)).nil?
    end

    alias_method :include?, :member?

    def members(options={})
      range(0, -1, options) || []
    end

    alias_method :to_a, :members

    expiration_filter :[]=, :add, :merge, :add_all, :difference_and_store, :increment, :decrement, :intersection, :intersect_and_store, :union_and_store

    private

    def keys_from_objects(sets)
      raise ArgumentError, "Must pass in one or more set names" if sets.empty?
      sets.collect{|set| set.is_a?(Redis::SortedSet) ? set.key : set}
    end
  end
end