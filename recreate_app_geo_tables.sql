CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS hstore;

DROP TABLE IF EXISTS app_geo__cities CASCADE;
DROP SEQUENCE IF EXISTS  app_geo__cities_id_seq;
DROP TABLE IF EXISTS  app_geo__districts CASCADE;
DROP SEQUENCE IF EXISTS  app_geo__districts_id_seq;
DROP TABLE IF EXISTS  app_geo__regions CASCADE;
DROP SEQUENCE IF EXISTS  app_geo__regions_id_seq;
DROP TABLE IF EXISTS  app_geo__countries CASCADE;
DROP SEQUENCE IF EXISTS  app_geo__countries_id_seq;

CREATE SEQUENCE IF NOT EXISTS "public"."app_geo__countries_id_seq" 
INCREMENT 1
MINVALUE  1
MAXVALUE 2147483647
START 1
CACHE 1;

CREATE SEQUENCE IF NOT EXISTS "public"."app_geo__regions_id_seq" 
INCREMENT 1
MINVALUE  1
MAXVALUE 2147483647
START 1
CACHE 1;

CREATE SEQUENCE IF NOT EXISTS "public"."app_geo__districts_id_seq" 
INCREMENT 1
MINVALUE  1
MAXVALUE 2147483647
START 1
CACHE 1;

CREATE SEQUENCE IF NOT EXISTS "public"."app_geo__cities_id_seq" 
INCREMENT 1
MINVALUE  1
MAXVALUE 2147483647
START 1
CACHE 1;

CREATE TABLE "public"."app_geo__countries" (
  "id" int4 NOT NULL DEFAULT nextval('app_geo__countries_id_seq'::regclass),
  "tags" "public"."hstore",
  "boundary" "public"."geometry",
  CONSTRAINT "app_geo__countries_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "app_geo__countries_boundary_id" ON "public"."app_geo__countries" USING gist (
  "boundary" "public"."gist_geometry_ops_2d"
);


CREATE TABLE "public"."app_geo__regions" (
  "id" int4 NOT NULL DEFAULT nextval('app_geo__regions_id_seq'::regclass),
	"tags" "public"."hstore",
	"boundary" "public"."geometry",
	"country_id" int4,  
  CONSTRAINT "app_geo__regions_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "app_geo__regions_country_id_fk_app_geo__countries_id" FOREIGN KEY ("country_id") REFERENCES "public"."app_geo__countries" ("id") ON DELETE NO ACTION ON UPDATE NO ACTION DEFERRABLE INITIALLY DEFERRED
)
;

CREATE INDEX "app_geo__regions_boundary_id" ON "public"."app_geo__regions" USING gist (
  "boundary" "public"."gist_geometry_ops_2d"
);

CREATE INDEX "app_geo__regions_country_id" ON "public"."app_geo__regions" USING btree (
  "country_id" "pg_catalog"."int4_ops" ASC NULLS LAST
);


CREATE TABLE "public"."app_geo__districts" (
  "id" int4 NOT NULL DEFAULT nextval('app_geo__districts_id_seq'::regclass),
  "tags" "public"."hstore",
  "boundary" "public"."geometry",
  "country_id" int4,
  "region_id" int4,
  CONSTRAINT "app_geo__districts_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "app_geo__districts_country_id_fk_app_geo__countries_id" FOREIGN KEY ("country_id") REFERENCES "public"."app_geo__countries" ("id") ON DELETE NO ACTION ON UPDATE NO ACTION DEFERRABLE INITIALLY DEFERRED,
  CONSTRAINT "app_geo__districts_region_id_fk_app_geo__regions_id" FOREIGN KEY ("region_id") REFERENCES "public"."app_geo__regions" ("id") ON DELETE NO ACTION ON UPDATE NO ACTION DEFERRABLE INITIALLY DEFERRED
)
;

CREATE INDEX "app_geo__districts_boundary_id" ON "public"."app_geo__districts" USING gist (
  "boundary" "public"."gist_geometry_ops_2d"
);

CREATE INDEX "app_geo__districts_country_id" ON "public"."app_geo__districts" USING btree (
  "country_id" "pg_catalog"."int4_ops" ASC NULLS LAST
);

CREATE INDEX "app_geo__districts_region_id" ON "public"."app_geo__districts" USING btree (
  "region_id" "pg_catalog"."int4_ops" ASC NULLS LAST
);


CREATE TABLE "public"."app_geo__cities" (
  "id" int4 NOT NULL DEFAULT nextval('app_geo__cities_id_seq'::regclass),
  "tags" "public"."hstore",
  "boundary" "public"."geometry",
  "center" "public"."geometry",
  "country_id" int4,
  "district_id" int4,
  "region_id" int4,
  CONSTRAINT "app_geo__cities_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "app_geo__cities_country_id_fk_app_geo__countries_id" FOREIGN KEY ("country_id") REFERENCES "public"."app_geo__countries" ("id") ON DELETE NO ACTION ON UPDATE NO ACTION DEFERRABLE INITIALLY DEFERRED,
  CONSTRAINT "app_geo__cities_district_id_fk_app_geo__districts_id" FOREIGN KEY ("district_id") REFERENCES "public"."app_geo__districts" ("id") ON DELETE NO ACTION ON UPDATE NO ACTION DEFERRABLE INITIALLY DEFERRED,
  CONSTRAINT "app_geo__cities_region_id_fk_app_geo__regions_id" FOREIGN KEY ("region_id") REFERENCES "public"."app_geo__regions" ("id") ON DELETE NO ACTION ON UPDATE NO ACTION DEFERRABLE INITIALLY DEFERRED
)
;

ALTER TABLE "public"."app_geo__cities" 
  OWNER TO "postgres";

CREATE INDEX "app_geo__cities_boundary_id" ON "public"."app_geo__cities" USING gist (
  "boundary" "public"."gist_geometry_ops_2d"
);

CREATE INDEX "app_geo__cities_country_id" ON "public"."app_geo__cities" USING btree (
  "country_id" "pg_catalog"."int4_ops" ASC NULLS LAST
);

CREATE INDEX "app_geo__cities_district_id" ON "public"."app_geo__cities" USING btree (
  "district_id" "pg_catalog"."int4_ops" ASC NULLS LAST
);

CREATE INDEX "app_geo__cities_center_id" ON "public"."app_geo__cities" USING gist (
  "center" "public"."gist_geometry_ops_2d"
);

CREATE INDEX "app_geo__cities_region_id" ON "public"."app_geo__cities" USING btree (
  "region_id" "pg_catalog"."int4_ops" ASC NULLS LAST
);