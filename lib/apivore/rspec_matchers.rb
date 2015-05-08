require 'json-schema'
require 'rspec/expectations'
require 'net/http'

module Apivore
  module RspecMatchers
    extend RSpec::Matchers::DSL
    matcher :be_valid_swagger do |version|
      match do |body|
        @api_description = Swagger.new(JSON.parse(body))
        @errors = @api_description.validate
        @errors.empty?
      end

      failure_message do |body|
        msg = "The document fails to validate as Swagger #{@api_description.version}:\n"
        msg += @errors.join("\n")
      end
    end

    matcher :have_models_for_all_get_endpoints do
      match do |body|
        @errors = []
        swagger = Swagger.new(JSON.parse(body))
        swagger.each_response do |path, method, response_code, schema|
          if method == 'get' && !schema
            @errors << "Unable to find a valid model for #{path} get #{response_code} response."
          end
        end
        @errors.empty?
      end

      failure_message do
        @errors.join("\n")
      end
    end

    matcher :be_consistent_with_swagger_definitions do |master_swagger, current_service|

      attr_reader :actual, :expected

      def cleaned_definitions(definitions, current_service)
        definitions.each do |key, definition_fields|
          # We ignore definitions that are owned exclusively by the current_service
          if [current_service] == definition_fields['x-services']
            definitions[key] = nil
          else
            # 'x-services' is added by api.westfield.io when aggregating swagger docs
            # Individual services will not have a 'x-services' property so we need to remove it to allow the comparison to pass
            definitions[key] = definition_fields.except 'x-services'
          end
        end.select{ |_, value| !value.nil? }
      end

      match do |body|
        our_swagger = JSON.parse(body)
        master_definitions = cleaned_definitions(master_swagger["definitions"], current_service)
        our_definitions = our_swagger["definitions"]
        @actual = our_definitions.slice(*master_definitions.keys)
        @expected = master_definitions.slice(*our_definitions.keys)
        @actual == @expected
      end

      diffable
    end

    matcher :conform_to_the_documented_model_for do |swagger, fragment|
      match do |body|
        body = JSON.parse(body)
        draft04 = JSON.parse(File.read(File.expand_path("../../../data/draft04_schema.json", __FILE__)))
        draft04_schema = JSON::Schema.new(draft04, Addressable::URI.parse('http://json-schema.org/draft-04/schema'))
        JSON::Validator.add_schema(draft04_schema)
        @errors = JSON::Validator.fully_validate(swagger, body, fragment: fragment)
        @errors.empty?
      end

      failure_message do |body|
        @errors.map { |e| e.sub("'#", "'#{path}#").gsub(/^The property|in schema.*$/,'') }.join("\n")
      end
    end
  end
end
