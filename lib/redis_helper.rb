require "redis"

# core
require "redis_helper/core_commands"

# objects
require "redis_helper/redis_object"
require "redis_helper/counter"
require "redis_helper/value"
require "redis_helper/list"
require "redis_helper/set"
require "redis_helper/sorted_set"
require "redis_helper/hash_set"
require "redis_helper/lock"

class Redis
  module RedisHelper
    class NotConnected < StandardError; end
    class NilObjectId  < StandardError; end
    class UndefinedCounter < StandardError; end
    class MissingId < StandardError; end

    def self.redis
      @redis ||= nil
      @redis || raise(NotConnected, "Redis connection not available")
    end

    def self.redis=(conn)
      @redis = conn
    end

    def self.included(klass)
      klass.instance_variable_set('@redis', nil)
      klass.instance_variable_set('@redis_data', {})

      klass.send :include, InstanceMethods
      klass.extend ClassMethods
    end

    module ClassMethods

      # -------------------------------------------------------------------------
      # core methods
      # -------------------------------------------------------------------------

      attr_writer :redis
      def redis
        @redis || RedisHelper.redis
      end

      attr_writer :redis_data
      def redis_data
        @redis_data ||= {}
      end

      def redis_prefix=(prefix)
        @redis_prefix = prefix
      end

      def redis_prefix(klass=self)
        @redis_prefix ||= klass.name.to_s.
          sub(%r{(.*::)}, '').
          gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').
          gsub(/([a-z\d])([A-Z])/, '\1_\2').
          downcase
      end

      def redis_field_redis(name)
        klass = first_ancestor_with(name)
        klass.redis_data[name.to_sym][:redis] || self.redis
      end

      def redis_field_key(name, id=nil, context=self)
        klass = first_ancestor_with(name)
        if key = klass.redis_data[name.to_sym][:key]
          if key.respond_to?(:call)
            key = key.call context
          else
            context.instance_eval "%(#{key})"
          end
        else
          raise_nil_id(name, klass) if id.nil? and !klass.redis_data[name.to_sym][:global]
          "#{redis_prefix(klass)}:#{id}:#{name}"
        end
      end

      def redis_field_data(name)
        klass = first_ancestor_with(name)
        klass.redis_data[name.to_sym]
      end

      def redis_id_field(id=nil)
        @redis_id_field = id || @redis_id_field || :id
      end

      def first_ancestor_with(name)
        if redis_data && redis_data.key?(name.to_sym)
          self
        elsif superclass && superclass.respond_to?(:redis_data)
          superclass.first_ancestor_with(name)
        end
      end

      def raise_nil_id(name, klass)
        raise(NilObjectId,
          "[#{klass.redis_data[name.to_sym]}] Attempt to address redis-object " +
          ":#{name} on class #{klass.name} with nil id (unsaved record?) [object_id=#{object_id}]")
      end

      # -------------------------------------------------------------------------
      # redis values/sets
      # -------------------------------------------------------------------------

      def counter(name, options={})
        build_methods(name, Redis::Counter, false, { start: 0, type: options[:start] == 0 ? :increment : :decrement }.merge(options))
      end

      def value(name, options={})
        build_methods(name, Redis::Value, true, options)
      end

      def list(name, options={})
        build_methods(name, Redis::List, false, options)
      end

      def set(name, options={})
        build_methods(name, Redis::Set, false, options)
      end

      def hash_set(name, options={})
        build_methods(name, Redis::HashSet, false, options)
      end

      def sorted_set(name, options={})
        build_methods(name, Redis::SortedSet, false, options)
      end

      def lock(name, options={})
        build_methods("#{name}_lock", Redis::Lock, false, options)
      end

      private

      def build_methods(name, klass, has_setter=false, options={})
        type = underscore(klass.to_s).split('/').last.to_sym
        redis_data[name.to_sym] = options.merge(type: type)

        mod = Module.new do
          define_method(name) do
            instance_variable_get("@#{name}") or instance_variable_set("@#{name}",
              klass.new(redis_field_key(name), redis_field_redis(name), redis_field_data(name))
            )
          end

          if has_setter
            define_method("#{name}=") do |value|
              public_send(name).value = value
            end
          end
        end

        return (include mod) unless options[:global]
        extend mod

        define_method(name) do
          self.class.public_send(name)
        end

        if has_setter
          define_method("#{name}=") do |value|
            self.class.public_send("#{name}=", value)
          end
        end
      end

      def underscore(camel_cased_word)
        return camel_cased_word unless camel_cased_word =~ /[A-Z-]|::/
        word = camel_cased_word.to_s.gsub(/::/, '/')
        word.gsub!(/([A-Z\d]+)([A-Z][a-z])/,'\1_\2')
        word.gsub!(/([a-z\d])([A-Z])/,'\1_\2')
        word.tr!("-", "_")
        word.downcase!
        word
      end
    end

    module InstanceMethods
      def redis
        self.class.redis
      end

      def redis_data
        self.class.redis_data
      end

      def redis_field_redis(name)
        return self.class.redis_field_redis(name)
      end

      def redis_field_key(name)
        id = send(self.class.redis_id_field) rescue self.class.raise_nil_id(name, self.class)
        self.class.redis_field_key(name, id)
      end

      def redis_field_data(name)
        self.class.redis_field_data(name)
      end
    end
  end
end