# require 'volt/models/validations/errors'
require 'volt/models/validations/length'

# Include in any class to get validation logic
module Validations
  module ClassMethods
    def validate(field_name, options)
      @validations ||= {}
      @validations[field_name] = options
    end

    def validations
      @validations
    end
  end

  def self.included(base)
    base.send :extend, ClassMethods
  end

  # Sometimes we want to skip checking a field until some event
  # has happened (usually a field has been typed in or blurred)
  def exclude_from_errors!(field_name)
    @exclude_from_errors ||= {}
    @exclude_from_errors[field_name] = true

    @include_in_errors.delete(field_name) if @include_in_errors

    trigger_for_methods!('changed', :errors, :marked_errors)
  end

  # Once a field is ready, we can use include_in_errors! to start
  # showing its errors.
  def mark_field!(field_name)
    @marked_fields ||= {}
    @marked_fields[field_name] = true

    trigger_for_methods!('changed', :errors, :marked_errors)
  end

  def marked_errors
    errors(true)
  end

  def errors(marked_only=false)
    errors = {}

    validations = self.class.validations

    if validations
      # Merge into errors, combining any error arrays
      merge = Proc.new do |new_errors|
        errors.merge!(new_errors) do |key, new_val, old_val|
          new_val + old_val
        end
      end

      # Run through each validation
      validations.each_pair do |field_name, options|
        if marked_only
          # When marked only, skip any validations on non-marked fields
          next unless @marked_fields && @marked_fields[field_name]
        end

        options.each_pair do |validation, args|
          # Call the specific validator, then merge the results back
          # into one large errors hash.
          case validation
          when :length
            merge.call(Length.validate(self, field_name, args))
          end
        end
      end
    end

    # puts "ERROR: #{errors.inspect}"

    return errors
  end
end