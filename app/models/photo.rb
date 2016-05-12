class Photo
    attr_accessor :id, :location
    attr_writer :contents

    def self.mongo_client
        Mongoid::Clients.default
    end

    def initialize(hash={})
        @id = hash[:_id].nil? ? hash[:id] : hash[:_id].to_s
        if hash[:metadata]
            @location = hash[:metadata][:location] ? Point.new(hash[:metadata][:location]): nil
            @place = hash[:metadata][:place]
        end
    end

    def persisted?
        !@id.nil?
    end

    def save
        if !self.persisted?
            geo_loc = EXIFR::JPEG.new(@contents).gps
            @contents.rewind
            description = {}
            description[:content_type] = "image/jpeg"
            @location = Point.new({ :lat => geo_loc[:latitude], :lng => geo_loc[:longitude]})
            description[:metadata] = {
                :location => @location.to_hash,
                :place => @place
            }
            grid_file = Mongo::Grid::File.new(@contents.read, description)
            id=self.class.mongo_client.database.fs.insert_one(grid_file)
            @id=id.to_s
        else
            bson_id = BSON::ObjectId.from_string(@id)
            id=self.class.mongo_client.database.fs.find( :_id => bson_id)
                .update_one( :$set => {
                    :metadata => {
                        :location => @location.to_hash,
                        :place => @place
                    }
                    })
        end
    end

    def self.all(offset=0, limit=nil)
        photos=[]
        docs = limit ? mongo_client.database.fs.find.skip(offset).limit(limit) : mongo_client.database.fs.find.skip(offset)
        docs.each{ |doc| photos << Photo.new(doc) }
        photos
    end

    def self.find(id)
        bson_id = BSON::ObjectId.from_string(id)
        doc = mongo_client.database.fs.find( :_id => bson_id).first
        return doc.nil? ? nil : Photo.new(doc)
    end

    def contents
        bson_id = BSON::ObjectId.from_string(@id)
        doc = self.class.mongo_client.database.fs.find_one(:_id => bson_id)
        puts "Testing #{doc}"
        if !doc.nil?
            buffer = ""
            doc.chunks.reduce([]) do |x,chunk|
                buffer << chunk.data.data
            end
            return buffer
        else
            nil
        end
    end

    def destroy
        bson_id = BSON::ObjectId.from_string(@id)
        puts "Testing #{bson_id}"
        self.class.mongo_client.database.fs.find(:_id => bson_id).delete_one
    end

    def find_nearest_place_id(distance)
        doc = Place.near(@location, distance)
            .limit(1)
            .projection(:_id => 1)
            .first
            puts "Testing #{doc}"
        result = doc.nil? ? nil : doc[:_id]
    end

    def place
      Place.find(@place.to_s) if !@place.nil?
    end

    def place=(object)
        case
        when object.is_a?(Place)
            @place = BSON::ObjectId(object.id)
        when object.is_a?(String)
            @place = BSON::ObjectId(object)
        else
            @place = object
        end
    end

    def self.find_photos_for_place(place_id)
        bson_id = place_id.is_a?(String) ? BSON::ObjectId.from_string(place_id) : place_id
        mongo_client.database.fs.find( :"metadata.place" => bson_id)
    end

end
