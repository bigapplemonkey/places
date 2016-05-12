Mongo::Logger.logger.level = ::Logger::INFO

class Place
    include ActiveModel::Model

    attr_accessor :id, :formatted_address, :location, :address_components

    def initialize(hash)
        @id = hash[:_id].nil? ? hash[:id] : hash[:_id].to_s
        @formatted_address = hash[:formatted_address]
        @location = Point.new(hash[:geometry][:geolocation])
        @address_components = []
        if !hash[:address_components].nil?
            hash[:address_components].each { |e| @address_components << AddressComponent.new(e)  }
        end
    end

    def self.mongo_client
        Mongoid::Clients.default
    end

    def self.collection
        self.mongo_client['places']
    end

    def self.load_all(file)
        # p file.path
        # p file
        file=File.read(file.path)
        hash=JSON.parse(file)
        r = collection.insert_many(hash)
        r.inserted_count
    end

    def self.find_by_short_name(input_string)
        collection.find(:'address_components.short_name' => input_string)
    end

    def self.to_places(collection_view)
        collection_view.map { |place_info| Place.new(place_info) }
    end

    def self.find(id)
        doc=collection.find(:_id => BSON::ObjectId.from_string(id)).first
        doc.nil? ? nil : Place.new(doc)
    end

    def self.all(offset=0, limit=nil)
        limit.nil? ? to_places(collection.find.skip(offset)) : to_places(collection.find.skip(offset).limit(limit))
    end

    def destroy
        self.class.collection.find(_id: BSON::ObjectId.from_string(@id)).delete_one()
    end

    def self.get_address_components(sort=nil, offset=0, limit=nil)
        query_maps = [
            {:$unwind => "$address_components"},
            {:$project => {
                :address_components => 1,
                :formatted_address => 1,
                :'geometry.geolocation' => 1
                }}
        ]

        query_maps << { :$sort => sort} if !sort.nil?
        query_maps << { :$skip => offset} if !offset.nil?
        query_maps << { :$limit => limit} if !limit.nil?

        collection.find.aggregate(query_maps)
    end

    def self.get_country_names
        query_maps = [
            {:$project => {
                :_id => 0,
                :'address_components.long_name' => 1,
                :'address_components.types' => 1
                }
            },
            {:$unwind => "$address_components"},
            {:$match => {
                :"address_components.types" => "country"
                }
            },
            {:$match => {
                :"address_components.types" => "country"
                }
            },
            {:$group => {
                :_id => "$address_components.long_name"
                }
            }
        ]
        collection.find.aggregate(query_maps).to_a.map{|h| h[:_id]}
    end

    def self.find_ids_by_country_code(country_code)
        query_maps = [
            {:$match => {
                :"address_components.types" => "country",
                :"address_components.short_name" => country_code
                }
            },
            {:$project => {
                :_id => 1
                }
            }
        ]
        collection.find.aggregate(query_maps).to_a.map{|h| h[:_id].to_s}
    end

    def self.create_indexes
        collection.indexes.create_one({:"geometry.geolocation" => Mongo::Index::GEO2DSPHERE})
    end

    def self.remove_indexes
        collection.indexes.drop_one("geometry.geolocation_2dsphere")
    end

    def self.near(point, max_meters=nil)
        query_map = {
            :"geometry.geolocation" => {
                :$near => {
                    :$geometry => point.to_hash,
                    :$maxDistance => max_meters
                }
            }

        }

        collection.find(query_map)
    end

    def near(max_meters=nil)
        self.class.to_places(self.class.near(@location,max_meters))
    end

    def photos(offset=0, limit=nil)
        photos = []
        result = Photo.find_photos_for_place(@id).skip(offset)
        result.limit(limit) if !limit.nil?
        result.each { |doc|  photos << Photo.new(doc) }
        photos
    end

    def persisted?
        !@id.nil?
    end
end