DO $$
	DECLARE
		_country_relation_id BIGINT = 60189; -- relation_id РФ в OSM
		
		_temp_country RECORD;
		_country RECORD;
		_country_id app_geo__countries.id%TYPE;
		
		_temp_region RECORD;
		_region RECORD;
		_region_id app_geo__regions.id%TYPE;
	
		_temp_district RECORD;
		_district RECORD;
		_district_id app_geo__districts.id%TYPE;
		
		_temp_city RECORD;
		_city RECORD;
		_city_id app_geo__cities.id%TYPE;
		
		_temp_reg_city RECORD;
		
		_cities_count INT;
		_updated_cities_count INT;
		_region_cities_count INT;
		_country_cities_count INT;
		_updated_district_cities_count INT;

	BEGIN
		SELECT * INTO _temp_country 
		FROM geometry_countries WHERE relation_id=_country_relation_id;
		
		INSERT INTO app_geo__countries(boundary, tags) 
		VALUES (_temp_country.boundary, _temp_country.tags) RETURNING id INTO _country_id;
		
		SELECT * INTO _country FROM app_geo__countries WHERE id=_country_id;

		_country_cities_count = 0;
		_updated_cities_count = 0;
		
		-- Вставляем регионы --
		FOR _temp_region IN
			SELECT 
				boundary,
				tags||hstore('relation_id', relation_id::text) AS tags
			FROM geometry_regions 
			WHERE ST_COVERS(
				(SELECT boundary FROM geometry_countries WHERE relation_id=_country_relation_id), 
				boundary
			) 
			AND relation_id !=72639 -- украинский Крым отсекаем
			
			ORDER BY tags->'name'

		LOOP

            ---- вставляем регион
            INSERT INTO app_geo__regions(country_id, boundary, tags) 
            VALUES (_country.id, _temp_region.boundary, _temp_region.tags) RETURNING id INTO _region_id;
            SELECT * INTO _region FROM app_geo__regions WHERE id=_region_id;
            
            ------------------------------
            _region_cities_count = 0;
            
            ------------- Логирование --------------
            raise info 'РЕГИОН ID:% - %', _region_id, _region.tags->'name';
            ----------------------------------------
            
            -- Вставляем города региона, которые могут не относиться к районам (Москва, Питер, например, и крупные в регионе) --
            
            FOR _temp_reg_city IN
                SELECT
                    c.boundary,
                    p.center,
                    hs_concat(
                        COALESCE(c.tags, hstore(''))||
                        CASE 
                            WHEN c.type='R' THEN hstore('relation_id', c.id::text) 
                            ELSE hstore('way_id', c.id::text) 
                        END,
                        COALESCE(p.tags, hstore(''))||
                        CASE 
                            WHEN p IS NULL THEN hstore('')
                            ELSE hstore('node_id', p.id::text)
                        END
                    ) AS tags -- Для слияния hstore, если вдруг null
                FROM geometry_cities c
                LEFT JOIN geometry_cities_points p
                ON ST_COVERS(c.boundary, p.center)
                WHERE ST_COVERS( -- геометрия региона покрывает геометрию города
                    (SELECT boundary FROM geometry_regions WHERE relation_id=cast(_region.tags->'relation_id' as int)), 
                    boundary
                )
                AND c.tags->'place'='city' 
                AND (p IS NULL OR p.tags->'place'='city')
                ORDER BY c.tags->'name'
            
            LOOP
                INSERT INTO app_geo__cities (country_id, region_id, boundary, center, tags) 
                VALUES (_country.id, _region.id, _temp_reg_city.boundary, _temp_reg_city.center, _temp_reg_city.tags);
                
                _region_cities_count = _region_cities_count + 1;
                _country_cities_count = _country_cities_count + 1;
                
            END LOOP;

            -- вставляем районы --
            FOR _temp_district IN
                SELECT 
                    boundary,
                    tags||hstore('relation_id', relation_id::text) AS tags
                FROM geometry_districts
                WHERE ST_COVERS(
                    (SELECT boundary FROM geometry_regions where relation_id=cast(_region.tags->'relation_id' as int)), 
                    boundary
                )
                ORDER BY tags->'name'

            LOOP
                ---- вставляем район
                INSERT INTO app_geo__districts (country_id, region_id, boundary, tags) 
                VALUES (_country.id, _region.id, _temp_district.boundary, _temp_district.tags) RETURNING id INTO _district_id;
                
                SELECT * INTO _district FROM app_geo__districts WHERE id=_district_id;
                
                ----------------------------------------
                _cities_count = 0;
                _updated_district_cities_count = 0;
                ----------------------------------------
                -- вставляем населенные пункты --
                FOR _temp_city IN
                    SELECT * FROM (SELECT
                        c.boundary,
                        p.center,
                        hs_concat(
                            COALESCE(c.tags, hstore(''))||
                            CASE 
                                WHEN c.type='R' THEN hstore('relation_id', c.id::text) 
                                ELSE hstore('way_id', c.id::text) 
                            END, 
                            COALESCE(p.tags, hstore(''))||
                            CASE 
                                WHEN p IS NULL THEN hstore('')
                                ELSE hstore('node_id', p.id::text)
                            END
                        ) AS tags -- Для слияния hstore, если вдруг null
                    FROM geometry_cities c
                    LEFT JOIN geometry_cities_points p
                    ON ST_COVERS(c.boundary, p.center) -- Геометрия населённого пункта должна полностью перекрывать точку
                    WHERE 
                        ST_Intersects (
                            (
                                SELECT boundary 
                                FROM geometry_districts 
                                WHERE relation_id=cast(_district.tags->'relation_id' as int)
                            ),
                            boundary
                        )=TRUE 
                        AND ST_Area (
                            ST_Intersection (
                                (
                                    SELECT boundary 
                                    FROM geometry_districts 
                                    WHERE relation_id=cast(_district.tags->'relation_id' as int)
                                ),
                                boundary
                            )
                        )> 0.95*ST_AREA(boundary)
                    AND c.tags->'place'!='suburb' 
                    AND (p IS NULL OR p.tags->'place'!='suburb') -- пригороды тут не берём
                    AND (p IS NULL OR p.tags->'name'=c.tags->'name')
                    
                    UNION 

                    SELECT
                        cc.boundary,
                        pp.center,
                        COALESCE(pp.tags, hstore(''))||hstore('node_id', pp.id::text) AS tags -- Для слияния hstore, если вдруг null
                    FROM geometry_cities_points pp 
                    LEFT JOIN geometry_cities cc -- объединяем с территориями,
                    ON ST_COVERS(cc.boundary, pp.center) -- которые вмещают точки
                    WHERE
                        ST_COVERS( -- берем города, пересекающие геометрию района
                            (
                                SELECT boundary
                                FROM geometry_districts
                                WHERE relation_id=cast(_district.tags->'relation_id' as int)
                            ),
                            pp.center
                        )
                        AND pp.tags->'place'!='suburb' -- исключаем пригороды, для них отдельная таблица будет
                        AND cc.boundary is null

                    ) sub
                    ORDER BY tags->'name'

                LOOP
                
                    IF _temp_city.tags->'place'='city' 
                    AND EXISTS(
                        SELECT id
                        FROM app_geo__cities
                        WHERE 
                            tags->'relation_id'=_temp_city.tags->'relation_id'
                            OR tags->'way_id'=_temp_city.tags->'way_id' -- для случаев, где нет relation_id
                    )
                    THEN
                        UPDATE app_geo__cities c
                        SET district_id=_district_id 
                        WHERE tags->'relation_id'=_temp_city.tags->'relation_id';
                                
                        _updated_district_cities_count = _updated_district_cities_count + 1;
                        _updated_cities_count = _updated_cities_count + 1;
                                
                    ELSE
                        ---- вставляем населенный пункт
                        INSERT INTO app_geo__cities (country_id, region_id, district_id, boundary, center, tags) 
                        VALUES (_country.id, _region.id, _district.id, _temp_city.boundary, _temp_city.center, _temp_city.tags) 
                        RETURNING id INTO _city_id;
                                
                        -------------------------------------------------
                        _cities_count = _cities_count+1;
                        _country_cities_count = _country_cities_count+1;
                                
                    END IF;

                END LOOP;
                                
                ------------- Логирование --------------
                raise info '% | РАЙОН ID:% - %, добавлено % городов, обновлено % городов', 
                _region.tags->'name', 
                _district_id, 
                _district.tags->'name', 
                _cities_count, 
                _updated_district_cities_count;
                ----------------------------------------

            END LOOP;

        END LOOP;
        ------------- Логирование --------------
        raise info 'Всего добавлено % городов', _country_cities_count;
        raise info 'Обновлено % городов', _updated_cities_count;
        ----------------------------------------
END $$;