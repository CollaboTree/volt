require 'volt/models/model_wrapper'
require 'volt/models/array_model'
require 'volt/reactive/object_tracking'

class NilMethodCall < NoMethodError
  def true?
    false
  end
  
  def false?
    true
  end
end

class Model
  include ReactiveTags
  include ModelWrapper
  include ObjectTracking
  
  attr_accessor :attributes
  attr_reader :parent, :path
  
  def nil?
    attributes.nil?
  end
  
  def false?
    attributes.false?
  end
  
  def true?
    attributes.true?
  end
  
  def initialize(attributes={}, parent=nil, path=nil, class_paths=nil)
    self.attributes = wrap_values(attributes)
    @parent = parent
    @path = path
  end
  
  # Pass the comparison through
  def ==(val)
    attributes == val
  end
  
  # Pass through needed
  def !
    !attributes
  end
  
  tag_method(:delete) do
    destructive!
  end
  def delete(*args)
    __clear_element(args[0])
    attributes.delete(*args)
    trigger_by_attribute!('changed', args[0])
  end
  
  tag_all_methods do
    destructive! do |method_name|
      method_name[0] == '_' && method_name[-1] == '='
    end
    pass_reactive! do |method_name|
      method_name[0] == '_' && method_name[-1] == '='
    end
  end
  def method_missing(method_name, *args, &block)
    if method_name[0] == '_'
      if method_name[-1] == '='
        # Assigning an attribute with =
        assign_attribute(method_name, *args, &block)
      else
        read_attribute(method_name)
      end
    else
      # Call method directly on attributes.  (since they are
      # not using _ )
      attributes.send(method_name, *args, &block)
    end
  end
  
  # Do the assignment to a model and trigger a changed event
  def assign_attribute(method_name, *args, &block)
    self.expand!
    # Assign, without the =
    attribute_name = method_name[0..-2].to_sym
    
    value = args[0]
    __assign_element(attribute_name, value)
    
    attributes[attribute_name] = wrap_value(value)
    trigger_by_attribute!('changed', attribute_name)
  end
  
  # When reading an attribute, we need to handle reading on:
  # 1) a nil model, which returns a wrapped error
  # 2) reading directly from attributes
  # 3) trying to read a key that doesn't exist.
  def read_attribute(method_name)
    # Reading an attribute, we may get back a nil model.
    method_name = method_name.to_sym
    
    if attributes == nil
      # The method we are calling is on a nil model, return a wrapped 
      # exception.
      return return_undefined_method(method_name)
    elsif attributes && attributes.has_key?(method_name)
      # Method has the key, look it up directly
      return attributes[method_name]
    else
      return new_model(nil, self, method_name)
    end
  end
  
  def return_undefined_method(method_name)
    # Methods called on nil capture an error so the user can know where
    # their nil calls are.  This error can be re-raised at a later point.
    begin
      raise NilMethodCall.new("undefined method `#{method_name}' for #{self.to_s}")
    rescue => e
      result = e

      # Cleanup backtrace around ReactiveValue's
      # TODO: this could be better
      result.backtrace.reject! {|line| line['lib/models/model.rb'] || line['lib/models/live_value.rb'] }
    end
  end
  
  def new_model(*args)
    Model.new(*args)
  end
  
  def trigger_by_attribute!(event_name, attribute, *passed_args)
    trigger_by_scope!(event_name, *passed_args) do |scope|
      method_name, *args, block = scope
      
      # TODO: Opal bug
      args ||= []
      
      # Any methods without _ are not directly related to one attribute, so
      # they should all trigger
      !method_name || method_name[0] != '_' || (method_name == attribute.to_sym && args.size == 0)
    end
  end
  
  # If this model is nil, it makes it into a hash model, then
  # sets it up to track from the parent.
  def expand!
    if attributes.nil?
      self.attributes = {}
      if @parent
        @parent.expand!
      
        @parent.attributes[@path] = self
      end
    end
  end
  
  tag_method(:<<) do
    destructive!
    pass_reactive!
  end
  # Initialize an empty array and append to it
  def <<(value)
    @parent.expand!
    result = @parent.send(@path)
    
    if result.nil?
      # If this isn't a model yet, instantiate it
      @parent.send(:"#{@path}=", ArrayModel.new([], @parent, @path))
      result = @parent.send(@path)
      
      # Add the new item
      result << value
    end
    
    return result
  end
  
  def inspect
    "<#{self.class.to_s}:#{@path} #{attributes.inspect}>"
  end
  
  
  private
    # Clear the previous value and assign a new one
    def __assign_element(key, value)
      __clear_element(key)
      __track_element(key, value)
    end
    
    # TODO: Somewhat duplicated from ReactiveArray
    def __clear_element(key)
      # Cleanup any tracking on an index
      # TODO: is this send a security risk?
      # puts "TRY TO CLEAR: #{key} - #{@reactive_element_listeners && @reactive_element_listeners.keys.inspect}"
      if @reactive_element_listeners && @reactive_element_listeners[key]        
        @reactive_element_listeners[key].remove
        @reactive_element_listeners.delete(key)
      end
    end
  
    def __track_element(key, value)
      puts "TRACK: #{key} - #{value.inspect}"
      __setup_tracking(key, value) do |event, key, args|
        trigger_by_attribute!(event, key, *args)
      end
    end
end