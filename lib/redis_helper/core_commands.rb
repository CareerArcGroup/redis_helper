class Redis
  module RedisHelper
    module CoreCommands
      def exists?
        redis.exists key
      end

      def delete!
        redis.del key
      end
      alias_method :clear!, :delete!

      def type
        redis.type key
      end

      def rename(name, set_key=true, nx=false)
        dest = name.is_a?(self.class) ? name.key : name
        ret = redis.send(nx ? :renamenx : :rename, key), dest
        @key = dest if ret && set_key
        ret
      end

      def expire(seconds)
        redis.expire key, seconds
      end

      def expire_at(unix_time)
        redis.expireat key, unix_time
      end

      def perist
        redis.persist key
      end

      def ttl
        redis.ttl key
      end

      def move(db_index)
        redis.move key, db_index
      end

      def sort(options={})
        options[:order] = "asc alpha" if options.keys.count == 0
        val = redis.sort(key, options)
        val.is_a?(Array) ? val.map{|v| unmarshal(v)} : val
      end

      def marshal(value, do_marshal=false)
        (options[:marshal] == true || do_marshal) ? to_serialized(value) : value
      end

      def unmarshal(value, do_marshal=false)
        (!value.nil? && (options[:marshal] == true || do_marshal)) ? from_serialized(value) : value
      end

      def send_reversable(forward_cmd, reverse, *args)
        reverse_cmd = "#{forward_cmd.to_s[0]}rev#{forward_cmd.to_s[1..-1]}"
        redis.public_send(reverse == true ? reverse_cmd : forward_cmd, *args)
      end

      private

      def to_serialized(obj)
        Marshal.dump(obj)
      end

      def from_serialized(str)
        Marshal.load(str)
      end
    end
  end
end