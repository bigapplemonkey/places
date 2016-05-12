class AddressComponent
    attr_reader :long_name, :short_name, :types

    def initialize(hash)
        # @long_name = hash[:long_name]
        # @short_name = hash[:short_name]
        hash.slice(:long_name, :short_name, :types).each do |k, v|
            instance_variable_set("@#{k}", v)
        end

    end
end