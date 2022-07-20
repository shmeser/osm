DO $$
	DECLARE
		_temp_country RECORD;
		_temp_region RECORD;
		_temp_district RECORD;
		_temp_city RECORD;

		_temp_reg_city RECORD;

		_region_id app_geo__regions.id%TYPE;
		_reg_city_id app_geo__cities.id%TYPE;
		_district_id app_geo__districts.id%TYPE;
		_city_id app_geo__cities.id%TYPE;


	BEGIN
	
		FOR _temp_region IN
			SELECT
				native, names, osm, boundary, timezone, population
			FROM dblink('host=localhost port=5433 user=postgres password=postgres dbname=testosm',
				'SELECT 
                    tags->''name'' as native,
                    slice(tags, ARRAY[''name:ru'',''name:en'', ''name:de'', ''name:fr'', ''name:it'', ''name:es'']) as names, 
                    slice(tags, ARRAY[''flag'', ''population'',''wikidata'',''place'', ''timezone'', ''postal_code'', ''relation_id'']) as osm,
                    boundary, 
                    tags->''timezone'' as timezone,
                    CASE 
                        WHEN (tags->''population'')~E''^\\d+$'' 
                        THEN (tags->''population'')::integer 
                        ELSE 0 
                    END AS population
				FROM app_geo__regions
				WHERE country_id = (
					SELECT id 
					FROM app_geo__countries
					WHERE id=1
					LIMIT 1
				)'			
			) AS x(native TEXT, names HSTORE, osm HSTORE, boundary GEOMETRY, timezone TEXT, population INTEGER)
			
		LOOP -- регион
			---- вставляем регион
			IF EXISTS( -- регион
				SELECT * 
				FROM app_geo__regions 
				WHERE osm->'relation_id'=_temp_region.osm->'relation_id'
			) 
			THEN
				-- update
				UPDATE app_geo__regions
				SET 
					updated_at=now(),
					native=_temp_region.native, 
					names=_temp_region.names, 
					osm=_temp_region.osm, 
					boundary=_temp_region.boundary,
					country_id=1
				WHERE osm->'relation_id'=_temp_region.osm->'relation_id'
				RETURNING id INTO _region_id;
				------------- Логирование --------------
				raise info 'Регион обновлён: %', _temp_region.native;
				----------------------------------------

			ELSE
				-- insert
				INSERT INTO app_geo__regions (created_at, updated_at, deleted, native, names, osm, boundary, country_id) 
				VALUES (
					now(), 
					now(), 
					FALSE, 		
					_temp_region.native, 
					_temp_region.names,  
					_temp_region.osm, 
					_temp_region.boundary,
					1
				) 
				RETURNING id INTO _region_id;
				------------- Логирование --------------
				raise info 'Регион добавлен: %', _temp_region.native;
				----------------------------------------
				
			END IF; -- регион
	
	
			FOR _temp_reg_city IN
				SELECT
					native, names, osm, boundary, center, timezone, population
				FROM dblink('host=localhost port=5433 user=postgres password=postgres dbname=testosm',
					format('
                        SELECT 
                            tags->''name'' as native,
                            slice(tags, ARRAY[''name:ru'',''name:en'', ''name:de'', ''name:fr'', ''name:it'', ''name:es'']) as names, 
                            slice(tags, ARRAY[''flag'', ''population'',''wikidata'',''place'', ''timezone'', ''postal_code'', ''relation_id'']) as osm,
                            boundary, 
                            center,
                            tags->''timezone'' as timezone,
                            CASE 
								WHEN (tags->''population'')~E''^\\d+$'' 
								THEN (tags->''population'')::integer 
								ELSE 0 
							END AS population
                        FROM app_geo__cities
                        WHERE region_id = (
                        	SELECT id 
                        	FROM app_geo__regions
                        	WHERE tags->''relation_id'' = ''%1$s''
                        	LIMIT 1
                        )
                        AND district_id IS NULL
                        ', _temp_region.osm->'relation_id'
					)		
				) AS x(
					native TEXT, 
					names HSTORE, 
					osm HSTORE, 
					boundary GEOMETRY, 
					center GEOMETRY, 
					timezone TEXT, 
					population INTEGER
				)
				
			LOOP -- региональный город
				---- вставляем региональный город, не относящийся к районам
				IF EXISTS(
					SELECT * 
					FROM app_geo__cities
					WHERE osm->'relation_id'=_temp_reg_city.osm->'relation_id'
					AND district_id IS NULL
				) 
				THEN
					
					UPDATE app_geo__cities
					SET 
                        updated_at=now(),
                        native=_temp_reg_city.native, 
                        names=_temp_reg_city.names, 
                        osm=_temp_reg_city.osm, 
                        boundary=_temp_reg_city.boundary,
                        position=_temp_reg_city.center,
                        region_id=_region_id,
                        country_id=1
					WHERE osm->'relation_id'=_temp_reg_city.osm->'relation_id'
					RETURNING id INTO _reg_city_id;
					------------- Логирование --------------
					raise info 'Региональный город обновлён: %', _temp_reg_city.native;
					----------------------------------------

				ELSE
					
					INSERT INTO app_geo__cities (created_at, updated_at, deleted, native, names, osm, boundary, position, country_id, region_id) 
					VALUES (
                        now(), 
                        now(), 
                        FALSE, 		
                        _temp_reg_city.native, 
                        _temp_reg_city.names,  
                        _temp_reg_city.osm, 
                        _temp_reg_city.boundary,
                        _temp_reg_city.center,
                        1,
                        _region_id
					) 
					RETURNING id INTO _reg_city_id;
					------------- Логирование --------------
					raise info 'Региональный город добавлен: %', _temp_reg_city.native;
					----------------------------------------
					 
				END IF;  -- региональный город
				
			END LOOP; -- региональный город
			
			FOR _temp_district IN
				SELECT
					native, names, osm, boundary, timezone, population
				FROM dblink('host=localhost port=5433 user=postgres password=postgres dbname=testosm',
					format('
                        SELECT 
                            tags->''name'' as native,
                            slice(tags, ARRAY[''name:ru'',''name:en'', ''name:de'', ''name:fr'', ''name:it'', ''name:es'']) as names, 
                            slice(tags, ARRAY[''flag'', ''population'',''wikidata'',''place'', ''timezone'', ''postal_code'', ''relation_id'']) as osm,
                            boundary,
                            tags->''timezone'' as timezone,
                            CASE 
								WHEN (tags->''population'')~E''^\\d+$'' 
								THEN (tags->''population'')::integer 
								ELSE 0 
							END AS population
                        FROM app_geo__districts
                        WHERE region_id = (
                        	SELECT id 
                        	FROM app_geo__regions
                        	WHERE tags->''relation_id'' = ''%1$s''
                        	LIMIT 1
                        )
                        ', _temp_region.osm->'relation_id'
					)		
				) AS x(
					native TEXT, 
					names HSTORE, 
					osm HSTORE, 
					boundary GEOMETRY, 
					timezone TEXT, 
					population INTEGER
				)
				
			LOOP -- район
				IF EXISTS( -- район
					SELECT * 
					FROM app_geo__districts
					WHERE osm->'relation_id'=_temp_district.osm->'relation_id'
				) 
				THEN
					
					UPDATE app_geo__districts
					SET 
                        updated_at=now(),
                        native=_temp_district.native, 
                        names=_temp_district.names, 
                        osm=_temp_district.osm, 
                        boundary=_temp_district.boundary,
                        region_id=_region_id,
                        country_id=1
					WHERE osm->'relation_id'=_temp_district.osm->'relation_id'
					RETURNING id INTO _district_id;
					------------- Логирование --------------
					raise info 'Район обновлён: %', _temp_district.native;
					----------------------------------------

				ELSE
					
					INSERT INTO app_geo__districts (created_at, updated_at, deleted, native, names, osm, boundary, country_id, region_id) 
					VALUES (
                        now(),
                        now(),
                        FALSE,
                        _temp_district.native,
                        _temp_district.names,
                        _temp_district.osm,
                        _temp_district.boundary,
                        1,
                        _region_id
					)
					RETURNING id INTO _district_id;
					------------- Логирование --------------
					raise info 'Район добавлен: %', _temp_district.native;
					----------------------------------------
					 
				END IF; -- район
				
				FOR _temp_city IN
					SELECT
                        native, names, osm, boundary, center, timezone, population
					FROM dblink('host=localhost port=5433 user=postgres password=postgres dbname=testosm',
                        format('
                        	SELECT 
                                tags->''name'' as native,
                                slice(tags, ARRAY[''name:ru'',''name:en'', ''name:de'', ''name:fr'', ''name:it'', ''name:es'']) as names, 
                                slice(tags, ARRAY[''flag'', ''population'',''wikidata'',''place'', ''timezone'', ''postal_code'', ''relation_id'']) as osm,
                                boundary, 
                                center,
                                tags->''timezone'' as timezone,
                                CASE 
									WHEN (tags->''population'')~E''^\\d+$'' 
									THEN (tags->''population'')::integer 
									ELSE 0 
								END AS population
                        	FROM app_geo__cities
                        	WHERE district_id = (
                        		SELECT id 
                        		FROM app_geo__districts
                        		WHERE tags->''relation_id'' = ''%1$s''
                        		LIMIT 1
                        	)
                        	', _temp_district.osm->'relation_id'
                        )		
					) AS x(
                        native TEXT, 
                        names HSTORE, 
                        osm HSTORE, 
                        boundary GEOMETRY, 
                        center GEOMETRY, 
                        timezone TEXT, 
                        population INTEGER
					)
					
				LOOP -- город
					---- вставляем город
					IF EXISTS(
                        SELECT * 
                        FROM app_geo__cities
                        WHERE 
                        	osm->'relation_id'=_temp_city.osm->'relation_id' 
                        	OR osm->'way_id'=_temp_city.osm->'way_id' 
                        	OR osm->'node_id'=_temp_city.osm->'node_id'
					) 
					THEN
                        
                        UPDATE app_geo__cities
                        SET 
                        	updated_at=now(),
                        	native=_temp_city.native, 
                        	names=_temp_city.names, 
                        	osm=_temp_city.osm, 
                        	boundary=_temp_city.boundary,
                        	position=_temp_city.center,
                        	region_id=_region_id,
                        	district_id=_district_id,
                        	country_id=1
                        WHERE 
                        	osm->'relation_id'=_temp_city.osm->'relation_id' 
                        	OR osm->'way_id'=_temp_city.osm->'way_id' 
                        	OR osm->'node_id'=_temp_city.osm->'node_id'
                        RETURNING id INTO _city_id;
                        ------------- Логирование --------------
                        raise info 'Город обновлён: %', _temp_city.native;
                        ----------------------------------------

					ELSE
                        
                        INSERT INTO app_geo__cities (
                        	created_at, 
                        	updated_at, 
                        	deleted, 
                        	native, 
                        	names, 
                        	osm, 
                        	boundary, 
                        	position, 
                        	country_id, 
                        	region_id, 
                        	district_id
                        ) 
                        VALUES (
                        	now(), 
                        	now(), 
                        	FALSE,
                        	_temp_city.native, 
                        	_temp_city.names,  
                        	_temp_city.osm, 
                        	_temp_city.boundary,
                        	_temp_city.center,
                        	1,
                        	_region_id,
                        	_district_id
                        ) 
                        RETURNING id INTO _city_id;
                        ------------- Логирование --------------
                        raise info 'Город добавлен: %', _temp_city.native;
                        ----------------------------------------

                END IF;  -- город

                END LOOP; -- город

            END LOOP; -- район

        END LOOP; -- регион

END $$;