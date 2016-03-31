class TypeStruct
  require "type_struct/union"
  require "type_struct/array_of"
  require "type_struct/hash_of"
  require "type_struct/interface"
  require "type_struct/version"

  UnionNotFoundError = Class.new(StandardError)

  def initialize(arg)
    sym_arg = {}
    arg.each do |k, v|
      sym_arg[k.to_sym] = v
    end
    self.class.members.each do |k|
      self[k] = sym_arg[k]
    end
  end

  def ==(other)
    return false unless TypeStruct === other
    to_h == other.to_h
  end

  def []=(k, v)
    __send__ "#{k}=", v
  end

  def [](k)
    __send__ k
  end

  def inspect
    m = to_h.map do |k, v|
      "#{k}=#{v.inspect}"
    end
    "#<#{self.class} #{m.join(', ')}>"
  end
  alias to_s inspect

  def to_h
    m = {}
    self.class.members.each do |k|
      m[k] = self[k]
    end
    m
  end

  module ClassMethods
    def from_hash(h)
      unless Hash === h
        h = h.to_hash if h.respond_to?(:to_hash)
        unless Hash === h
          raise TypeError, "#{self}.from_hash only accept Hash got `#{h.class}'"
        end
      end
      args = {}
      h.each do |key, value|
        key = key.to_sym
        t = type(key)
        args[key] = try_convert(t, key, value)
      end
      new(args)
    end

    def definition
      const_get(:DEFINITION)
    end

    def members
      definition.keys
    end

    def type(k)
      definition[k]
    end

    def valid?(k, v)
      definition[k] === v
    end

    private

    def try_convert(klass, key, value)
      return nil unless !klass.nil? && !value.nil?

      case klass
      when Union
        errors = []
        klass.each do |k|
          t = begin
                try_convert(k, key, value)
              rescue TypeError => e
                errors << e
                nil
              end
          return t if !t.nil?
        end
        raise UnionNotFoundError, "#{klass} is not found with value `#{value}'\nerrors:\n#{errors.join("\n")}"
      when ArrayOf
        unless Array === value
          raise TypeError, "#{self}##{key} expect #{klass.inspect} got #{value.inspect}"
        end
        value.map { |v| try_convert(klass.type, key, v) }
      when HashOf
        unless Hash === value
          raise TypeError, "#{self}##{key} expect #{klass.inspect} got #{value.inspect}"
        end
        new_hash = {}
        value.each do |hk, hv|
          new_hash[hk] = try_convert(klass.value_type, key, hv)
        end
        new_hash
      else
        if klass.respond_to?(:ancestors)
          if klass.ancestors.include?(TypeStruct)
            klass.from_hash(value)
          elsif klass.ancestors.include?(Struct)
            struct = klass.new
            value.each { |k, v| struct[k] = v }
            struct
          elsif klass === value
            value
          else
            raise TypeError, "#{self}##{key} expect #{klass.inspect} got #{value.inspect}"
          end
        else
          value
        end
      end
    end
  end

  class << self
    alias original_new new
    def new(**args, &block)
      c = Class.new(TypeStruct) do
        extend ClassMethods
        const_set :DEFINITION, args

        class << self
          alias_method :new, :original_new
        end

        args.each_key do |k|
          define_method(k) do
            instance_variable_get("@#{k}")
          end

          define_method("#{k}=") do |v|
            unless self.class.valid?(k, v)
              raise TypeError, "#{self.class}##{k} expect #{self.class.type(k)} got #{v.inspect}"
            end
            instance_variable_set("@#{k}", v)
          end
        end
      end
      if block_given?
        c.module_eval(&block)
      end
      c
    end
  end
end
