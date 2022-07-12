local tables = {}

local places = {'country','state','city','town','village','hamlet','suburb'}
local cities = {'city','town','village','hamlet','suburb'}


tables.geometry_countries = osm2pgsql.define_table({
    name = 'geometry_countries',
    ids = { type = 'relation', id_column = 'relation_id' },
    columns = {
        { column = 'osm_type',     type = 'text' , not_null = false},
        { column = 'tags',     type = 'hstore' },
        { column = 'boundary',     type = 'geometry' , projection = 4326 },
    }, 
    schema = 'public' 
})

tables.geometry_regions = osm2pgsql.define_table({
    name='geometry_regions', 
    ids = { type = 'relation', id_column = 'relation_id' },
    columns = {
        { column = 'osm_type',     type = 'text' , not_null = false},
        { column = 'tags',     type = 'hstore' },
        { column = 'boundary',     type = 'geometry' , projection = 4326 },
    }, 
    schema = 'public' 
})

tables.geometry_districts = osm2pgsql.define_table({
    name='geometry_districts', 
    ids = { type = 'relation', id_column = 'relation_id' },
    columns = {
        { column = 'osm_type',     type = 'text' , not_null = false},
        { column = 'tags',     type = 'hstore' },
        { column = 'boundary', type = 'geometry' , projection = 4326 },
    }, 
    schema = 'public' 
})

tables.geometry_cities = osm2pgsql.define_table({
    name='geometry_cities',
    ids = { id_column = 'id', type = 'any', type_column = 'type' },
    columns = {
        { column = 'osm_type',     type = 'text' , not_null = false},
        { column = 'tags',     type = 'hstore' },
        { column = 'boundary',     type = 'geometry', projection = 4326 }
    }, 
    schema = 'public' 
})

tables.geometry_cities_points = osm2pgsql.define_table({
    name='geometry_cities_points',
    ids = { id_column = 'id', type = 'any', type_column = 'type' },
    columns = {
        { column = 'osm_type',     type = 'text' , not_null = false},
        { column = 'tags',     type = 'hstore' },
        { column = 'center',     type = 'point', projection = 4326  },
    }, 
    schema = 'public' 
})



function clean_tags(tags)
    tags.odbl = nil
    tags.created_by = nil
    tags.source = nil
    tags['source:ref'] = nil

    return next(tags) == nil
end


local function has_value (tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end


-- Обработка узлов
function geometry_process_node(object)
    -- We are only interested in places
    if not object.tags.place then
        return
    end

    clean_tags(object.tags)

    -- local osm_type = object:grab_tag('boundary')


    if has_value(places, object.tags.place) then
        tables.geometry_cities_points:add_row({
            tags = object.tags,
            -- osm_type = osm_type,
            center = { create = 'point' }
        })
    end
end


-- Обработка путей
function geometry_process_way(object)
    -- Только с тегом place
    if not object.tags.place then
        return
    end

    clean_tags(object.tags)

    -- local osm_type = object:grab_tag('boundary')


    if object.is_closed and has_value(places, object.tags.place) then
        tables.geometry_cities:add_row({
            tags = object.tags,
            -- osm_type = osm_type,
            boundary = { create = 'area' }
        })
    end
    
end

-- Обработка отношений
function geometry_process_relation(object)

    clean_tags(object.tags)

    -- local osm_type = object:grab_tag('boundary')
    
    -- countries
    if object.tags.type == 'boundary' and object.tags.admin_level == '2' then
        -- print('relation_id added')
        -- print(object.id)
        -- print(object.tags.name)
        tables.geometry_countries:add_row({
            tags = object.tags,
            -- osm_type = osm_type,
            boundary = { create = 'area' }
        })
    end

    -- -- regions
    if object.tags.type == 'boundary' and object.tags.admin_level == '4' then
        tables.geometry_regions:add_row({
            tags = object.tags,
            -- osm_type = osm_type,
            boundary = { create = 'area' }
        })
    end

     -- districts
    if object.tags.type == 'boundary' and (object.tags.admin_level == '5' or object.tags.admin_level == '6' ) then
        tables.geometry_districts:add_row({
            tags = object.tags,
            -- osm_type = osm_type,
            boundary = { create = 'area' }
        })
    end

    -- cities
    if (object.tags.type == 'multipolygon' or object.tags.type == 'boundary') and has_value(cities, object.tags.place)  then
        tables.geometry_cities:add_row({
            tags = object.tags,
            -- osm_type = osm_type,
            boundary = { create = 'area' }
        })
    end
    
end


if osm2pgsql.process_node == nil then
    osm2pgsql.process_node = geometry_process_node
end

if osm2pgsql.process_way == nil then
    osm2pgsql.process_way = geometry_process_way
end

if osm2pgsql.process_relation == nil then
    osm2pgsql.process_relation = geometry_process_relation
end
