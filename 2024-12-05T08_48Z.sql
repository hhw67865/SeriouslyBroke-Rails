--
-- PostgreSQL database cluster dump
--

SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

--
-- Drop databases (except postgres and template1)
--




--
--


--
--

--
-- Database "moneyhugs_development" dump
--

--
-- PostgreSQL database dump
--

-- Dumped from database version 16.4 (Debian 16.4-1.pgdg120+2)
-- Dumped by pg_dump version 16.4 (Debian 16.4-1.pgdg120+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: moneyhugs_development; Type: DATABASE; Schema: -; Owner: -
--



SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: moneyhugs_development; Type: DATABASE PROPERTIES; Schema: -; Owner: -
--

ALTER DATABASE "moneyhugs_development" SET "TimeZone" TO 'utc';


\connect "moneyhugs_development"

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- *not* creating schema, since initdb creates it


--
-- Name: SCHEMA "public"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA "public" IS 'standard public schema';


--
-- Name: bloom; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "bloom" WITH SCHEMA "public";


--
-- Name: EXTENSION "bloom"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "bloom" IS 'bloom access method - signature file based index';


--
-- Name: btree_gin; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "btree_gin" WITH SCHEMA "public";


--
-- Name: EXTENSION "btree_gin"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "btree_gin" IS 'support for indexing common datatypes in GIN';


--
-- Name: btree_gist; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "btree_gist" WITH SCHEMA "public";


--
-- Name: EXTENSION "btree_gist"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "btree_gist" IS 'support for indexing common datatypes in GiST';


--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "citext" WITH SCHEMA "public";


--
-- Name: EXTENSION "citext"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "citext" IS 'data type for case-insensitive character strings';


--
-- Name: cube; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "cube" WITH SCHEMA "public";


--
-- Name: EXTENSION "cube"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "cube" IS 'data type for multidimensional cubes';


--
-- Name: dblink; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "dblink" WITH SCHEMA "public";


--
-- Name: EXTENSION "dblink"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "dblink" IS 'connect to other PostgreSQL databases from within a database';


--
-- Name: dict_int; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "dict_int" WITH SCHEMA "public";


--
-- Name: EXTENSION "dict_int"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "dict_int" IS 'text search dictionary template for integers';


--
-- Name: dict_xsyn; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "dict_xsyn" WITH SCHEMA "public";


--
-- Name: EXTENSION "dict_xsyn"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "dict_xsyn" IS 'text search dictionary template for extended synonym processing';


--
-- Name: earthdistance; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "earthdistance" WITH SCHEMA "public";


--
-- Name: EXTENSION "earthdistance"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "earthdistance" IS 'calculate great-circle distances on the surface of the Earth';


--
-- Name: fuzzystrmatch; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "fuzzystrmatch" WITH SCHEMA "public";


--
-- Name: EXTENSION "fuzzystrmatch"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "fuzzystrmatch" IS 'determine similarities and distance between strings';


--
-- Name: hstore; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "hstore" WITH SCHEMA "public";


--
-- Name: EXTENSION "hstore"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "hstore" IS 'data type for storing sets of (key, value) pairs';


--
-- Name: intagg; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "intagg" WITH SCHEMA "public";


--
-- Name: EXTENSION "intagg"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "intagg" IS 'integer aggregator and enumerator (obsolete)';


--
-- Name: intarray; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "intarray" WITH SCHEMA "public";


--
-- Name: EXTENSION "intarray"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "intarray" IS 'functions, operators, and index support for 1-D arrays of integers';


--
-- Name: isn; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "isn" WITH SCHEMA "public";


--
-- Name: EXTENSION "isn"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "isn" IS 'data types for international product numbering standards';


--
-- Name: lo; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "lo" WITH SCHEMA "public";


--
-- Name: EXTENSION "lo"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "lo" IS 'Large Object maintenance';


--
-- Name: ltree; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "ltree" WITH SCHEMA "public";


--
-- Name: EXTENSION "ltree"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "ltree" IS 'data type for hierarchical tree-like structures';


--
-- Name: pg_buffercache; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "pg_buffercache" WITH SCHEMA "public";


--
-- Name: EXTENSION "pg_buffercache"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "pg_buffercache" IS 'examine the shared buffer cache';


--
-- Name: pg_prewarm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "pg_prewarm" WITH SCHEMA "public";


--
-- Name: EXTENSION "pg_prewarm"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "pg_prewarm" IS 'prewarm relation data';


--
-- Name: pg_similarity; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "pg_similarity" WITH SCHEMA "public";


--
-- Name: EXTENSION "pg_similarity"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "pg_similarity" IS 'support similarity queries';


--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "public";


--
-- Name: EXTENSION "pg_stat_statements"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "pg_stat_statements" IS 'track execution statistics of all SQL statements executed';


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "pg_trgm" WITH SCHEMA "public";


--
-- Name: EXTENSION "pg_trgm"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "pg_trgm" IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "public";


--
-- Name: EXTENSION "pgcrypto"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "pgcrypto" IS 'cryptographic functions';


--
-- Name: pgrowlocks; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "pgrowlocks" WITH SCHEMA "public";


--
-- Name: EXTENSION "pgrowlocks"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "pgrowlocks" IS 'show row-level locking information';


--
-- Name: pgstattuple; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "pgstattuple" WITH SCHEMA "public";


--
-- Name: EXTENSION "pgstattuple"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "pgstattuple" IS 'show tuple-level statistics';


--
-- Name: tablefunc; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "tablefunc" WITH SCHEMA "public";


--
-- Name: EXTENSION "tablefunc"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "tablefunc" IS 'functions that manipulate whole tables, including crosstab';


--
-- Name: unaccent; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "unaccent" WITH SCHEMA "public";


--
-- Name: EXTENSION "unaccent"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "unaccent" IS 'text search dictionary that removes accents';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "public";


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- PostgreSQL database dump complete
--

--
-- Database "moneyhugs" dump
--

--
-- PostgreSQL database dump
--

-- Dumped from database version 16.4 (Debian 16.4-1.pgdg120+2)
-- Dumped by pg_dump version 16.4 (Debian 16.4-1.pgdg120+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: moneyhugs; Type: DATABASE; Schema: -; Owner: -
--

CREATE DATABASE "moneyhugs_development" WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE_PROVIDER = libc LOCALE = 'en_US.UTF8';


\connect "moneyhugs_development"

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- *not* creating schema, since initdb creates it


--
-- Name: SCHEMA "public"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA "public" IS 'standard public schema';


SET default_tablespace = '';

SET default_table_access_method = "heap";

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE "public"."ar_internal_metadata" (
    "key" character varying NOT NULL,
    "value" character varying,
    "created_at" timestamp(6) without time zone NOT NULL,
    "updated_at" timestamp(6) without time zone NOT NULL
);


--
-- Name: asset_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE "public"."asset_transactions" (
    "id" bigint NOT NULL,
    "date" "date",
    "amount" "money",
    "description" "text",
    "asset_id" bigint NOT NULL,
    "created_at" timestamp(6) without time zone NOT NULL,
    "updated_at" timestamp(6) without time zone NOT NULL
);


--
-- Name: asset_transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE "public"."asset_transactions_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: asset_transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE "public"."asset_transactions_id_seq" OWNED BY "public"."asset_transactions"."id";


--
-- Name: asset_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE "public"."asset_types" (
    "id" bigint NOT NULL,
    "name" character varying,
    "user_id" bigint NOT NULL,
    "created_at" timestamp(6) without time zone NOT NULL,
    "updated_at" timestamp(6) without time zone NOT NULL
);


--
-- Name: asset_types_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE "public"."asset_types_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: asset_types_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE "public"."asset_types_id_seq" OWNED BY "public"."asset_types"."id";


--
-- Name: assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE "public"."assets" (
    "id" bigint NOT NULL,
    "name" character varying,
    "asset_type_id" bigint NOT NULL,
    "created_at" timestamp(6) without time zone NOT NULL,
    "updated_at" timestamp(6) without time zone NOT NULL
);


--
-- Name: assets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE "public"."assets_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: assets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE "public"."assets_id_seq" OWNED BY "public"."assets"."id";


--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE "public"."categories" (
    "id" bigint NOT NULL,
    "name" character varying,
    "minimum_amount" "money",
    "color" character varying,
    "user_id" bigint NOT NULL,
    "created_at" timestamp(6) without time zone NOT NULL,
    "updated_at" timestamp(6) without time zone NOT NULL
);


--
-- Name: categories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE "public"."categories_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE "public"."categories_id_seq" OWNED BY "public"."categories"."id";


--
-- Name: expenses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE "public"."expenses" (
    "id" bigint NOT NULL,
    "name" character varying,
    "amount" "money",
    "date" "date",
    "category_id" bigint NOT NULL,
    "created_at" timestamp(6) without time zone NOT NULL,
    "updated_at" timestamp(6) without time zone NOT NULL
);


--
-- Name: expenses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE "public"."expenses_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: expenses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE "public"."expenses_id_seq" OWNED BY "public"."expenses"."id";


--
-- Name: income_sources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE "public"."income_sources" (
    "id" bigint NOT NULL,
    "name" character varying,
    "user_id" bigint NOT NULL,
    "created_at" timestamp(6) without time zone NOT NULL,
    "updated_at" timestamp(6) without time zone NOT NULL
);


--
-- Name: income_sources_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE "public"."income_sources_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: income_sources_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE "public"."income_sources_id_seq" OWNED BY "public"."income_sources"."id";


--
-- Name: paychecks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE "public"."paychecks" (
    "id" bigint NOT NULL,
    "date" "date",
    "amount" "money",
    "income_source_id" bigint NOT NULL,
    "created_at" timestamp(6) without time zone NOT NULL,
    "updated_at" timestamp(6) without time zone NOT NULL,
    "description" character varying
);


--
-- Name: paychecks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE "public"."paychecks_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: paychecks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE "public"."paychecks_id_seq" OWNED BY "public"."paychecks"."id";


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE "public"."schema_migrations" (
    "version" character varying NOT NULL
);


--
-- Name: tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE "public"."tasks" (
    "id" bigint NOT NULL,
    "description" "text",
    "completed" boolean,
    "upgrade_id" bigint NOT NULL,
    "created_at" timestamp(6) without time zone NOT NULL,
    "updated_at" timestamp(6) without time zone NOT NULL
);


--
-- Name: tasks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE "public"."tasks_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tasks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE "public"."tasks_id_seq" OWNED BY "public"."tasks"."id";


--
-- Name: upgrades; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE "public"."upgrades" (
    "id" bigint NOT NULL,
    "potential_income" "money",
    "minimum_downpayment" "money",
    "income_source_id" bigint NOT NULL,
    "created_at" timestamp(6) without time zone NOT NULL,
    "updated_at" timestamp(6) without time zone NOT NULL
);


--
-- Name: upgrades_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE "public"."upgrades_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: upgrades_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE "public"."upgrades_id_seq" OWNED BY "public"."upgrades"."id";


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE "public"."users" (
    "id" bigint NOT NULL,
    "clerk_user_id" character varying,
    "created_at" timestamp(6) without time zone NOT NULL,
    "updated_at" timestamp(6) without time zone NOT NULL
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE "public"."users_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE "public"."users_id_seq" OWNED BY "public"."users"."id";


--
-- Name: asset_transactions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."asset_transactions" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."asset_transactions_id_seq"'::"regclass");


--
-- Name: asset_types id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."asset_types" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."asset_types_id_seq"'::"regclass");


--
-- Name: assets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."assets" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."assets_id_seq"'::"regclass");


--
-- Name: categories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."categories" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."categories_id_seq"'::"regclass");


--
-- Name: expenses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."expenses" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."expenses_id_seq"'::"regclass");


--
-- Name: income_sources id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."income_sources" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."income_sources_id_seq"'::"regclass");


--
-- Name: paychecks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."paychecks" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."paychecks_id_seq"'::"regclass");


--
-- Name: tasks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."tasks" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."tasks_id_seq"'::"regclass");


--
-- Name: upgrades id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."upgrades" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."upgrades_id_seq"'::"regclass");


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."users" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."users_id_seq"'::"regclass");


--
-- Data for Name: ar_internal_metadata; Type: TABLE DATA; Schema: public; Owner: -
--

COPY "public"."ar_internal_metadata" ("key", "value", "created_at", "updated_at") FROM stdin;
environment	production	2024-01-02 14:11:18.245126	2024-01-02 14:11:18.245129
\.


--
-- Data for Name: asset_transactions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY "public"."asset_transactions" ("id", "date", "amount", "description", "asset_id", "created_at", "updated_at") FROM stdin;
1	2024-01-02	$20,934.42	\N	1	2024-01-02 19:01:38.321314	2024-01-02 19:01:38.321314
3	2024-01-19	$2,416.57	\N	3	2024-01-20 07:52:42.401152	2024-01-20 07:52:42.401152
4	2024-01-19	$1,425.62	\N	4	2024-01-20 07:53:06.144423	2024-01-20 07:53:06.144423
5	2024-01-19	$1,000.01	\N	5	2024-01-20 07:54:20.495448	2024-01-20 07:54:20.495448
6	2024-01-19	$15,045.31	\N	6	2024-01-20 07:56:07.674496	2024-01-20 07:56:07.674496
7	2024-01-19	$2,839.03	\N	8	2024-01-20 07:58:27.647078	2024-01-20 07:58:27.647078
8	2024-01-19	$1,400.00	\N	9	2024-01-20 07:58:36.962127	2024-01-20 07:58:36.962127
9	2024-01-19	$8,900.00	\N	10	2024-01-20 07:58:46.669057	2024-01-20 07:58:46.669057
\.


--
-- Data for Name: asset_types; Type: TABLE DATA; Schema: public; Owner: -
--

COPY "public"."asset_types" ("id", "name", "user_id", "created_at", "updated_at") FROM stdin;
1	Cash	1	2024-01-02 15:21:24.819524	2024-01-02 15:21:24.819524
2	Checking	1	2024-01-02 15:21:24.819524	2024-01-02 15:21:24.819524
3	Savings	1	2024-01-02 15:21:24.819524	2024-01-02 15:21:24.819524
4	Investments	1	2024-01-02 15:21:24.819524	2024-01-02 15:21:24.819524
5	Real Estate	1	2024-01-02 15:21:24.819524	2024-01-02 15:21:24.819524
6	Cash	2	2024-01-02 19:09:56.319316	2024-01-02 19:09:56.319316
7	Checking	2	2024-01-02 19:09:56.319316	2024-01-02 19:09:56.319316
8	Savings	2	2024-01-02 19:09:56.319316	2024-01-02 19:09:56.319316
9	Investments	2	2024-01-02 19:09:56.319316	2024-01-02 19:09:56.319316
10	Real Estate	2	2024-01-02 19:09:56.319316	2024-01-02 19:09:56.319316
11	Cash	3	2024-01-02 19:14:09.338422	2024-01-02 19:14:09.338422
12	Checking	3	2024-01-02 19:14:09.338422	2024-01-02 19:14:09.338422
13	Savings	3	2024-01-02 19:14:09.338422	2024-01-02 19:14:09.338422
14	Investments	3	2024-01-02 19:14:09.338422	2024-01-02 19:14:09.338422
15	Real Estate	3	2024-01-02 19:14:09.338422	2024-01-02 19:14:09.338422
16	Cash	4	2024-01-02 20:04:04.528728	2024-01-02 20:04:04.528728
17	Checking	4	2024-01-02 20:04:04.528728	2024-01-02 20:04:04.528728
18	Savings	4	2024-01-02 20:04:04.528728	2024-01-02 20:04:04.528728
19	Investments	4	2024-01-02 20:04:04.528728	2024-01-02 20:04:04.528728
20	Real Estate	4	2024-01-02 20:04:04.528728	2024-01-02 20:04:04.528728
21	Cash	5	2024-01-02 20:07:31.324875	2024-01-02 20:07:31.324875
22	Checking	5	2024-01-02 20:07:31.324875	2024-01-02 20:07:31.324875
23	Savings	5	2024-01-02 20:07:31.324875	2024-01-02 20:07:31.324875
24	Investments	5	2024-01-02 20:07:31.324875	2024-01-02 20:07:31.324875
25	Real Estate	5	2024-01-02 20:07:31.324875	2024-01-02 20:07:31.324875
26	Cash	6	2024-01-02 23:57:19.296947	2024-01-02 23:57:19.296947
27	Checking	6	2024-01-02 23:57:19.296947	2024-01-02 23:57:19.296947
28	Savings	6	2024-01-02 23:57:19.296947	2024-01-02 23:57:19.296947
29	Investments	6	2024-01-02 23:57:19.296947	2024-01-02 23:57:19.296947
30	Real Estate	6	2024-01-02 23:57:19.296947	2024-01-02 23:57:19.296947
31	Cash	7	2024-01-03 03:26:49.090645	2024-01-03 03:26:49.090645
32	Checking	7	2024-01-03 03:26:49.090645	2024-01-03 03:26:49.090645
33	Savings	7	2024-01-03 03:26:49.090645	2024-01-03 03:26:49.090645
34	Investments	7	2024-01-03 03:26:49.090645	2024-01-03 03:26:49.090645
35	Real Estate	7	2024-01-03 03:26:49.090645	2024-01-03 03:26:49.090645
36	Emergency Fund	6	2024-01-20 07:53:48.593677	2024-01-20 07:53:48.593677
\.


--
-- Data for Name: assets; Type: TABLE DATA; Schema: public; Owner: -
--

COPY "public"."assets" ("id", "name", "asset_type_id", "created_at", "updated_at") FROM stdin;
1	Account 0917	1	2024-01-02 19:01:17.952182	2024-01-02 19:01:17.952182
2	BOA Account 2482	26	2024-01-20 07:51:08.088171	2024-01-20 07:51:08.088171
3	BOA Account 2482	27	2024-01-20 07:52:32.628584	2024-01-20 07:52:32.628584
4	BOA Account 7642	27	2024-01-20 07:52:54.746231	2024-01-20 07:52:54.746231
5	BOA Account 7634	36	2024-01-20 07:54:04.45211	2024-01-20 07:54:04.45211
6	Discover Account 5243	28	2024-01-20 07:55:58.937209	2024-01-20 07:55:58.937209
7	2481 Scarlet Maple Aly	30	2024-01-20 07:56:22.972348	2024-01-20 07:56:22.972348
8	Ming's Robinhood	29	2024-01-20 07:57:40.65312	2024-01-20 07:57:40.65312
9	Henry's IRA	29	2024-01-20 07:57:51.237822	2024-01-20 07:57:51.237822
10	Ming's Merrill	29	2024-01-20 07:58:13.242695	2024-01-20 07:58:13.242695
\.


--
-- Data for Name: categories; Type: TABLE DATA; Schema: public; Owner: -
--

COPY "public"."categories" ("id", "name", "minimum_amount", "color", "user_id", "created_at", "updated_at") FROM stdin;
2	Transportation	\N	\N	1	2024-01-02 15:21:24.819524	2024-01-02 15:21:24.819524
3	Food	\N	\N	1	2024-01-02 15:21:24.819524	2024-01-02 15:21:24.819524
4	Utilities	\N	\N	1	2024-01-02 15:21:24.819524	2024-01-02 15:21:24.819524
5	Medical & Healthcare	\N	\N	1	2024-01-02 15:21:24.819524	2024-01-02 15:21:24.819524
6	Fitness	\N	\N	1	2024-01-02 15:21:24.819524	2024-01-02 15:21:24.819524
7	Debt Payments	\N	\N	1	2024-01-02 15:21:24.819524	2024-01-02 15:21:24.819524
8	Personal Care	\N	\N	1	2024-01-02 15:21:24.819524	2024-01-02 15:21:24.819524
9	Entertainment	\N	\N	1	2024-01-02 15:21:24.819524	2024-01-02 15:21:24.819524
10	Pets	\N	\N	1	2024-01-02 15:21:24.819524	2024-01-02 15:21:24.819524
11	Clothes	\N	\N	1	2024-01-02 15:21:24.819524	2024-01-02 15:21:24.819524
12	Miscellaneous	\N	\N	1	2024-01-02 15:21:24.819524	2024-01-02 15:21:24.819524
1	Housing	$0.00	#e69640	1	2024-01-02 15:21:24.819524	2024-01-02 17:04:27.067176
13	Housing	\N	\N	2	2024-01-02 19:09:56.319316	2024-01-02 19:09:56.319316
14	Transportation	\N	\N	2	2024-01-02 19:09:56.319316	2024-01-02 19:09:56.319316
15	Food	\N	\N	2	2024-01-02 19:09:56.319316	2024-01-02 19:09:56.319316
16	Utilities	\N	\N	2	2024-01-02 19:09:56.319316	2024-01-02 19:09:56.319316
17	Medical & Healthcare	\N	\N	2	2024-01-02 19:09:56.319316	2024-01-02 19:09:56.319316
18	Fitness	\N	\N	2	2024-01-02 19:09:56.319316	2024-01-02 19:09:56.319316
19	Debt Payments	\N	\N	2	2024-01-02 19:09:56.319316	2024-01-02 19:09:56.319316
20	Personal Care	\N	\N	2	2024-01-02 19:09:56.319316	2024-01-02 19:09:56.319316
21	Entertainment	\N	\N	2	2024-01-02 19:09:56.319316	2024-01-02 19:09:56.319316
22	Pets	\N	\N	2	2024-01-02 19:09:56.319316	2024-01-02 19:09:56.319316
23	Clothes	\N	\N	2	2024-01-02 19:09:56.319316	2024-01-02 19:09:56.319316
24	Miscellaneous	\N	\N	2	2024-01-02 19:09:56.319316	2024-01-02 19:09:56.319316
25	Housing	\N	\N	3	2024-01-02 19:14:09.338422	2024-01-02 19:14:09.338422
26	Transportation	\N	\N	3	2024-01-02 19:14:09.338422	2024-01-02 19:14:09.338422
27	Food	\N	\N	3	2024-01-02 19:14:09.338422	2024-01-02 19:14:09.338422
28	Utilities	\N	\N	3	2024-01-02 19:14:09.338422	2024-01-02 19:14:09.338422
29	Medical & Healthcare	\N	\N	3	2024-01-02 19:14:09.338422	2024-01-02 19:14:09.338422
30	Fitness	\N	\N	3	2024-01-02 19:14:09.338422	2024-01-02 19:14:09.338422
31	Debt Payments	\N	\N	3	2024-01-02 19:14:09.338422	2024-01-02 19:14:09.338422
32	Personal Care	\N	\N	3	2024-01-02 19:14:09.338422	2024-01-02 19:14:09.338422
33	Entertainment	\N	\N	3	2024-01-02 19:14:09.338422	2024-01-02 19:14:09.338422
34	Pets	\N	\N	3	2024-01-02 19:14:09.338422	2024-01-02 19:14:09.338422
35	Clothes	\N	\N	3	2024-01-02 19:14:09.338422	2024-01-02 19:14:09.338422
36	Miscellaneous	\N	\N	3	2024-01-02 19:14:09.338422	2024-01-02 19:14:09.338422
37	Housing	\N	\N	4	2024-01-02 20:04:04.528728	2024-01-02 20:04:04.528728
38	Transportation	\N	\N	4	2024-01-02 20:04:04.528728	2024-01-02 20:04:04.528728
39	Food	\N	\N	4	2024-01-02 20:04:04.528728	2024-01-02 20:04:04.528728
40	Utilities	\N	\N	4	2024-01-02 20:04:04.528728	2024-01-02 20:04:04.528728
41	Medical & Healthcare	\N	\N	4	2024-01-02 20:04:04.528728	2024-01-02 20:04:04.528728
42	Fitness	\N	\N	4	2024-01-02 20:04:04.528728	2024-01-02 20:04:04.528728
43	Debt Payments	\N	\N	4	2024-01-02 20:04:04.528728	2024-01-02 20:04:04.528728
44	Personal Care	\N	\N	4	2024-01-02 20:04:04.528728	2024-01-02 20:04:04.528728
45	Entertainment	\N	\N	4	2024-01-02 20:04:04.528728	2024-01-02 20:04:04.528728
46	Pets	\N	\N	4	2024-01-02 20:04:04.528728	2024-01-02 20:04:04.528728
47	Clothes	\N	\N	4	2024-01-02 20:04:04.528728	2024-01-02 20:04:04.528728
48	Miscellaneous	\N	\N	4	2024-01-02 20:04:04.528728	2024-01-02 20:04:04.528728
49	Housing	\N	\N	5	2024-01-02 20:07:31.324875	2024-01-02 20:07:31.324875
50	Transportation	\N	\N	5	2024-01-02 20:07:31.324875	2024-01-02 20:07:31.324875
51	Food	\N	\N	5	2024-01-02 20:07:31.324875	2024-01-02 20:07:31.324875
52	Utilities	\N	\N	5	2024-01-02 20:07:31.324875	2024-01-02 20:07:31.324875
53	Medical & Healthcare	\N	\N	5	2024-01-02 20:07:31.324875	2024-01-02 20:07:31.324875
54	Fitness	\N	\N	5	2024-01-02 20:07:31.324875	2024-01-02 20:07:31.324875
55	Debt Payments	\N	\N	5	2024-01-02 20:07:31.324875	2024-01-02 20:07:31.324875
56	Personal Care	\N	\N	5	2024-01-02 20:07:31.324875	2024-01-02 20:07:31.324875
57	Entertainment	\N	\N	5	2024-01-02 20:07:31.324875	2024-01-02 20:07:31.324875
58	Pets	\N	\N	5	2024-01-02 20:07:31.324875	2024-01-02 20:07:31.324875
59	Clothes	\N	\N	5	2024-01-02 20:07:31.324875	2024-01-02 20:07:31.324875
60	Miscellaneous	\N	\N	5	2024-01-02 20:07:31.324875	2024-01-02 20:07:31.324875
72	Miscellaneous (Saving Annually)	$0.00	#9600e6	6	2024-01-02 23:57:19.296947	2024-11-01 19:24:52.671545
87	Career Advancement	$50.00	#00e6e6	6	2024-01-10 01:01:27.283462	2024-11-01 19:21:12.920173
74	Housing	\N	\N	7	2024-01-03 03:26:49.090645	2024-01-03 03:26:49.090645
75	Transportation	\N	\N	7	2024-01-03 03:26:49.090645	2024-01-03 03:26:49.090645
76	Food	\N	\N	7	2024-01-03 03:26:49.090645	2024-01-03 03:26:49.090645
77	Utilities	\N	\N	7	2024-01-03 03:26:49.090645	2024-01-03 03:26:49.090645
78	Medical & Healthcare	\N	\N	7	2024-01-03 03:26:49.090645	2024-01-03 03:26:49.090645
79	Fitness	\N	\N	7	2024-01-03 03:26:49.090645	2024-01-03 03:26:49.090645
80	Debt Payments	\N	\N	7	2024-01-03 03:26:49.090645	2024-01-03 03:26:49.090645
81	Personal Care	\N	\N	7	2024-01-03 03:26:49.090645	2024-01-03 03:26:49.090645
82	Entertainment	\N	\N	7	2024-01-03 03:26:49.090645	2024-01-03 03:26:49.090645
83	Pets	\N	\N	7	2024-01-03 03:26:49.090645	2024-01-03 03:26:49.090645
84	Clothes	\N	\N	7	2024-01-03 03:26:49.090645	2024-01-03 03:26:49.090645
85	Miscellaneous	\N	\N	7	2024-01-03 03:26:49.090645	2024-01-03 03:26:49.090645
66	Fitness	$100.00	#00dee6	6	2024-01-02 23:57:19.296947	2024-11-01 19:21:33.588262
89	Hair Cut/Skin Care	$100.00	#0060e6	6	2024-03-14 23:43:27.209672	2024-11-01 19:21:48.876786
71	Clothes & Estate Sale	$400.00	#e65a27	6	2024-01-02 23:57:19.296947	2024-11-01 19:25:40.173118
61	Mortgage & HOA	$2,025.00	#00e608	6	2024-01-02 23:57:19.296947	2024-11-01 19:22:43.775591
70	Pets	$80.00	#e6e602	6	2024-01-02 23:57:19.296947	2024-11-01 19:22:54.269995
63	Food & Grocery	$1,800.00	#e60505	6	2024-01-02 23:57:19.296947	2024-11-01 14:02:39.250831
88	Shopping 	$300.00	#0077e6	6	2024-02-23 01:52:24.797999	2024-11-01 19:23:20.273159
65	Medical & Healthcare	$1,050.00	#00e65c	6	2024-01-02 23:57:19.296947	2024-11-01 19:22:01.572465
62	Transportation	$180.00	#e69900	6	2024-01-02 23:57:19.296947	2024-11-01 19:23:38.072611
64	Utilities Monthly (Phone, Housing)	$500.00	#08e600	6	2024-01-02 23:57:19.296947	2024-11-01 19:23:53.970456
73	Monthly Membership	$55.00	#cfe600	6	2024-01-03 00:05:23.751944	2024-11-01 19:22:26.971511
69	Vacations	$100.00	#9d00e6	6	2024-01-02 23:57:19.296947	2024-11-01 19:24:11.270465
\.


--
-- Data for Name: expenses; Type: TABLE DATA; Schema: public; Owner: -
--

COPY "public"."expenses" ("id", "name", "amount", "date", "category_id", "created_at", "updated_at") FROM stdin;
1	GA Power Bill	$145.38	2024-01-02	4	2024-01-02 19:26:39.452406	2024-01-02 19:26:39.452406
2	testing	$1,239.23	2024-01-01	45	2024-01-02 20:05:46.126748	2024-01-02 20:05:46.126748
4	Life Time	$15.38	2024-01-02	73	2024-01-03 00:06:32.072486	2024-01-03 00:06:32.072486
5	Spotify	$14.99	2024-01-02	73	2024-01-03 00:06:32.114714	2024-01-03 00:06:32.114714
6	Name Cheap.com	$9.95	2024-01-02	73	2024-01-03 00:10:32.986556	2024-01-03 00:10:32.986556
78	Life Time	$15.38	2024-02-02	66	2024-02-12 15:53:36.782397	2024-02-12 15:53:36.782397
3	GA Power Bill	$145.38	2024-01-02	64	2024-01-03 00:00:16.063887	2024-01-03 00:10:59.285481
7	HOA	$120.00	2024-01-04	61	2024-01-10 00:48:19.085512	2024-01-10 00:48:19.085512
8	Apple Bill	$2.99	2024-01-09	73	2024-01-10 00:48:58.165054	2024-01-10 00:48:58.165054
9	Arby's	$3.43	2024-01-06	63	2024-01-10 00:50:48.643486	2024-01-10 00:50:48.643486
10	Arby's	$8.37	2024-01-06	63	2024-01-10 00:50:48.667512	2024-01-10 00:50:48.667512
11	McDonalds	$12.14	2024-01-06	63	2024-01-10 00:50:48.6756	2024-01-10 00:50:48.6756
12	Bobo Garden	$149.42	2024-01-05	63	2024-01-10 00:51:29.88535	2024-01-10 00:51:29.88535
13	10 Seconds	$61.30	2024-01-05	63	2024-01-10 00:51:29.888198	2024-01-10 00:51:29.888198
14	Sweet Hut Bakery	$6.31	2024-01-04	63	2024-01-10 00:52:27.246801	2024-01-10 00:52:27.246801
15	Sweet Hut Bakery	$12.47	2024-01-04	63	2024-01-10 00:52:27.250476	2024-01-10 00:52:27.250476
16	Tofu Village	$42.41	2024-01-04	63	2024-01-10 00:52:27.254127	2024-01-10 00:52:27.254127
17	Farmer's Market	$45.62	2024-01-09	63	2024-01-10 01:02:12.134353	2024-01-10 01:02:12.134353
18	LARE Section 2	$525.00	2024-01-09	87	2024-01-10 01:02:33.831511	2024-01-10 01:02:33.831511
19	Gas	$25.72	2024-01-09	62	2024-01-10 01:03:00.815681	2024-01-10 01:03:00.815681
20	Annual HOA	$1,710.70	2024-01-08	61	2024-01-10 01:06:02.513567	2024-01-10 01:06:02.513567
21	CVS	$71.43	2024-01-08	65	2024-01-10 01:06:02.516773	2024-01-10 01:06:02.516773
22	Revolving Sushi	$99.91	2024-01-08	63	2024-01-10 01:06:02.519475	2024-01-10 01:06:02.519475
23	AGA Professional Service (Henry Ass)	$150.00	2024-01-08	65	2024-01-10 01:06:02.521753	2024-01-10 01:06:02.521753
24	Gas	$16.69	2024-01-08	62	2024-01-10 01:06:02.524058	2024-01-10 01:06:02.524058
25	Ober Snowboard Ticket (Zeke)	$187.68	2024-01-07	69	2024-01-10 01:10:13.145813	2024-01-10 01:10:13.145813
26	Ober Snowboard Ticket	$280.39	2024-01-07	69	2024-01-10 01:10:13.151533	2024-01-10 01:10:13.151533
27	Ober Snowboard Ticket	$127.40	2024-01-07	69	2024-01-10 01:10:13.155574	2024-01-10 01:10:13.155574
28	Gatlinburg Parking	$20.00	2024-01-07	69	2024-01-10 01:10:13.159474	2024-01-10 01:10:13.159474
29	Ober  Parking	$20.00	2024-01-07	69	2024-01-10 01:10:13.166437	2024-01-10 01:10:13.166437
30	Gatlinburg Parking	$20.00	2024-01-06	69	2024-01-10 01:12:15.353486	2024-01-10 01:12:15.353486
31	Ober Parking	$20.00	2024-01-06	69	2024-01-10 01:12:15.35708	2024-01-10 01:12:15.35708
32	Racetrac gas	$18.45	2024-01-06	62	2024-01-10 01:12:15.38007	2024-01-10 01:12:15.38007
33	HMART	$100.81	2024-01-05	63	2024-01-10 01:12:48.282807	2024-01-10 01:12:48.282807
34	Gas	$22.44	2024-01-04	62	2024-01-10 01:13:22.517665	2024-01-10 01:13:22.517665
35	ACH HOLD Rocket Money Premium	$48.00	2024-01-10	73	2024-01-11 03:08:19.589095	2024-01-11 03:08:19.589095
36	Tasty Jia	$112.94	2024-01-10	63	2024-01-11 03:10:28.283143	2024-01-11 03:10:28.283143
37	Gas	$21.00	2024-01-10	62	2024-01-11 03:15:41.62131	2024-01-11 03:15:41.62131
38	King Pop	$22.14	2024-01-10	63	2024-01-11 03:15:41.714651	2024-01-11 03:15:41.714651
40	Ponce City Market Parking	$11.00	2024-01-10	62	2024-01-11 03:15:41.720706	2024-01-11 03:15:41.720706
41	Henry's Phone Bill	$26.50	2024-01-16	73	2024-01-17 04:50:04.51475	2024-01-17 04:50:04.51475
43	Publix	$136.24	2024-01-16	63	2024-01-17 04:53:33.560038	2024-01-17 04:53:33.560038
44	Parking For Work	$15.00	2024-01-16	62	2024-01-17 04:53:33.566771	2024-01-17 04:53:33.566771
45	UnitedHealthOne	$134.64	2024-01-12	65	2024-01-17 04:53:56.659321	2024-01-17 04:53:56.659321
46	Scana Energy	$74.38	2024-01-18	64	2024-01-20 07:46:13.88773	2024-01-20 07:46:13.88773
48	Amazon	$27.49	2024-01-19	69	2024-01-20 07:48:58.318061	2024-01-20 07:48:58.318061
49	Sephora	$569.16	2024-01-19	69	2024-01-20 07:48:58.323638	2024-01-20 07:48:58.323638
51	Gas	$22.11	2024-01-19	62	2024-01-20 07:49:15.042235	2024-01-20 07:49:15.042235
52	USPS (Exam Application)	$9.65	2024-01-19	87	2024-01-20 07:50:02.118008	2024-01-20 07:50:02.118008
53	Target	$392.03	2024-01-22	69	2024-01-23 02:18:58.646452	2024-01-23 02:18:58.646452
54	H MART	$155.43	2024-01-22	63	2024-01-23 02:18:58.656624	2024-01-23 02:18:58.656624
55	Apple Bill	$2.99	2024-01-22	73	2024-01-23 02:18:58.669199	2024-01-23 02:18:58.669199
56	Publix	$253.81	2024-01-21	69	2024-01-23 02:19:33.771229	2024-01-23 02:19:33.771229
57	Kroger	$118.53	2024-01-22	69	2024-01-23 02:21:00.924551	2024-01-23 02:21:00.924551
58	Amazon	$284.81	2024-01-22	69	2024-01-23 02:21:00.95267	2024-01-23 02:21:00.95267
59	Amazon	$44.97	2024-01-22	69	2024-01-23 02:21:00.957064	2024-01-23 02:21:00.957064
60	Amazon	$262.37	2024-01-22	69	2024-01-23 02:21:01.015414	2024-01-23 02:21:01.015414
61	GNC	$142.14	2024-01-20	69	2024-01-23 02:21:21.786127	2024-01-23 02:21:21.786127
50	10 Seconds Noodle	$34.41	2024-01-19	63	2024-01-20 07:48:58.3274	2024-01-23 02:22:35.190062
62	Chickfila	$26.54	2024-01-20	63	2024-01-23 02:22:41.253465	2024-01-23 02:22:41.253465
64	Amazon	$35.83	2024-01-23	69	2024-01-25 05:34:29.33082	2024-01-25 05:34:29.33082
63	USPS (Henry Insurance Check)	$9.85	2024-01-25	72	2024-01-25 05:32:45.502263	2024-01-25 05:35:22.995179
65	Ming AT&T Phone	$42.50	2024-01-25	64	2024-01-27 05:10:43.659756	2024-01-27 05:10:43.659756
66	AT&T Wifi	$69.32	2024-01-26	64	2024-01-27 05:12:17.006558	2024-01-27 05:12:17.006558
67	Gas	$22.50	2024-01-26	62	2024-01-27 05:12:17.098499	2024-01-27 05:12:17.098499
68	BestBuy	$75.59	2024-01-26	69	2024-01-27 05:12:17.104882	2024-01-27 05:12:17.104882
69	Amazon	$112.36	2024-01-24	69	2024-01-27 05:13:07.458728	2024-01-27 05:13:07.458728
70	HOA	$120.00	2024-02-06	61	2024-02-12 15:40:39.897149	2024-02-12 15:40:39.897149
71	GA Power Bill	$199.62	2024-01-30	64	2024-02-12 15:44:41.503977	2024-02-12 15:44:41.503977
72	Henry Venmo (Zeke Present)	$25.00	2024-01-29	72	2024-02-12 15:45:42.176301	2024-02-12 15:45:42.176301
73	SEA Food Hall	$36.60	2024-02-12	69	2024-02-12 15:49:32.799335	2024-02-12 15:49:32.799335
74	Apple Bill	$2.99	2024-02-09	73	2024-02-12 15:50:57.073916	2024-02-12 15:50:57.073916
75	Henry Novel	$4.99	2024-02-08	73	2024-02-12 15:51:37.155078	2024-02-12 15:51:37.155078
76	Apple Bill	$9.99	2024-02-07	73	2024-02-12 15:52:39.410055	2024-02-12 15:52:39.410055
77	Spotify	$14.99	2024-02-02	73	2024-02-12 15:53:13.830154	2024-02-12 15:53:13.830154
79	All State Health Solution	$104.05	2024-01-29	65	2024-02-12 15:54:36.926543	2024-02-12 15:54:36.926543
80	Github	$10.00	2024-01-29	73	2024-02-12 15:54:59.942092	2024-02-12 15:54:59.942092
81	WallStreet ATL (Snacks)	$2.58	2024-01-29	69	2024-02-12 15:59:08.064398	2024-02-12 15:59:08.064398
82	Mcdonald's 9.70	$9.70	2024-01-29	69	2024-02-12 15:59:08.095248	2024-02-12 15:59:08.095248
83	WIFIONBOARD	$69.95	2024-01-29	69	2024-02-12 16:00:39.270341	2024-02-12 16:00:39.270341
84	ATT Bill Payment	$1.00	2024-01-24	64	2024-02-12 16:02:43.093977	2024-02-12 16:02:43.093977
85	Amazon (AC Filter)	$59.00	2024-02-11	61	2024-02-12 16:07:49.508341	2024-02-12 16:07:49.508341
86	SEA Burger	$21.90	2024-01-27	69	2024-02-12 16:09:17.778743	2024-02-12 16:09:17.778743
87	SEA Indian	$16.00	2024-01-27	69	2024-02-12 16:09:17.782058	2024-02-12 16:09:17.782058
88	Uber	$16.13	2024-02-12	69	2024-02-12 16:14:41.220977	2024-02-12 16:14:41.220977
89	Uber	$48.26	2024-02-12	69	2024-02-12 16:14:41.224647	2024-02-12 16:14:41.224647
90	SEA Hotel	$57.91	2024-02-12	69	2024-02-12 16:14:41.307241	2024-02-12 16:14:41.307241
91	CLARB	$160.00	2024-02-01	87	2024-02-12 16:15:13.218852	2024-02-12 16:15:13.218852
92	Render.com	$6.61	2024-02-01	73	2024-02-12 16:15:48.209246	2024-02-12 16:15:48.209246
93	Water Bill	$88.17	2024-02-14	64	2024-02-15 10:36:03.509015	2024-02-15 10:36:03.509015
94	Mortgage	$2,200.00	2024-02-14	61	2024-02-15 10:36:03.562591	2024-02-15 10:36:03.562591
95	Chewy	$57.30	2024-02-14	70	2024-02-15 10:38:16.466231	2024-02-15 10:38:16.466231
97	Chickfila	$9.52	2024-02-13	63	2024-02-15 10:39:27.385475	2024-02-15 10:39:27.385475
98	Last Xfinity Wifi	$102.91	2024-02-13	64	2024-02-15 10:40:07.579865	2024-02-15 10:40:07.579865
99	United HealthOne	$134.64	2024-02-14	65	2024-02-15 10:41:14.307267	2024-02-15 10:41:14.307267
100	Henry Phone Bill	$26.50	2024-02-19	73	2024-02-20 01:59:59.426143	2024-02-20 01:59:59.426143
101	Ming Speeding Ticket	$154.70	2024-02-19	72	2024-02-20 01:59:59.500756	2024-02-20 01:59:59.500756
102	TurboTax	$128.00	2024-02-18	72	2024-02-20 02:00:32.876505	2024-02-20 02:00:32.876505
105	HMART	$144.02	2024-02-19	63	2024-02-20 02:04:14.846275	2024-02-20 02:04:14.846275
106	Air Filter	$59.00	2024-02-15	61	2024-02-20 02:05:37.716114	2024-02-20 02:05:37.716114
107	Ming's LARE Exam	$525.00	2024-02-15	87	2024-02-20 02:07:20.220641	2024-02-20 02:07:20.220641
108	Gas	$103.74	2024-02-20	64	2024-02-23 01:43:21.375951	2024-02-23 01:43:21.375951
109	Apple Bill	$2.99	2024-02-22	73	2024-02-23 01:48:32.676084	2024-02-23 01:48:32.676084
110	Publix	$45.90	2024-02-21	63	2024-02-23 01:48:57.546319	2024-02-23 01:48:57.546319
111	LARE Prep	$59.99	2024-02-20	87	2024-02-23 01:49:18.750886	2024-02-23 01:49:18.750886
112	Ming's Rain Boots	$226.75	2024-02-20	71	2024-02-23 01:50:53.10911	2024-02-23 01:50:53.10911
113	Crate&Barrel Spatulas	$68.45	2024-02-21	88	2024-02-23 01:53:10.397897	2024-02-23 01:53:10.397897
114	Chevron	$25.14	2024-02-25	62	2024-02-26 02:30:20.145866	2024-02-26 02:30:20.145866
116	Downtown parking (Optimist)	$9.54	2024-02-25	62	2024-02-26 02:30:20.156519	2024-02-26 02:30:20.156519
117	Publix (quick lunch)	$41.46	2024-02-25	63	2024-02-26 02:30:20.160086	2024-02-26 02:30:20.160086
118	Publix (water)	$2.56	2024-02-25	63	2024-02-26 02:30:20.163691	2024-02-26 02:30:20.163691
119	Publix 	$31.30	2024-02-25	63	2024-02-26 02:30:20.167806	2024-02-26 02:30:20.167806
122	Willy's	$25.55	2024-02-23	63	2024-02-26 02:37:52.171999	2024-02-26 02:37:52.171999
123	Power Bill	$207.98	2024-02-28	64	2024-03-01 15:11:30.200132	2024-03-01 15:11:30.200132
124	Ming AT&T Phone	$42.50	2024-02-26	64	2024-03-01 15:13:02.186724	2024-03-01 15:13:02.186724
125	Spotify	$14.00	2024-03-01	73	2024-03-01 15:17:56.420712	2024-03-01 15:17:56.420712
126	ALL STATE HEALTHSOLOTION	$104.05	2024-02-29	65	2024-03-01 15:19:13.653682	2024-03-01 15:19:13.653682
127	GITHUB	$10.00	2024-02-29	73	2024-03-01 15:19:13.657965	2024-03-01 15:19:13.657965
115	Optimist	$177.00	2024-02-25	63	2024-02-26 02:30:20.150657	2024-03-01 15:21:11.640719
128	SP SECRETLAB 	$1,194.48	2024-02-28	88	2024-03-01 15:23:21.617089	2024-03-01 15:23:21.617089
130	Chewy	$113.91	2024-02-26	70	2024-03-01 15:23:55.771331	2024-03-01 15:23:55.771331
131	Render.com	$7.00	2024-03-01	73	2024-03-01 15:27:11.380234	2024-03-01 15:27:11.380234
134	ATT wifi	$62.62	2024-03-03	64	2024-03-04 23:25:25.727548	2024-03-04 23:25:25.727548
135	Chickfila	$31.40	2024-03-03	63	2024-03-04 23:25:46.991845	2024-03-04 23:25:46.991845
136	Car Maintance	$88.29	2024-03-01	62	2024-03-04 23:26:10.312998	2024-03-04 23:26:10.312998
138	Popflex	$267.84	2024-03-02	71	2024-03-04 23:37:47.886247	2024-03-04 23:37:47.886247
139	H mart	$254.57	2024-03-03	63	2024-03-04 23:40:53.149881	2024-03-04 23:40:53.149881
140	HOA	$120.00	2024-03-05	61	2024-03-12 03:56:06.616044	2024-03-12 03:56:06.616044
141	Mortgage	$2,200.00	2024-03-05	61	2024-03-14 01:03:14.270204	2024-03-14 01:03:14.270204
142	Farmer's Market	$140.46	2024-03-12	63	2024-03-14 01:05:55.981533	2024-03-14 01:05:55.981533
143	Gas	$22.15	2024-03-12	62	2024-03-14 01:05:55.991196	2024-03-14 01:05:55.991196
144	Publix	$127.23	2024-03-12	63	2024-03-14 01:05:56.073069	2024-03-14 01:05:56.073069
145	Henry Novel	$4.99	2024-03-12	73	2024-03-14 01:05:56.081024	2024-03-14 01:05:56.081024
146	BestBuy	$42.79	2024-03-11	88	2024-03-14 01:06:16.988941	2024-03-14 01:06:16.988941
147	Apple Cloud	$2.99	2024-03-09	73	2024-03-14 01:06:37.175768	2024-03-14 01:06:37.175768
148	Broken Faucet Plumber Service	$99.00	2024-03-08	61	2024-03-14 01:07:11.949487	2024-03-14 01:07:11.949487
149	Gas	$23.51	2024-03-07	62	2024-03-14 01:08:03.249098	2024-03-14 01:08:03.249098
133	Ten Sec	$34.41	2024-03-03	63	2024-03-04 23:25:01.242435	2024-03-14 01:08:23.373351
150	Ming Practice Test	$25.00	2024-03-12	87	2024-03-14 01:10:23.508639	2024-03-14 01:10:23.508639
151	Amazon Switch SD CARD	$118.79	2024-03-11	88	2024-03-14 01:10:43.806194	2024-03-14 01:10:43.806194
152	Amazon	$10.79	2024-03-11	88	2024-03-14 01:11:06.219434	2024-03-14 01:11:06.219434
153	Amazon	$48.59	2024-03-08	88	2024-03-14 01:11:30.619884	2024-03-14 01:11:30.619884
154	Amazon	$21.58	2024-03-08	88	2024-03-14 01:11:44.53425	2024-03-14 01:11:44.53425
155	Willy's	$24.17	2024-03-12	63	2024-03-14 01:13:02.663549	2024-03-14 01:13:02.663549
156	Willy's	$24.17	2024-03-10	63	2024-03-14 01:13:11.153001	2024-03-14 01:13:11.153001
160	Willy's	$24.17	2024-03-08	63	2024-03-14 01:17:22.218597	2024-03-14 01:17:22.218597
161	Willy's	$24.17	2024-03-11	63	2024-03-14 01:17:45.636823	2024-03-14 01:17:45.636823
162	Chickfila	$22.79	2024-03-10	63	2024-03-14 01:18:15.17574	2024-03-14 01:18:15.17574
163	UnitedHealthOne	$134.64	2024-03-13	65	2024-03-14 01:19:50.214066	2024-03-14 01:19:50.214066
166	post office	$0.88	2024-03-13	72	2024-03-15 00:59:00.546465	2024-03-15 00:59:00.546465
167	Henry Phone Bill	$26.50	2024-03-17	64	2024-03-17 20:09:30.414536	2024-03-17 20:09:30.414536
168	estate sale	$23.31	2024-03-16	88	2024-03-17 20:13:06.32109	2024-03-17 20:13:06.32109
169	amazon Prime	$8.09	2024-03-17	73	2024-03-17 20:14:16.547086	2024-03-17 20:14:16.547086
170	Willy's	$24.17	2024-03-16	63	2024-03-17 20:16:53.425762	2024-03-17 20:16:53.425762
171	Chickfila	$21.15	2024-03-16	63	2024-03-17 20:16:53.430114	2024-03-17 20:16:53.430114
172	estate sale	$13.90	2024-03-16	88	2024-03-17 20:17:50.106784	2024-03-17 20:17:50.106784
173	Water Bill	$51.79	2024-03-18	64	2024-03-25 00:28:29.72808	2024-03-25 00:28:29.72808
174	Scana Energy	$100.15	2024-03-20	64	2024-03-25 00:30:13.638182	2024-03-25 00:30:13.638182
175	Shell Gas	$27.03	2024-03-23	62	2024-03-25 00:31:26.111383	2024-03-25 00:31:26.111383
177	Shell (Truck Renting for patio furniture)	$7.06	2024-03-22	61	2024-03-25 00:35:54.975256	2024-03-25 00:35:54.975256
179	GA DDS (Ming Driver's Liscense)	$20.00	2024-03-22	62	2024-03-25 00:35:55.063116	2024-03-25 00:35:55.063116
181	Chevron	$28.55	2024-03-20	62	2024-03-25 00:37:22.015349	2024-03-25 00:37:22.015349
180	Apple Bill	$2.99	2024-03-22	73	2024-03-25 00:35:55.068092	2024-03-25 00:38:02.583225
182	Estate Sale (Flower pot and Ryan's Coat)	$22.41	2024-03-22	88	2024-03-25 00:40:46.452085	2024-03-25 00:40:46.452085
183	Estate Sale (Patio Furniture)	$473.39	2024-03-22	61	2024-03-25 00:40:46.455534	2024-03-25 00:40:46.455534
184	LARE Prep Test	$27.99	2024-03-18	87	2024-03-25 00:42:01.853136	2024-03-25 00:42:01.853136
178	Home Depot((Truck Renting for patio furniture)	$46.98	2024-03-22	61	2024-03-25 00:35:54.979931	2024-03-27 00:23:41.331148
96	Amazon	$205.80	2024-02-14	89	2024-02-15 10:38:16.552302	2024-02-15 10:38:16.552302
185	Willy's	$28.30	2024-03-22	63	2024-03-25 00:44:36.62366	2024-03-25 00:44:36.62366
186	Ten Sec	$59.49	2024-03-22	63	2024-03-25 00:44:36.628933	2024-03-26 02:07:35.775269
187	Willy's	$24.17	2024-03-21	63	2024-03-25 00:45:14.654834	2024-03-25 00:45:14.654834
188	Farmer's Market	$15.86	2024-03-18	63	2024-03-25 00:46:49.635956	2024-03-25 00:46:49.635956
189	Oh k-dog (Ryan)	$5.39	2024-03-18	63	2024-03-25 00:46:49.641634	2024-03-25 00:46:49.641634
190	Hmart	$107.00	2024-03-18	63	2024-03-25 00:46:49.645595	2024-03-25 00:46:49.645595
192	Life Time	$199.34	2024-03-01	66	2024-03-25 00:54:06.855421	2024-03-25 00:54:31.007516
193	Ming AT&T Phone	$42.50	2024-03-25	64	2024-03-26 02:04:09.581536	2024-03-26 02:04:09.581536
194	park pride t shirt	$35.00	2024-03-25	71	2024-03-26 02:06:10.636639	2024-03-27 00:24:02.059851
195	GA Power Bill	$154.01	2024-03-28	64	2024-03-28 21:48:29.203871	2024-03-28 21:48:29.203871
196	Github	$10.00	2024-03-29	73	2024-03-29 16:36:36.367456	2024-03-29 16:36:36.367456
197	AllStateSolution	$104.05	2024-03-29	65	2024-03-29 16:36:36.382572	2024-03-29 16:36:36.382572
198	Chickfila	$12.57	2024-03-28	63	2024-03-29 16:38:05.13506	2024-03-29 16:38:05.13506
199	publix	$87.09	2024-03-27	63	2024-03-29 16:38:31.668003	2024-03-29 16:38:31.668003
200	Willy's	$24.17	2024-03-27	63	2024-03-29 16:39:18.522897	2024-03-29 16:39:18.522897
201	Spotify	$14.99	2024-04-01	64	2024-04-01 12:21:43.829687	2024-04-01 12:21:43.829687
202	ATT Wifi	$65.30	2024-04-01	64	2024-04-01 12:21:43.834226	2024-04-01 12:21:43.834226
203	Willy's	$11.40	2024-03-31	63	2024-04-01 12:23:39.429526	2024-04-01 12:23:39.429526
204	Willy's	$22.79	2024-03-29	63	2024-04-01 12:24:31.153292	2024-04-01 12:24:31.153292
205	Render.com	$7.00	2024-04-01	73	2024-04-01 12:26:04.451522	2024-04-01 12:26:04.451522
206	Mortgage	$2,200.00	2024-04-01	61	2024-04-01 13:24:12.238737	2024-04-01 13:24:12.238737
207	Life Time	$234.73	2024-04-01	66	2024-04-01 16:22:11.348912	2024-04-01 16:22:11.348912
209	Farmer's Market	$170.54	2024-04-01	63	2024-04-02 12:45:54.802954	2024-04-02 12:45:54.802954
211	Chewy	$158.59	2024-04-02	70	2024-04-02 13:08:44.403794	2024-04-02 13:08:44.403794
213	Willy's	$25.55	2024-04-07	63	2024-04-08 12:21:29.713701	2024-04-08 12:21:29.713701
214	Apple Bill	$4.99	2024-04-07	73	2024-04-08 12:21:29.719194	2024-04-08 12:21:29.719194
215	Chickfila	$19.54	2024-04-06	63	2024-04-08 12:22:23.29006	2024-04-08 12:22:23.29006
217	Hmart	$55.93	2024-04-06	63	2024-04-08 12:22:23.303688	2024-04-08 12:22:23.303688
219	LARE Prep	$27.99	2024-04-03	87	2024-04-08 12:23:11.306876	2024-04-08 12:23:11.306876
220	Chevron	$22.44	2024-04-02	62	2024-04-08 12:24:30.383682	2024-04-08 12:24:30.383682
222	Revolving SUS	$99.80	2024-04-06	63	2024-04-08 12:28:21.055551	2024-04-08 12:28:21.055551
223	Publix	$91.35	2024-04-09	63	2024-04-10 12:40:56.381948	2024-04-10 12:40:56.381948
224	Apple Bill	$2.99	2024-04-09	73	2024-04-10 12:40:56.434049	2024-04-10 12:40:56.434049
225	Chevron	$23.66	2024-04-08	62	2024-04-10 12:42:06.310826	2024-04-10 12:42:06.310826
226	Decatur Plant Sale	$23.76	2024-04-14	88	2024-04-15 12:10:32.452227	2024-04-15 12:10:32.452227
227	Water Bill	$66.63	2024-04-14	64	2024-04-15 12:10:32.474647	2024-04-15 12:10:32.474647
228	Willy's	$25.55	2024-04-14	63	2024-04-15 12:13:21.790547	2024-04-15 12:13:21.790547
229	Palworld Henry	$33.22	2024-04-13	72	2024-04-15 12:16:17.987575	2024-04-15 12:16:17.987575
231	Ten Sec	$37.75	2024-04-13	63	2024-04-15 12:16:17.994578	2024-04-15 12:16:17.994578
232	Home Deport (Truck Rental)	$46.98	2024-04-13	61	2024-04-15 12:16:17.997604	2024-04-15 12:16:17.997604
233	Estate Sale ( 4 post Bed)	$223.04	2024-04-13	61	2024-04-15 12:16:18.000657	2024-04-15 12:16:18.000657
234	Chickfila	$10.25	2024-04-13	63	2024-04-15 12:16:18.003799	2024-04-15 12:16:18.003799
235	Farmer's Market	$88.80	2024-04-12	63	2024-04-15 12:18:50.572589	2024-04-15 12:18:50.572589
237	UnitedHealthOne	$134.64	2024-04-12	65	2024-04-15 12:27:37.52131	2024-04-15 12:27:37.52131
238	Henry's Parents Car Tire Change	$1,289.05	2024-04-10	72	2024-04-15 12:28:15.248019	2024-04-15 12:28:15.248019
230	Palworld Ming	$33.50	2024-04-13	72	2024-04-15 12:16:17.99136	2024-04-15 12:29:18.81795
239	Progressive Insurance	$1,796.00	2024-04-15	62	2024-04-16 12:13:57.666967	2024-04-16 12:13:57.666967
240	Chickfila	$20.82	2024-04-15	63	2024-04-16 12:14:16.430918	2024-04-16 12:14:16.430918
236	Chevron	$23.89	2024-04-14	62	2024-04-15 12:24:19.093313	2024-04-16 12:15:16.230585
241	Long Horn(Henry Birthday)	$118.24	2024-04-15	63	2024-04-16 12:16:53.718356	2024-04-16 12:16:53.718356
242	Henry Phone Bill	$26.50	2024-04-17	64	2024-04-17 12:25:54.746842	2024-04-17 12:25:54.746842
243	HOA	$120.00	2024-04-17	61	2024-04-17 12:29:41.699605	2024-04-17 12:29:41.699605
244	BOA maintenance Fee	$12.00	2024-04-17	72	2024-04-17 12:29:41.71062	2024-04-17 12:29:41.71062
245	Willy's	$24.17	2024-04-16	63	2024-04-17 12:31:31.142126	2024-04-17 12:31:31.142126
246	Publix	$110.32	2024-04-16	63	2024-04-17 12:31:31.151973	2024-04-17 12:31:31.151973
247	Farmer's Market	$91.58	2024-04-16	63	2024-04-17 12:31:31.159937	2024-04-17 12:31:31.159937
248	Henry Hospital Parking	$6.00	2024-04-16	62	2024-04-17 12:31:31.229544	2024-04-17 12:31:31.229544
250	Scana Energy	$57.81	2024-04-18	64	2024-04-22 12:21:59.113467	2024-04-22 12:21:59.113467
251	Ten Sec	$29.92	2024-04-21	63	2024-04-22 12:23:50.34723	2024-04-22 12:23:50.34723
252	Hmart	$177.11	2024-04-21	63	2024-04-22 12:23:50.352151	2024-04-22 12:23:50.352151
253	Apple Bill	$2.99	2024-04-21	73	2024-04-22 12:23:50.3562	2024-04-22 12:23:50.3562
254	Willy's	$24.17	2024-04-20	63	2024-04-22 12:24:13.995828	2024-04-22 12:24:13.995828
256	Zoo Parking ( Ming Work)	$9.45	2024-04-19	62	2024-04-22 12:28:47.521355	2024-04-22 12:28:47.521355
257	Chevron	$24.58	2024-04-18	62	2024-04-22 12:29:19.971796	2024-04-22 12:29:19.971796
258	Ming AT&T Phone	$42.50	2024-04-24	64	2024-04-25 00:33:07.544907	2024-04-25 00:33:07.544907
259	Chickfila	$13.33	2024-04-24	63	2024-04-25 00:35:09.149943	2024-04-25 00:35:09.149943
260	Ten Sec	$34.41	2024-04-23	63	2024-04-25 00:35:34.009911	2024-04-25 00:35:34.009911
261	Car Tire Light	$407.86	2024-04-24	62	2024-04-25 00:37:48.931627	2024-04-25 00:37:48.931627
262	Power Bill	$143.69	2024-04-29	64	2024-04-29 11:54:48.922362	2024-04-29 11:54:48.922362
263	Publix	$118.95	2024-04-28	63	2024-04-29 11:55:52.944053	2024-04-29 11:55:52.944053
264	Github	$10.00	2024-04-29	73	2024-04-29 11:57:17.623613	2024-04-29 11:57:17.623613
265	ALLSTATEHEALTHSOLUTION	$104.05	2024-04-29	65	2024-04-29 11:57:17.627182	2024-04-29 11:57:17.627182
266	Mcdonald's 	$26.42	2024-04-29	63	2024-04-29 11:57:17.630287	2024-04-29 11:57:17.630287
267	Old Mill Estate Sale	$11.13	2024-04-27	88	2024-04-29 11:58:06.543443	2024-04-29 11:58:06.543443
268	Chickfila	$19.58	2024-04-27	63	2024-04-29 11:58:06.548119	2024-04-29 11:58:06.548119
269	Willy's	$25.55	2024-04-26	63	2024-04-29 11:59:16.555176	2024-04-29 11:59:16.555176
270	Chickfila	$13.33	2024-04-26	63	2024-04-29 11:59:16.558464	2024-04-29 11:59:16.558464
272	Chevron	$26.17	2024-04-26	62	2024-04-29 12:02:03.202798	2024-04-29 12:02:03.202798
273	E Dennis Jasper usa (AC/Heater)	$346.00	2024-04-26	61	2024-04-29 12:04:32.154609	2024-04-29 12:04:32.154609
274	Mortgage	$2,200.00	2024-05-01	61	2024-04-29 12:08:33.915576	2024-04-29 12:08:33.915576
275	Life Time	$234.73	2024-05-01	66	2024-05-01 12:50:20.91078	2024-05-01 12:50:20.91078
276	Spotify	$14.99	2024-05-01	73	2024-05-01 12:50:20.992579	2024-05-01 12:50:20.992579
279	AT&T Wifi	$65.30	2024-05-01	64	2024-05-01 12:50:21.006629	2024-05-01 12:50:21.006629
280	Willy's	$24.17	2024-04-30	63	2024-05-01 12:50:54.408328	2024-05-01 12:50:54.408328
271	Chewy	$55.26	2024-04-29	70	2024-04-29 12:01:04.424215	2024-05-01 12:52:15.690334
281	QT Gas	$23.87	2024-04-29	62	2024-05-01 12:53:13.802361	2024-05-03 12:11:35.18367
212	Henry Hair cut Tip	$10.00	2024-04-06	89	2024-04-08 12:20:03.907608	2024-04-08 12:20:03.907608
216	Henry Hair Cut	$31.05	2024-04-06	89	2024-04-08 12:22:23.298171	2024-04-08 12:22:23.298171
282	Render.com	$7.00	2024-05-01	73	2024-05-01 12:53:58.26322	2024-05-01 12:53:58.26322
285	Publix	$43.81	2024-04-30	63	2024-05-01 12:56:05.752083	2024-05-01 12:56:05.752083
286	Publix (Work)	$8.20	2024-04-30	88	2024-05-01 12:56:05.779129	2024-05-01 12:56:05.779129
287	HOA	$120.00	2024-05-06	61	2024-05-06 12:24:32.21903	2024-05-06 12:24:32.21903
289	Hmart	$107.62	2024-05-05	63	2024-05-06 12:26:07.336251	2024-05-06 12:26:07.336251
290	Farmer's Market	$141.98	2024-05-05	63	2024-05-06 12:26:07.341027	2024-05-06 12:26:07.341027
291	Chickfila	$23.40	2024-05-05	63	2024-05-06 12:26:07.344281	2024-05-06 12:26:07.344281
292	amazon (Snacks and wipes)	$48.26	2024-05-05	63	2024-05-06 12:27:26.53404	2024-05-06 12:27:26.53404
293	Uber eats	$23.58	2024-05-03	63	2024-05-06 12:30:58.780311	2024-05-06 12:30:58.780311
294	Pest Control	$355.00	2024-05-03	61	2024-05-06 12:30:58.805945	2024-05-06 12:30:58.805945
295	Chevron	$26.61	2024-05-08	62	2024-05-08 12:14:42.561272	2024-05-08 12:14:42.561272
296	Publix (Work)	$4.36	2024-05-07	88	2024-05-08 12:15:10.206601	2024-05-08 12:15:10.206601
298	amazon (Kitchen Stuff)	$74.48	2024-05-07	88	2024-05-08 12:17:46.843009	2024-05-08 12:17:46.843009
299	Revolving sus	$89.60	2024-05-06	63	2024-05-08 12:22:04.908922	2024-05-08 12:22:04.908922
301	Apple Bill (Henry novel)	$4.99	2024-05-12	73	2024-05-13 15:49:02.773696	2024-05-13 15:49:02.773696
302	Chickfila	$19.58	2024-05-11	63	2024-05-13 15:50:30.35381	2024-05-13 15:50:30.35381
303	Publix	$164.01	2024-05-11	63	2024-05-13 15:50:30.359972	2024-05-13 15:50:30.359972
304	Radiology (Henry Stomach)	$120.89	2024-05-11	65	2024-05-13 15:50:30.363588	2024-05-13 15:50:30.363588
305	Willy's	$24.17	2024-05-09	63	2024-05-13 15:51:20.381149	2024-05-13 15:51:20.381149
306	Apple Bill	$2.99	2024-05-09	73	2024-05-13 15:51:20.386583	2024-05-13 15:51:20.386583
308	UnitedHealthOne	$134.64	2024-05-11	65	2024-05-13 15:54:32.788252	2024-05-13 15:54:32.788252
309	Dekalb Co Water Bill	$68.79	2024-05-15	64	2024-05-15 12:23:13.125236	2024-05-15 12:23:13.125236
310	Willy's	$22.79	2024-05-14	63	2024-05-15 12:28:29.704599	2024-05-15 12:28:29.704599
311	Home Depot (plant caddy)	$11.85	2024-05-14	88	2024-05-15 12:28:29.711232	2024-05-15 12:28:29.711232
312	Home Depot (plant caddy)	$254.40	2024-05-14	88	2024-05-15 12:28:29.715387	2024-05-15 12:28:29.715387
313	onyx (fixing mac)	$110.66	2024-05-14	72	2024-05-15 12:28:29.720221	2024-05-15 12:28:29.720221
300	Trappeze	$64.00	2024-05-12	63	2024-05-13 15:49:02.769989	2024-05-15 12:28:40.997011
307	Racetrac	$19.95	2024-05-12	62	2024-05-13 15:53:35.330379	2024-05-15 12:30:26.015446
314	Chickfila	$23.40	2024-05-15	63	2024-05-16 03:05:11.246563	2024-05-16 03:05:11.246563
315	Home Depot (plant caddy)	$30.88	2024-05-15	88	2024-05-16 03:05:11.251414	2024-05-16 03:05:11.251414
316	Kroger	$16.72	2024-05-15	63	2024-05-16 03:05:11.255151	2024-05-16 03:05:11.255151
317	Scana Energy	$46.97	2024-05-17	64	2024-05-17 11:54:32.806275	2024-05-17 11:54:32.806275
318	Henry Phone Bill	$26.50	2024-05-17	64	2024-05-17 11:55:17.538561	2024-05-17 11:55:17.538561
319	Power Bill	$138.12	2024-05-29	64	2024-05-30 12:30:10.220612	2024-05-30 12:30:10.220612
320	Estate Sale ( Shelf Metal)	$32.00	2024-05-25	61	2024-05-30 12:30:47.062478	2024-05-30 12:30:47.062478
321	Ming AT&T Phone	$42.50	2024-05-24	64	2024-05-30 12:31:08.426194	2024-05-30 12:31:08.426194
322	Estate Sale (Pots)	$15.00	2024-05-20	88	2024-05-30 12:31:44.723898	2024-05-30 12:31:44.723898
323	Henry Piedmont healthcare	$125.00	2024-05-29	65	2024-05-30 12:33:12.088596	2024-05-30 12:33:12.088596
324	Willy's	$17.77	2024-05-29	63	2024-05-30 12:33:12.092393	2024-05-30 12:33:12.092393
326	ALLSTATEHEALTHSOLUTION	$104.05	2024-05-29	65	2024-05-30 12:34:50.479331	2024-05-30 12:34:50.479331
327	Github	$10.00	2024-05-29	73	2024-05-30 12:34:50.489249	2024-05-30 12:34:50.489249
328	Farmer's Market	$73.52	2024-05-29	63	2024-05-30 12:34:50.497315	2024-05-30 12:34:50.497315
329	Home Depot (garden tool and tomato cages)	$79.81	2024-05-28	88	2024-05-30 12:36:37.056797	2024-05-30 12:36:37.056797
330	Home Depot (Rent Truck Metal Shelf)	$22.42	2024-05-25	61	2024-05-30 12:38:05.379578	2024-05-30 12:38:05.379578
332	Willy's	$24.17	2024-05-27	63	2024-05-30 12:40:32.825729	2024-05-30 12:40:32.825729
333	Mcdonald's	$18.65	2024-05-27	63	2024-05-30 12:40:32.833074	2024-05-30 12:40:32.833074
334	texaco tucker GA	$6.42	2024-05-27	72	2024-05-30 12:40:32.837343	2024-05-30 12:40:32.837343
335	Uber Eat	$24.09	2024-05-24	63	2024-05-30 12:40:51.879031	2024-05-30 12:40:51.879031
336	Publix	$131.36	2024-05-23	63	2024-05-30 12:41:07.312891	2024-05-30 12:41:07.312891
337	Uber eat	$20.95	2024-05-23	63	2024-05-30 12:41:57.863341	2024-05-30 12:41:57.863341
338	Apple Bill	$2.99	2024-05-22	73	2024-05-30 12:42:10.128118	2024-05-30 12:42:10.128118
339	Farmer's Market	$85.80	2024-05-22	63	2024-05-30 12:42:27.502375	2024-05-30 12:42:27.502375
340	678 BBQ	$125.07	2024-05-20	63	2024-05-30 12:43:40.869673	2024-05-30 12:43:40.869673
341	Chickfila	$16.98	2024-05-20	63	2024-05-30 12:43:40.873471	2024-05-30 12:43:40.873471
342	Home Depot (washer)	$11.85	2024-05-20	61	2024-05-30 12:43:40.878681	2024-05-30 12:43:40.878681
343	Willy's	$24.17	2024-05-20	63	2024-05-30 12:45:55.88745	2024-05-30 12:45:55.88745
344	Ten Sec	$43.41	2024-05-20	63	2024-05-30 12:45:55.891185	2024-05-30 12:45:55.891185
345	Home Depot (Planter Caddy)	$72.98	2024-05-20	61	2024-05-30 12:45:55.894604	2024-05-30 12:45:55.894604
346	Rockler ww(Planter Caddy)	$28.43	2024-05-20	61	2024-05-30 12:45:55.898157	2024-05-30 12:45:55.898157
347	Rockler ww(Planter Caddy)	$81.13	2024-05-20	61	2024-05-30 12:45:55.902259	2024-05-30 12:45:55.902259
348	Sephora	$70.20	2024-05-22	89	2024-05-30 12:47:12.925257	2024-05-30 12:47:12.925257
349	Amazon Prime	$1.07	2024-05-17	73	2024-05-30 12:47:38.573788	2024-05-30 12:47:38.573788
350	Amazon (Pressure washer)	$399.59	2024-05-28	88	2024-05-30 12:48:50.994788	2024-05-30 12:48:50.994788
351	Texaco Tucker	$25.98	2024-05-25	62	2024-05-30 12:49:46.889914	2024-05-30 12:49:46.889914
352	Chevron	$27.22	2024-05-17	62	2024-05-30 12:50:25.795273	2024-05-30 12:50:25.795273
353	Mortgage	$2,200.00	2024-06-01	61	2024-05-30 12:56:22.227842	2024-05-30 12:56:22.227842
354	Delta	$2,271.85	2024-05-21	69	2024-05-30 13:06:11.540587	2024-05-30 13:06:11.540587
355	Delta	$1,801.81	2024-05-21	69	2024-05-30 13:06:11.544946	2024-05-30 13:06:11.544946
356	Delta	$48.94	2024-05-21	69	2024-05-30 13:06:11.620214	2024-05-30 13:06:11.620214
357	Delta	$2,271.85	2024-05-21	69	2024-05-30 13:06:11.624308	2024-05-30 13:06:11.624308
358	Delta	$1,801.81	2024-05-21	69	2024-05-30 13:06:11.628418	2024-05-30 13:06:11.628418
359	Delta	$48.94	2024-05-21	69	2024-05-30 13:06:11.633418	2024-05-30 13:06:11.633418
360	Delta	$1,328.80	2024-05-21	69	2024-05-30 13:06:11.715352	2024-05-30 13:06:11.715352
361	Delta	$1,328.80	2024-05-21	69	2024-05-30 13:06:11.727432	2024-05-30 13:06:11.727432
362	Delta	$48.99	2024-05-21	69	2024-05-30 13:06:11.732912	2024-05-30 13:06:11.732912
363	Publix	$132.34	2024-06-01	63	2024-06-01 22:37:15.753799	2024-06-01 22:37:15.753799
364	Life Time	$176.23	2024-06-01	66	2024-06-01 22:37:15.757252	2024-06-01 22:37:15.757252
365	Spotify	$14.99	2024-06-01	73	2024-06-01 22:37:15.760448	2024-06-01 22:37:15.760448
366	Wifi Bill	$65.30	2024-06-01	64	2024-06-01 22:38:21.219364	2024-06-01 22:38:21.219364
325	Refresh foot spa	$168.00	2024-05-26	72	2024-05-30 12:33:42.639612	2024-06-01 22:39:05.424603
367	Chickfila	$21.28	2024-06-01	63	2024-06-01 22:42:26.679301	2024-06-01 22:42:26.679301
368	Home Depot (Furniture restore))	$26.86	2024-06-10	61	2024-06-11 12:30:48.900773	2024-06-11 12:30:48.900773
369	Willy's	$33.36	2024-06-10	63	2024-06-11 12:32:00.80188	2024-06-11 12:32:00.80188
370	Publix	$157.69	2024-06-10	63	2024-06-11 12:32:00.804955	2024-06-11 12:32:00.804955
371	Parking (work)	$10.00	2024-06-10	62	2024-06-11 12:32:00.807654	2024-06-11 12:32:00.807654
372	Chickfila	$18.57	2024-06-10	63	2024-06-11 12:32:00.810751	2024-06-11 12:32:00.810751
373	Apple Bill	$2.99	2024-06-10	73	2024-06-11 12:32:00.814402	2024-06-11 12:32:00.814402
374	Ten Sec	$43.41	2024-06-08	63	2024-06-11 12:32:43.593745	2024-06-11 12:32:43.593745
375	Chickfila	$11.27	2024-06-08	63	2024-06-11 12:32:43.598713	2024-06-11 12:32:43.598713
376	Home Depot (Furniture restore))	$21.51	2024-06-08	61	2024-06-11 12:32:43.603494	2024-06-11 12:32:43.603494
377	CLARB (Section 2)	$525.00	2024-06-07	87	2024-06-11 12:33:05.835851	2024-06-11 12:33:05.835851
378	Chickfila	$28.49	2024-06-06	63	2024-06-11 12:33:31.598724	2024-06-11 12:33:31.598724
379	Parking (work)	$6.45	2024-06-05	62	2024-06-11 12:34:16.727135	2024-06-11 12:34:16.727135
380	Farmer's Market	$62.51	2024-06-05	63	2024-06-11 12:34:32.312577	2024-06-11 12:34:32.312577
381	Willy's	$31.54	2024-06-04	63	2024-06-11 12:34:56.680573	2024-06-11 12:34:56.680573
382	Chevron	$28.29	2024-06-04	62	2024-06-11 12:36:38.885123	2024-06-11 12:36:38.885123
383	Good Harvest (Hot pot)	$115.20	2024-06-08	63	2024-06-11 12:37:29.85318	2024-06-11 12:37:29.85318
384	Willy's	$18.87	2024-06-02	63	2024-06-11 12:38:08.044535	2024-06-11 12:38:46.043271
385	Render.com	$7.00	2024-06-02	73	2024-06-11 12:39:12.868894	2024-06-11 12:39:12.868894
386	Henry Phone Bill	$26.50	2024-06-16	64	2024-06-18 12:37:27.345653	2024-06-18 12:37:27.345653
387	Scana Energy	$41.75	2024-06-17	64	2024-06-18 12:37:44.647811	2024-06-18 12:37:44.647811
388	Henry Hair cut Tip	$10.00	2024-06-17	72	2024-06-18 12:38:46.301666	2024-06-18 12:38:46.301666
389	Water Bill	$68.43	2024-06-17	64	2024-06-18 12:39:29.636932	2024-06-18 12:39:29.636932
391	Cotton & Bea Vet	$244.00	2024-06-17	70	2024-06-18 12:42:20.255874	2024-06-18 12:42:20.255874
392	Publix	$96.78	2024-06-17	63	2024-06-18 12:42:20.259605	2024-06-18 12:42:20.259605
393	Hmart	$205.80	2024-06-14	63	2024-06-18 12:43:47.437644	2024-06-18 12:43:47.437644
394	Hmart	$11.43	2024-06-14	63	2024-06-18 12:43:47.452066	2024-06-18 12:43:47.452066
395	Pho	$38.29	2024-06-14	63	2024-06-18 12:43:47.455599	2024-06-18 12:43:47.455599
396	Chickfila	$11.50	2024-06-13	63	2024-06-18 12:44:17.238289	2024-06-18 12:44:17.238289
397	Shell	$28.45	2024-06-15	62	2024-06-18 12:46:46.175474	2024-06-18 12:46:46.175474
398	Chevron	$27.57	2024-06-11	62	2024-06-18 12:47:09.979942	2024-06-18 12:47:09.979942
399	Revolving Sus	$91.60	2024-06-16	63	2024-06-18 12:48:44.939699	2024-06-18 12:48:44.939699
400	UnitedHealthOne	$134.64	2024-06-12	65	2024-06-18 12:49:20.755571	2024-06-18 12:49:20.755571
401	Ming AT&T Phone	$42.50	2024-06-24	64	2024-06-25 12:06:27.225077	2024-06-25 12:06:27.225077
402	QDI QUEST DIAGNOSTICS	$9.78	2024-06-24	65	2024-06-25 12:12:18.19909	2024-06-25 12:12:18.19909
403	CAFE AVALON	$37.33	2024-06-24	63	2024-06-25 12:12:18.223896	2024-06-25 12:12:18.223896
404	BALDINOS OF ATL	$15.63	2024-06-24	63	2024-06-25 12:12:18.228756	2024-06-25 12:12:18.228756
405	CVS (Henry Pill)	$24.01	2024-06-24	65	2024-06-25 12:12:18.232357	2024-06-25 12:12:18.232357
406	Publix	$142.92	2024-06-22	63	2024-06-25 12:13:16.580995	2024-06-25 12:13:16.580995
407	Apple Bill	$2.99	2024-06-22	73	2024-06-25 12:13:16.593518	2024-06-25 12:13:16.593518
408	QDI QUEST DIAGNOSTICS	$5.34	2024-06-21	65	2024-06-25 12:15:30.945178	2024-06-25 12:15:30.945178
409	QDI QUEST DIAGNOSTICS	$9.78	2024-06-21	65	2024-06-25 12:15:30.949763	2024-06-25 12:15:30.949763
410	PHO	$24.64	2024-06-20	63	2024-06-25 12:15:55.082373	2024-06-25 12:15:55.082373
411	Chevron	$28.55	2024-06-20	62	2024-06-25 12:17:41.682177	2024-06-25 12:17:41.682177
412	Pizza Hut	$23.32	2024-06-21	63	2024-06-25 12:19:40.739037	2024-06-25 12:19:40.739037
413	CITI annual membership	$95.00	2024-06-20	73	2024-06-25 12:20:08.086131	2024-06-25 12:20:08.086131
414	GA Power Bill	$189.72	2024-06-28	64	2024-06-30 05:13:59.724612	2024-06-30 05:13:59.724612
415	Chickfila	$21.10	2024-06-29	63	2024-06-30 05:15:18.734339	2024-06-30 05:15:18.734339
416	Github	$10.00	2024-06-29	73	2024-06-30 05:16:20.129868	2024-06-30 05:16:20.129868
417	Jbistro	$105.32	2024-06-29	63	2024-06-30 05:16:20.142822	2024-06-30 05:16:20.142822
418	Publix	$10.94	2024-06-28	63	2024-06-30 05:18:15.447868	2024-06-30 05:18:15.447868
419	American Deli	$15.11	2024-06-28	63	2024-06-30 05:18:15.451671	2024-06-30 05:18:15.451671
420	Hmart	$218.72	2024-06-28	63	2024-06-30 05:18:15.456029	2024-06-30 05:18:15.456029
421	Willy's	$7.47	2024-06-26	63	2024-06-30 05:18:50.399734	2024-06-30 05:18:50.399734
422	Chevron	$20.34	2024-06-27	62	2024-06-30 05:20:14.693317	2024-06-30 05:20:14.693317
423	QT Gas	$24.63	2024-06-26	62	2024-06-30 05:20:36.095785	2024-06-30 05:20:36.095785
424	Mortgage	$2,200.00	2024-07-01	61	2024-07-01 03:40:23.039135	2024-07-01 03:40:23.039135
425	Home Depot (2 black out shades))	$388.86	2024-07-01	61	2024-07-02 13:54:07.587795	2024-07-02 13:54:07.587795
426	figma monthly renewal	$15.00	2024-07-01	73	2024-07-02 13:54:07.593185	2024-07-02 13:54:07.593185
427	Life Time	$199.34	2024-07-01	66	2024-07-02 13:54:07.597056	2024-07-02 13:54:07.597056
428	QT Gas Staion ( Snack)	$5.49	2024-07-01	63	2024-07-02 13:54:07.600971	2024-07-02 13:54:07.600971
429	Willy's	$28.36	2024-06-30	63	2024-07-02 13:55:03.857085	2024-07-02 13:55:03.857085
430	Spotify	$14.99	2024-07-01	73	2024-07-02 13:56:07.315105	2024-07-02 13:56:07.315105
431	sq white consulting	$12.40	2024-06-30	63	2024-07-02 13:56:53.821034	2024-07-02 13:56:53.821034
432	AT&T Wifi	$65.30	2024-07-01	64	2024-07-02 13:57:12.920667	2024-07-02 13:57:12.920667
433	ALLSTATEHEALTHSOLUTION	$104.05	2024-06-29	65	2024-07-02 13:58:38.048764	2024-07-02 13:58:38.048764
435	Render.com	$7.00	2024-07-01	73	2024-07-02 14:01:22.562519	2024-07-02 14:01:22.562519
437	Return Jiawei Deposit	$781.70	2024-07-03	72	2024-07-03 12:49:41.432881	2024-07-03 12:49:41.432881
438	Publix	$73.12	2024-07-02	63	2024-07-03 12:50:12.113403	2024-07-03 12:50:12.113403
434	QT Gas	$24.44	2024-06-30	62	2024-07-02 14:00:15.510234	2024-07-03 12:51:44.759909
436	CRU Avalon	$43.71	2024-07-01	63	2024-07-02 14:01:22.568286	2024-07-03 12:52:34.012512
439	Return Jody Deposit	$965.49	2024-07-05	72	2024-07-10 04:03:47.245906	2024-07-10 04:03:47.245906
440	Chickfila	$9.12	2024-07-10	63	2024-07-10 04:07:17.644034	2024-07-10 04:07:17.644034
441	Chickfila	$9.12	2024-07-10	63	2024-07-10 04:07:17.648101	2024-07-10 04:07:17.648101
442	Home Depot (showerhead pot)	$105.00	2024-07-10	61	2024-07-10 04:07:17.651775	2024-07-10 04:07:17.651775
443	cursor ai powered ide (Henry Work)	$20.00	2024-07-10	87	2024-07-10 04:09:13.900582	2024-07-10 04:09:13.900582
444	Ming Doctor Visit	$25.00	2024-07-10	65	2024-07-10 04:09:13.904444	2024-07-10 04:09:13.904444
445	Willy's	$14.70	2024-07-08	63	2024-07-10 04:09:35.181186	2024-07-10 04:09:35.181186
446	Apple Bill	$2.99	2024-07-08	73	2024-07-10 04:11:33.812767	2024-07-10 04:11:33.812767
447	Chevron	$26.80	2024-07-08	62	2024-07-10 04:11:33.826641	2024-07-10 04:11:33.826641
448	Home Depot (lag screws)	$30.78	2024-07-08	61	2024-07-10 04:11:33.834566	2024-07-10 04:11:33.834566
449	Farmer's Market	$100.23	2024-07-08	63	2024-07-10 04:13:18.151043	2024-07-10 04:13:18.151043
450	Apple Bill (Henry Novel)	$4.99	2024-07-06	73	2024-07-10 04:14:26.837136	2024-07-10 04:14:26.837136
451	estate sale (Plant Stant)	$81.92	2024-07-06	72	2024-07-10 04:16:04.356306	2024-07-10 04:16:04.356306
452	Chickfila	$19.97	2024-07-06	63	2024-07-10 04:16:49.193552	2024-07-10 04:16:49.193552
453	waffle house	$29.71	2024-07-06	63	2024-07-10 04:18:41.90778	2024-07-10 04:18:41.90778
454	Home Depot (carpet cleaner)	$33.21	2024-07-06	72	2024-07-10 04:18:41.91326	2024-07-10 04:18:41.91326
455	alta	$30.00	2024-07-04	66	2024-07-10 04:19:31.408002	2024-07-10 04:19:31.408002
456	usta	$30.00	2024-07-04	66	2024-07-10 04:19:31.412371	2024-07-10 04:19:31.412371
457	amazon (house improvement)	$44.28	2024-07-09	72	2024-07-10 04:23:00.472371	2024-07-10 04:23:00.472371
458	Chewy	$55.74	2024-07-08	70	2024-07-10 04:24:53.723881	2024-07-10 04:24:53.723881
459	william sonoma	$215.45	2024-07-08	88	2024-07-10 04:24:53.7484	2024-07-10 04:24:53.7484
461	william sonoma	$156.18	2024-07-07	88	2024-07-10 04:30:06.807184	2024-07-10 04:30:06.807184
463	pho	$44.00	2024-07-05	63	2024-07-10 04:30:27.801074	2024-07-10 04:30:27.801074
464	Home Depot 	$50.00	2024-07-13	61	2024-07-15 02:23:02.535177	2024-07-15 02:23:02.535177
465	Ikea	$180.59	2024-07-13	61	2024-07-15 02:23:02.539441	2024-07-15 02:23:02.539441
466	QT Gas	$29.39	2024-07-13	62	2024-07-15 02:23:02.543102	2024-07-15 02:23:02.543102
467	Kroger (Ming Medicine)	$16.96	2024-07-12	65	2024-07-15 02:24:43.164351	2024-07-15 02:24:43.164351
468	Kroger	$87.79	2024-07-12	63	2024-07-15 02:24:43.252816	2024-07-15 02:24:43.252816
469	Amazon	$135.94	2024-07-12	88	2024-07-15 02:34:07.103317	2024-07-15 02:34:07.103317
470	Revolving sus	$72.87	2024-07-14	63	2024-07-15 02:39:17.680887	2024-07-15 02:39:17.680887
472	Willy's	$26.61	2024-07-12	63	2024-07-15 02:40:03.063066	2024-07-15 02:40:03.063066
473	UnitedHealthOne	$134.64	2024-07-12	65	2024-07-15 02:40:03.067712	2024-07-15 02:40:03.067712
462	cafe intermezzo	$47.50	2024-07-07	63	2024-07-10 04:30:06.816435	2024-07-15 02:40:42.631678
474	Dekalb Co Water Bill	$75.93	2024-07-18	64	2024-07-20 03:00:55.784429	2024-07-20 03:00:55.784429
475	Henry Phone Bill	$26.50	2024-07-18	64	2024-07-20 03:00:55.79377	2024-07-20 03:00:55.79377
476	Scana Energy	$41.28	2024-07-17	64	2024-07-20 03:01:16.632751	2024-07-20 03:01:16.632751
477	QT Gas	$28.07	2024-07-19	62	2024-07-20 03:03:06.002503	2024-07-20 03:03:06.002503
478	E Dennis Jasper usa (AC/Heater)	$297.00	2024-07-19	61	2024-07-20 03:04:17.645372	2024-07-20 03:04:17.645372
479	AAREVARK ELECTRIC	$514.00	2024-07-19	61	2024-07-20 03:04:17.649176	2024-07-20 03:04:17.649176
480	SHERWIN WILLIAMS (PAINT)	$69.89	2024-07-18	61	2024-07-20 03:05:52.145294	2024-07-20 03:05:52.145294
481	WILLIAM SONOMA	$215.45	2024-07-18	88	2024-07-20 03:05:52.148623	2024-07-20 03:05:52.148623
482	Willy's	$13.36	2024-07-18	63	2024-07-20 03:06:14.334574	2024-07-20 03:06:14.334574
483	Farmer's Market	$71.18	2024-07-17	63	2024-07-20 04:29:58.722343	2024-07-20 04:29:58.722343
484	Lanier Parking (work)	$30.00	2024-07-17	62	2024-07-20 04:31:01.920796	2024-07-20 04:31:01.920796
485	Chickfila	$18.39	2024-07-17	63	2024-07-20 04:31:01.925418	2024-07-20 04:31:01.925418
486	Life Time	$16.42	2024-07-16	66	2024-07-20 04:32:14.496053	2024-07-20 04:32:14.496053
487	life cafe	$3.06	2024-07-16	63	2024-07-20 04:32:14.505181	2024-07-20 04:32:14.505181
488	Publix	$159.19	2024-07-16	63	2024-07-20 04:32:33.466458	2024-07-20 04:32:33.466458
471	Great SiChuan	$59.00	2024-07-14	63	2024-07-15 02:39:17.689072	2024-07-20 04:35:54.302942
489	Ming AT&T Phone	$42.50	2024-07-23	64	2024-07-25 00:03:29.566601	2024-07-25 00:03:29.566601
491	Emissions	$25.00	2024-07-24	62	2024-07-25 00:06:55.884453	2024-07-25 00:06:55.884453
492	Publix	$21.51	2024-07-24	63	2024-07-25 00:07:29.310713	2024-07-25 00:07:29.310713
493	Chickfila	$14.61	2024-07-24	63	2024-07-25 00:07:29.318901	2024-07-25 00:07:29.318901
494	Mattress Firm (pillow)	$343.99	2024-07-23	88	2024-07-25 00:09:20.72784	2024-07-25 00:09:20.72784
495	Target (Beddings)	$293.62	2024-07-23	88	2024-07-25 00:09:20.732043	2024-07-25 00:09:20.732043
496	Home Depot (cleaning mattress)	$40.99	2024-07-23	61	2024-07-25 00:09:20.735853	2024-07-25 00:09:20.735853
497	J bistro	$123.89	2024-07-22	63	2024-07-25 00:15:18.287008	2024-07-25 00:15:18.287008
498	Apple Bill	$2.99	2024-07-22	73	2024-07-25 00:15:18.293796	2024-07-25 00:15:18.293796
499	Home Depot 	$26.96	2024-07-22	72	2024-07-25 00:16:28.458732	2024-07-25 00:16:28.458732
500	Willy's	$26.61	2024-07-22	63	2024-07-25 00:17:17.517079	2024-07-25 00:17:17.517079
503	Amazon	$44.68	2024-07-21	88	2024-07-25 00:28:37.864182	2024-07-25 00:28:37.864182
504	GA Power Bill	$247.32	2024-07-30	64	2024-08-11 03:06:04.613038	2024-08-11 03:06:04.613038
505	Riot ez skin	$4.99	2024-08-10	72	2024-08-11 03:39:20.127032	2024-08-11 03:39:20.127032
506	Serious Tennis	$93.21	2024-08-10	66	2024-08-11 03:40:20.902851	2024-08-11 03:40:20.902851
507	Publix	$255.92	2024-08-10	63	2024-08-11 03:40:20.90937	2024-08-11 03:40:20.90937
508	SEA food Hall	$59.45	2024-08-09	69	2024-08-11 03:42:24.241109	2024-08-11 03:42:24.241109
509	AI Powered	$20.00	2024-08-09	87	2024-08-11 03:42:24.248182	2024-08-11 03:42:24.248182
510	wifi on board	$39.95	2024-08-09	69	2024-08-11 03:42:24.252901	2024-08-11 03:42:24.252901
511	Apple Bill	$2.99	2024-08-06	73	2024-08-11 03:43:38.356755	2024-08-11 03:43:38.356755
512	Apple Bill	$4.99	2024-08-06	73	2024-08-11 03:43:38.368728	2024-08-11 03:43:38.368728
513	Life Time	$50.76	2024-08-02	66	2024-08-11 03:46:01.475595	2024-08-11 03:46:01.475595
514	Spotify	$16.99	2024-08-01	73	2024-08-11 03:46:23.298513	2024-08-11 03:46:23.298513
515	AT&T Wifi	$65.30	2024-07-31	64	2024-08-11 03:47:09.910785	2024-08-11 03:47:09.910785
516	Luke's Lobster	$52.97	2024-07-29	69	2024-08-11 03:49:00.075914	2024-08-11 03:49:00.075914
517	Pike Place Chowder	$26.94	2024-07-29	69	2024-08-11 03:49:00.080383	2024-08-11 03:49:00.080383
518	Dekalb Co DMV	$29.60	2024-07-29	62	2024-08-11 03:49:57.790721	2024-08-11 03:49:57.790721
519	Henry Teeth	$101.40	2024-07-26	65	2024-08-11 03:50:42.491845	2024-08-11 03:50:42.491845
520	Quizlet.com	$35.99	2024-07-29	73	2024-08-11 03:57:35.141057	2024-08-11 03:57:35.141057
521	amazon (cusion)	$168.45	2024-07-22	69	2024-08-11 03:58:37.429828	2024-08-11 03:58:37.429828
522	Publix	$4.96	2024-08-10	63	2024-08-11 04:02:39.424293	2024-08-11 04:02:39.424293
523	Amazon (ming's dad cusion)	$80.04	2024-08-10	88	2024-08-11 04:02:39.4286	2024-08-11 04:02:39.4286
524	kroger	$51.80	2024-07-25	69	2024-08-11 04:03:24.648432	2024-08-11 04:03:24.648432
525	uber	$31.26	2024-08-09	69	2024-08-11 04:07:33.655646	2024-08-11 04:07:33.655646
526	uber	$156.33	2024-08-09	69	2024-08-11 04:07:33.660738	2024-08-11 04:07:33.660738
527	Render.com	$7.00	2024-08-01	73	2024-08-11 04:08:00.542625	2024-08-11 04:08:00.542625
528	uber	$104.53	2024-07-27	69	2024-08-11 04:09:56.804671	2024-08-11 04:09:56.804671
529	delta	$59.99	2024-07-27	69	2024-08-11 04:09:56.810734	2024-08-11 04:09:56.810734
530	delta	$59.99	2024-07-26	69	2024-08-11 04:12:00.989275	2024-08-11 04:12:00.989275
531	uber	$116.31	2024-07-26	69	2024-08-11 04:12:00.993432	2024-08-11 04:12:00.993432
532	uber	$87.99	2024-07-26	69	2024-08-11 04:12:00.997116	2024-08-11 04:12:00.997116
533	uber	$61.37	2024-07-26	69	2024-08-11 04:12:01.000725	2024-08-11 04:12:01.000725
534	delta	$24.99	2024-07-26	69	2024-08-11 04:12:01.073104	2024-08-11 04:12:01.073104
535	atl goldbergs	$17.18	2024-07-26	69	2024-08-11 04:12:01.078515	2024-08-11 04:12:01.078515
536	Farmer's Market	$44.27	2024-08-11	63	2024-08-11 20:23:45.927538	2024-08-11 20:23:45.927538
537	H Mart	$267.00	2024-08-11	63	2024-08-11 20:23:45.994368	2024-08-11 20:23:45.994368
538	Water Bill	$51.36	2024-08-15	64	2024-08-15 11:44:07.2248	2024-08-15 11:44:07.2248
540	Amazon	$53.99	2024-08-14	88	2024-08-15 11:47:55.382673	2024-08-15 11:47:55.382673
541	Publix	$82.95	2024-08-14	63	2024-08-15 11:48:52.916489	2024-08-15 11:48:52.916489
542	UnitedHealthOne	$134.64	2024-08-14	65	2024-08-15 11:50:01.702296	2024-08-15 11:50:01.702296
543	Scana Energy	$41.27	2024-08-16	64	2024-08-16 11:42:02.207227	2024-08-16 11:42:02.207227
544	amazon	$58.29	2024-08-16	88	2024-08-16 11:44:02.402204	2024-08-16 11:44:02.402204
545	Henry Phone Bill	$26.50	2024-08-16	64	2024-08-19 12:22:36.128415	2024-08-19 12:22:36.128415
546	Home Depot (Truck Rental)	$20.52	2024-08-18	61	2024-08-19 12:29:57.957967	2024-08-19 12:29:57.957967
547	Estate Sale (Dresser)	$448.67	2024-08-18	61	2024-08-19 12:29:58.015016	2024-08-19 12:29:58.015016
548	Willy's	$49.13	2024-08-18	63	2024-08-19 12:29:58.019891	2024-08-19 12:29:58.019891
549	76 Gas	$28.82	2024-08-18	62	2024-08-19 12:29:58.025898	2024-08-19 12:29:58.025898
550	Amazon	$131.74	2024-08-17	88	2024-08-19 13:47:20.51078	2024-08-19 13:47:20.51078
551	Amazon	$57.62	2024-08-17	88	2024-08-19 13:47:20.527828	2024-08-19 13:47:20.527828
552	Farmer's Market	$184.58	2024-08-18	63	2024-08-19 13:48:22.304415	2024-08-19 13:48:22.304415
553	Publix	$204.81	2024-08-18	63	2024-08-19 13:48:22.31088	2024-08-19 13:48:22.31088
554	Amazon	$80.04	2024-08-18	88	2024-08-19 13:48:40.23354	2024-08-19 13:48:40.23354
539	Sephora (Eye cream)	$77.76	2024-08-15	89	2024-08-15 11:46:26.050132	2024-08-20 01:07:02.628764
557	Amazon (Water preolic)	$32.37	2024-08-19	61	2024-08-20 01:11:13.951496	2024-08-20 01:11:13.951496
558	Apple Bill	$2.99	2024-08-21	73	2024-08-21 23:10:20.958101	2024-08-21 23:10:20.958101
559	All State Health Solution(Mom&Dad)	$522.61	2024-08-19	65	2024-08-21 23:19:12.517335	2024-08-21 23:19:12.517335
560	Toyota Rav4	$44,403.00	2024-08-23	62	2024-08-24 02:58:52.284981	2024-08-24 02:58:52.284981
561	Ming's phone bill	$42.50	2024-08-22	64	2024-08-24 03:00:34.367634	2024-08-24 03:00:34.367634
562	Chevron	$28.70	2024-08-23	62	2024-08-24 03:03:17.851561	2024-08-24 03:03:17.851561
563	stern Law (Visa Extension)	$3,000.00	2024-08-23	72	2024-08-24 03:04:07.422992	2024-08-24 03:04:07.422992
564	Publix	$121.19	2024-08-22	63	2024-08-24 03:06:44.184851	2024-08-24 03:06:44.184851
565	Amazon	$32.37	2024-08-20	88	2024-08-24 03:07:11.422808	2024-08-24 03:07:11.422808
566	Mortgage	$2,200.00	2024-08-23	61	2024-08-24 03:10:04.951094	2024-08-24 03:10:04.951094
567	Amazon	$19.17	2024-08-23	88	2024-08-24 03:15:17.387774	2024-08-24 03:15:17.387774
568	Amazon	$28.07	2024-08-23	88	2024-08-24 03:15:51.700986	2024-08-24 03:15:51.700986
569	Amazon	$19.17	2024-08-23	88	2024-08-24 03:16:08.959963	2024-08-24 03:16:08.959963
570	WuKong Game Steam	$75.59	2024-08-24	72	2024-08-25 19:17:22.313637	2024-08-25 19:17:22.313637
571	micro center marietta	$3,403.63	2024-08-24	61	2024-08-25 19:17:22.324871	2024-08-25 19:17:22.324871
572	Progressive Insurance	$730.47	2024-08-24	62	2024-08-25 19:17:22.333356	2024-08-25 19:17:22.333356
573	Amazon	$10.79	2024-08-25	88	2024-08-25 19:19:38.344373	2024-08-25 19:19:38.344373
574	Amazon	$39.95	2024-08-25	88	2024-08-25 19:19:38.353316	2024-08-25 19:19:38.353316
575	Amazon	$52.87	2024-08-25	88	2024-08-25 19:19:38.365225	2024-08-25 19:19:38.365225
576	Amazon	$17.27	2024-08-25	88	2024-08-25 19:19:38.373635	2024-08-25 19:19:38.373635
577	Amazon	$17.27	2024-08-25	88	2024-08-26 01:48:39.631572	2024-08-26 01:48:39.631572
578	Amazon	$70.18	2024-08-25	88	2024-08-26 01:48:39.638539	2024-08-26 01:48:39.638539
579	Farmer's Market	$181.00	2024-08-25	63	2024-08-26 01:51:35.913015	2024-08-26 01:51:35.913015
582	HOA	$265.12	2024-08-26	61	2024-08-30 03:17:18.567724	2024-08-30 03:17:18.567724
583	ALLSTATEHEALTHSOLUTION	$104.05	2024-08-29	65	2024-08-30 03:22:31.855424	2024-08-30 03:22:31.855424
584	Amazon	$58.31	2024-08-29	88	2024-08-30 03:23:19.913493	2024-08-30 03:23:19.913493
585	Amazon	$25.84	2024-08-29	88	2024-08-30 03:24:03.436097	2024-08-30 03:24:03.436097
586	Farmer's Market	$38.40	2024-08-28	63	2024-08-30 03:25:00.981955	2024-08-30 03:25:00.981955
580	Ten Sec	$71.29	2024-08-24	63	2024-08-26 01:56:23.30667	2024-08-30 03:25:39.967898
581	GA Power Bill	$129.01	2024-08-28	64	2024-08-30 03:16:37.358451	2024-08-31 01:14:00.325265
587	Mortgage	$2,200.00	2024-09-01	61	2024-08-31 01:17:04.793334	2024-08-31 01:17:04.793334
588	Amazon	$16.19	2024-08-30	88	2024-08-31 01:23:31.193217	2024-08-31 01:23:31.193217
589	Amazon	$26.98	2024-08-30	88	2024-08-31 01:23:31.198876	2024-08-31 01:23:31.198876
590	Whole Food	$24.72	2024-08-30	63	2024-08-31 01:29:57.330443	2024-08-31 01:29:57.330443
591	Hmart	$192.49	2024-09-01	63	2024-09-02 01:43:08.911597	2024-09-02 01:43:08.911597
592	Publix	$195.15	2024-08-31	63	2024-09-02 01:44:37.938565	2024-09-02 01:44:37.938565
593	Life Time	$234.73	2024-09-01	66	2024-09-02 01:49:22.774084	2024-09-02 01:49:22.774084
594	Apple Bill	$4.99	2024-09-01	73	2024-09-02 01:49:22.77833	2024-09-02 01:49:22.77833
595	Spotify	$16.99	2024-09-01	73	2024-09-02 01:49:22.782075	2024-09-02 01:49:22.782075
596	parking at ponce	$13.60	2024-08-31	62	2024-09-02 01:49:52.808098	2024-09-02 01:49:52.808098
598	Chickfila	$28.87	2024-08-31	63	2024-09-02 01:50:47.871829	2024-09-02 01:50:47.871829
599	AT&T Wifi	$65.30	2024-08-31	64	2024-09-02 01:51:33.923541	2024-09-02 01:51:33.923541
600	Amazon	$14.03	2024-08-31	88	2024-09-02 01:52:48.065016	2024-09-02 01:52:48.065016
602	Render.com	$7.00	2024-09-01	73	2024-09-02 01:54:03.272035	2024-09-02 01:54:03.272035
603	QT Gas	$22.24	2024-09-03	62	2024-09-04 02:21:59.301668	2024-09-04 02:21:59.301668
604	Bubble cafe	$17.83	2024-09-02	63	2024-09-04 02:22:32.752375	2024-09-04 02:22:32.752375
605	UGA Bookstore	$28.08	2024-09-02	71	2024-09-04 02:24:17.991716	2024-09-04 02:24:17.991716
601	Chewy	$121.02	2024-08-31	70	2024-09-02 01:52:48.069274	2024-09-04 02:25:38.325155
606	Amazon	$13.56	2024-09-02	88	2024-09-04 02:25:59.801294	2024-09-04 02:25:59.801294
607	Mortgage (9/4)	$2,375.32	2024-10-01	61	2024-09-04 12:11:47.62293	2024-09-04 12:11:47.62293
608	Willy's	$13.25	2024-09-04	63	2024-09-05 13:43:26.912743	2024-09-05 13:43:26.912743
609	Mortgage (9/6)	$2,200.00	2024-11-01	61	2024-09-06 12:13:39.905609	2024-09-06 12:13:39.905609
610	HOA	$122.95	2024-09-05	61	2024-09-06 12:25:47.40367	2024-09-06 12:25:47.40367
611	Amazon ( Computer case)	$232.19	2024-09-05	88	2024-09-06 12:28:02.913308	2024-09-06 12:28:02.913308
612	Target (Ming Dad clothes)	$111.88	2024-09-05	71	2024-09-06 12:36:39.543865	2024-09-06 12:36:39.543865
613	Micro center	$31.79	2024-09-07	88	2024-09-09 18:57:36.360865	2024-09-09 18:57:36.360865
614	Sephora (serum)	$145.80	2024-09-06	89	2024-09-09 18:58:52.81811	2024-09-09 18:58:52.81811
615	Farmer's Market	$238.58	2024-09-08	63	2024-09-09 18:59:49.331358	2024-09-09 18:59:49.331358
616	Estate Sale (Flower pot and two plants)	$20.00	2024-09-08	72	2024-09-09 19:00:37.664333	2024-09-09 19:00:37.664333
617	AI POWERED IDE	$20.00	2024-09-10	73	2024-09-12 12:25:54.034055	2024-09-12 12:25:54.034055
618	Amazon ( Vacuum)	$539.99	2024-09-11	88	2024-09-12 12:26:49.840764	2024-09-12 12:26:49.840764
619	UnitedHealthOne	$134.64	2024-09-11	65	2024-09-12 12:29:35.880371	2024-09-12 12:29:35.880371
620	brainscape pro	$19.99	2024-09-12	87	2024-09-13 12:21:15.908967	2024-09-13 12:21:15.908967
621	Scana Energy	$37.08	2024-09-16	64	2024-09-17 13:51:47.423703	2024-09-17 13:51:47.423703
622	Water Bill	$54.36	2024-09-16	64	2024-09-17 13:51:47.428053	2024-09-17 13:51:47.428053
623	Ming Parents Health Insurance	$472.61	2024-09-16	65	2024-09-17 13:53:31.803855	2024-09-17 13:53:31.803855
624	Henry Phone Bill	$26.50	2024-09-16	64	2024-09-17 13:53:59.097853	2024-09-17 13:53:59.097853
625	CVS (Ming mom eye med)	$20.00	2024-09-16	65	2024-09-17 13:55:16.819811	2024-09-17 13:55:16.819811
626	Ming Car Maintance	$179.91	2024-09-16	62	2024-09-17 13:55:16.824829	2024-09-17 13:55:16.824829
627	CLARB Transcript	$75.00	2024-09-16	87	2024-09-17 13:55:16.828692	2024-09-17 13:55:16.828692
628	Battle & Brew	$124.66	2024-09-14	63	2024-09-17 13:55:55.451748	2024-09-17 13:55:55.451748
629	Hmart	$174.27	2024-09-14	63	2024-09-17 13:56:45.909476	2024-09-17 13:56:45.909476
630	Chevron	$35.36	2024-09-14	62	2024-09-17 13:56:45.914147	2024-09-17 13:56:45.914147
631	Bee's knees estatesale	$196.29	2024-09-14	72	2024-09-17 13:57:13.577857	2024-09-17 13:57:13.577857
632	Chevron	$24.14	2024-09-14	62	2024-09-17 13:57:49.569543	2024-09-17 13:57:49.569543
634	Amazon ( Dad diaper)	$90.70	2024-09-15	88	2024-09-17 13:59:43.015103	2024-09-17 14:00:18.094628
635	Amazon ( Kitchen liner)	$53.06	2024-09-15	88	2024-09-17 13:59:43.057691	2024-09-17 14:01:22.561695
633	Amazon ( Henry Chips)	$29.60	2024-09-15	88	2024-09-17 13:59:43.010681	2024-09-17 14:01:09.472068
636	CVS	$7.41	2024-09-16	63	2024-09-17 14:02:19.237776	2024-09-17 14:02:19.237776
637	Publix	$10.87	2024-09-15	63	2024-09-17 14:02:56.376114	2024-09-17 14:02:56.376114
638	Farmer's Market	$17.04	2024-09-15	63	2024-09-17 14:02:56.380021	2024-09-17 14:02:56.380021
640	Publix	$101.75	2024-09-13	63	2024-09-17 14:04:33.915429	2024-09-17 14:04:33.915429
641	Parking dt atlanta	$4.00	2024-09-18	62	2024-09-18 11:50:35.424391	2024-09-18 11:50:35.424391
642	Chickfila	$9.12	2024-09-17	63	2024-09-18 11:52:20.190599	2024-09-18 11:52:20.190599
644	ncourt ( Traffic tickets)	$300.56	2024-09-18	62	2024-09-19 14:38:52.970304	2024-09-19 14:38:52.970304
645	Apple Bill	$2.99	2024-09-21	73	2024-09-21 20:22:20.90274	2024-09-21 20:22:20.90274
646	Hmart	$99.64	2024-09-20	63	2024-09-21 20:23:05.363	2024-09-21 20:23:05.363
647	Costco	$200.09	2024-09-20	63	2024-09-21 20:23:05.371091	2024-09-21 20:23:05.371091
643	Parking dw atlanta	$11.00	2024-09-18	62	2024-09-19 14:38:52.962767	2024-09-21 20:23:18.235347
648	Amazon prime	$16.19	2024-09-20	73	2024-09-21 20:24:38.455313	2024-09-21 20:24:38.455313
649	Amazon	$24.17	2024-09-21	88	2024-09-21 20:25:18.582808	2024-09-21 20:25:18.582808
650	Amazon	$134.99	2024-09-21	88	2024-09-21 20:25:18.589737	2024-09-21 20:25:18.589737
651	smoothie king	$8.13	2024-09-20	63	2024-09-21 20:26:26.104465	2024-09-21 20:26:26.104465
652	Ming AT&T Phone	$42.50	2024-09-23	64	2024-09-23 22:38:34.549402	2024-09-23 22:38:34.549402
653	Chevron	$26.53	2024-09-23	62	2024-09-23 22:39:35.267907	2024-09-23 22:39:35.267907
655	Amazon (Crab cage)	$46.42	2024-09-21	88	2024-09-23 22:42:09.796119	2024-09-23 22:42:09.796119
657	airbnb st simmon	$979.26	2024-09-22	69	2024-09-23 22:46:45.03504	2024-09-23 22:46:45.03504
656	Chevron	$4.44	2024-09-23	62	2024-09-23 22:45:47.132621	2024-09-26 12:07:32.594119
658	GW BBQ Inc	$56.77	2024-09-26	63	2024-09-27 15:12:41.092266	2024-09-27 15:12:41.092266
659	Farmer's market	$180.28	2024-09-26	63	2024-09-27 15:13:04.985885	2024-09-27 15:13:04.985885
660	Power Bill	$238.48	2024-09-30	64	2024-09-30 11:45:26.815275	2024-09-30 11:45:26.815275
661	estate sale	$41.04	2024-09-28	88	2024-09-30 11:47:33.183832	2024-09-30 11:47:33.183832
662	estate sale	$32.70	2024-09-28	88	2024-09-30 11:49:49.621187	2024-09-30 11:49:49.621187
663	AllStateHealthSolution	$104.05	2024-09-30	65	2024-09-30 11:51:00.119343	2024-09-30 11:51:00.119343
664	Pizza Hut	$21.43	2024-09-28	63	2024-09-30 11:56:22.206092	2024-09-30 11:56:22.206092
665	Hmart	$108.26	2024-09-30	63	2024-10-01 01:52:52.127685	2024-10-01 01:52:52.127685
666	Nayax Parking	$6.00	2024-09-30	65	2024-10-01 01:52:52.136809	2024-10-01 01:52:52.136809
667	AT&T Wifi	$65.30	2024-09-30	64	2024-10-01 01:53:18.043116	2024-10-01 01:53:18.043116
668	Spotify	$16.99	2024-10-01	73	2024-10-01 11:07:52.178365	2024-10-01 11:07:52.178365
669	Life Time	$93.21	2024-10-02	66	2024-10-03 02:18:45.659276	2024-10-03 02:18:45.659276
670	Apple Bill	$3.92	2024-10-02	73	2024-10-03 02:18:45.667033	2024-10-03 02:19:47.74959
671	Render.com	$7.00	2024-10-02	73	2024-10-03 02:23:50.928289	2024-10-03 02:23:50.928289
672	Publix	$323.62	2024-10-04	63	2024-10-05 01:50:49.223628	2024-10-05 01:50:49.223628
673	Chevron	$20.97	2024-10-04	62	2024-10-05 01:50:49.246928	2024-10-05 01:50:49.246928
675	Mortgage (10/3)	$1,950.00	2024-12-01	61	2024-10-08 12:17:15.426926	2024-10-08 12:17:15.426926
676	Mortgage(10/4)	$1,950.00	2025-01-01	61	2024-10-08 12:18:12.394175	2024-10-08 12:18:12.394175
677	Mortgage(10/8)	$1,900.00	2025-02-01	61	2024-10-08 12:21:25.283386	2024-10-08 12:21:25.283386
678	HOA	$122.95	2024-10-07	61	2024-10-08 12:22:54.854803	2024-10-08 12:22:54.854803
679	Hmart	$116.21	2024-10-07	63	2024-10-08 12:26:54.489452	2024-10-08 12:26:54.489452
680	Amazon 	$39.20	2024-10-06	88	2024-10-08 12:28:51.673546	2024-10-08 12:28:51.673546
681	Revolving SUS	$72.22	2024-10-05	63	2024-10-08 12:29:56.766811	2024-10-08 12:29:56.766811
682	CURSOR	$20.00	2024-10-09	73	2024-10-10 00:31:34.388767	2024-10-10 00:31:34.388767
683	MEDREHABILITATION	$120.00	2024-10-09	65	2024-10-10 00:31:34.397115	2024-10-10 00:31:34.397115
685	Apple Bill	$4.99	2024-10-15	73	2024-10-16 02:13:00.046293	2024-10-16 02:13:00.046293
686	Hmart	$102.65	2024-10-15	63	2024-10-16 02:13:00.06176	2024-10-16 02:13:00.06176
688	Ming GA Test	$85.00	2024-10-14	87	2024-10-16 02:13:55.779375	2024-10-16 02:13:55.779375
689	PILOT	$30.86	2024-10-14	62	2024-10-16 02:13:55.78814	2024-10-16 02:13:55.78814
690	CVS	$81.69	2024-10-13	69	2024-10-16 02:16:08.721794	2024-10-16 02:16:08.721794
691	ST SIMONS BAIT AND TACKL	$7.84	2024-10-13	69	2024-10-16 02:16:08.731779	2024-10-16 02:16:08.731779
692	RACETRAC	$24.15	2024-10-13	69	2024-10-16 02:16:08.74104	2024-10-16 02:16:08.74104
693	WINN-DIXIE	$6.11	2024-10-13	69	2024-10-16 02:16:08.752921	2024-10-16 02:16:08.752921
694	HARRIS TEETER	$16.28	2024-10-12	69	2024-10-16 02:17:19.466098	2024-10-16 02:17:19.466098
695	ST SIMONS BAIT AND TACKL	$5.52	2024-10-12	69	2024-10-16 02:17:19.504916	2024-10-16 02:17:19.504916
696	Farmer's market	$27.58	2024-10-10	63	2024-10-16 02:19:30.16462	2024-10-16 02:19:30.16462
697	Farmer's market	$4.93	2024-10-10	63	2024-10-16 02:19:30.172355	2024-10-16 02:19:30.172355
698	GA go outdoors	$36.00	2024-10-10	69	2024-10-16 02:19:30.179835	2024-10-16 02:19:30.179835
699	eye consultants	$344.78	2024-10-09	65	2024-10-16 02:20:40.106057	2024-10-16 02:20:40.106057
700	brainscape pro	$19.99	2024-10-14	87	2024-10-16 02:21:53.468183	2024-10-16 02:21:53.468183
701	tst collins quarter	$89.66	2024-10-14	63	2024-10-16 02:23:27.512905	2024-10-16 02:23:27.512905
702	Willy's	$10.87	2024-10-15	63	2024-10-16 02:24:25.541016	2024-10-16 02:24:25.541016
703	UnitedHealthOne	$134.64	2024-10-12	65	2024-10-16 02:25:02.404911	2024-10-16 02:25:02.404911
704	tst the half shell	$203.88	2024-10-11	69	2024-10-16 02:25:44.661104	2024-10-16 02:25:44.661104
705	Scana Energy	$43.89	2024-10-16	64	2024-10-16 14:06:57.15146	2024-10-16 14:06:57.15146
706	Amazon (Photo Printer)	$34.55	2024-10-15	88	2024-10-16 14:09:58.15924	2024-10-16 14:09:58.15924
707	Water Bill	$96.44	2024-10-17	64	2024-10-17 12:26:24.011393	2024-10-17 12:26:24.011393
708	Allstate health solution	$453.11	2024-10-17	65	2024-10-17 12:27:15.854425	2024-10-17 12:27:15.854425
709	Henry Phone Bill	$26.50	2024-10-17	64	2024-10-17 12:27:40.553831	2024-10-17 12:27:40.553831
710	Chevron	$23.48	2024-10-17	62	2024-10-18 12:22:46.312307	2024-10-18 12:22:46.312307
711	Mortgage(10/20)	$1,950.00	2025-03-01	61	2024-10-21 02:53:55.765127	2024-10-21 02:53:55.765127
712	Ming AT&T Phone	$42.50	2024-10-21	64	2024-10-22 03:00:33.693483	2024-10-22 03:00:33.693483
713	Eye Consultants of ALT	$152.93	2024-10-21	65	2024-10-22 03:01:59.822747	2024-10-22 03:01:59.822747
715	Buford Highway Farmers	$180.20	2024-10-19	63	2024-10-22 03:03:08.445094	2024-10-22 03:03:08.445094
716	Publix	$149.30	2024-10-19	63	2024-10-22 03:03:45.723079	2024-10-22 03:03:45.723079
717	estate sale	$19.63	2024-10-19	88	2024-10-22 03:04:13.38358	2024-10-22 03:04:13.38358
718	Amazon prime	$16.19	2024-10-21	73	2024-10-22 03:05:35.118606	2024-10-22 03:05:35.118606
719	Chickfila	$15.63	2024-10-19	63	2024-10-22 03:05:56.786448	2024-10-22 03:05:56.786448
720	Amazon	$20.51	2024-10-19	88	2024-10-22 03:07:32.971368	2024-10-22 03:07:32.971368
721	united digestive	$13.62	2024-10-19	65	2024-10-22 03:09:49.714332	2024-10-22 03:09:49.714332
722	Mom Glasses	$525.00	2024-10-24	65	2024-10-25 12:20:38.432688	2024-10-25 12:20:38.432688
714	Apple Bill	$2.99	2024-10-21	73	2024-10-22 03:01:59.834673	2024-10-25 12:21:23.15838
723	Chickfila	$12.61	2024-10-24	63	2024-10-25 12:27:53.658502	2024-10-25 12:27:53.658502
724	Amazon (the boys)	$2.99	2024-10-24	73	2024-10-25 12:27:53.66701	2024-10-25 12:27:53.66701
725	Farmer's	$97.69	2024-10-26	63	2024-10-27 01:57:40.248418	2024-10-27 01:57:40.248418
726	Publix	$135.42	2024-10-26	63	2024-10-27 01:57:40.260974	2024-10-27 01:57:40.260974
727	open AI	$5.00	2024-10-26	87	2024-10-27 01:57:40.350595	2024-10-27 01:57:40.350595
728	Chickfila	$19.08	2024-10-26	63	2024-10-27 01:58:59.230412	2024-10-27 01:58:59.230412
729	Chickfila	$12.61	2024-10-26	63	2024-10-27 01:58:59.305253	2024-10-27 01:58:59.305253
730	AllStateHealthSolution	$104.05	2024-10-27	65	2024-10-28 13:31:56.923419	2024-10-28 13:31:56.923419
731	Willy's	$14.68	2024-10-27	63	2024-10-28 13:33:43.772661	2024-10-28 13:33:43.772661
732	Chevron	$22.31	2024-10-29	62	2024-10-30 00:14:08.676608	2024-10-30 00:14:08.676608
733	Power Bill	$154.74	2024-10-30	64	2024-10-31 12:57:53.018239	2024-10-31 12:57:53.018239
734	Farmer's Market	$150.67	2024-10-30	63	2024-10-31 12:58:40.441422	2024-10-31 12:58:40.441422
735	Spotify	$16.99	2024-11-01	73	2024-11-01 12:18:29.351427	2024-11-01 12:18:29.351427
736	ATT Wifi	$65.30	2024-11-01	64	2024-11-01 12:18:29.357218	2024-11-01 12:18:29.357218
737	Mortgage (11/1)	$1,900.00	2025-04-01	61	2024-11-01 12:43:07.195229	2024-11-01 12:43:07.195229
738	Render.com	$7.00	2024-11-01	73	2024-11-01 18:44:05.331209	2024-11-01 18:44:05.331209
739	National parking( office lunch, expense)	$5.50	2024-11-01	62	2024-11-01 18:44:39.792489	2024-11-01 18:44:39.792489
740	Amazon ( xmas Present Henry mom)	$150.12	2024-11-01	72	2024-11-01 18:45:24.410378	2024-11-01 18:45:24.410378
741	Chickfila	$12.61	2024-11-01	63	2024-11-01 18:46:16.830825	2024-11-01 18:46:16.830825
742	Life Time	$15.38	2024-11-01	66	2024-11-01 18:46:35.473516	2024-11-01 18:46:35.473516
39	Kroger	$54.69	2024-01-10	89	2024-01-11 03:15:41.718086	2024-01-11 03:15:41.718086
103	Amazon	$14.04	2024-02-17	89	2024-02-20 02:03:36.806017	2024-02-20 02:03:36.806017
104	Amazon	$35.63	2024-02-17	89	2024-02-20 02:03:36.810603	2024-02-20 02:03:36.810603
121	amazon (Chopsticks)	$12.94	2024-02-24	89	2024-02-26 02:34:54.044821	2024-02-26 02:34:54.044821
129	Walmart	$80.95	2024-02-28	89	2024-03-01 15:23:21.622625	2024-03-01 15:23:21.622625
132	CVS (Mouth Gard)	$127.72	2024-03-03	89	2024-03-04 22:21:39.969555	2024-03-04 22:21:39.969555
176	Home Depot (Toliet Paper)	$85.02	2024-03-22	89	2024-03-25 00:35:54.970827	2024-03-25 00:35:54.970827
218	Kroger	$152.81	2024-04-05	89	2024-04-08 12:22:42.273178	2024-04-08 12:22:42.273178
288	Target (Kitchen towel)	$41.04	2024-05-05	89	2024-05-06 12:26:07.292156	2024-05-06 12:26:07.292156
331	Home Depot (kitchen cleaning)	$13.00	2024-05-25	89	2024-05-30 12:38:51.908796	2024-05-30 12:38:51.908796
390	Henry Hair cut	$31.05	2024-06-17	89	2024-06-18 12:42:20.250594	2024-06-18 12:42:20.250594
555	Walmart	$14.95	2024-08-19	89	2024-08-20 01:04:56.209545	2024-08-20 01:04:56.209545
556	Amazon (Diaper dad)	$19.43	2024-08-19	89	2024-08-20 01:08:02.528361	2024-08-20 01:08:02.528361
597	Home Depot (Shower drain)	$39.38	2024-08-31	89	2024-09-02 01:50:29.589813	2024-09-02 01:50:29.589813
639	CVS (Mouth Gard, Eye wipe)	$92.71	2024-09-13	89	2024-09-17 14:03:56.025929	2024-09-17 14:03:56.025929
674	Amazon	$21.82	2024-10-04	89	2024-10-05 02:07:10.289256	2024-10-05 02:07:10.289256
684	Henry Hair cut Tip	$10.00	2024-10-15	89	2024-10-16 02:09:48.711036	2024-10-16 02:09:48.711036
687	Henry Hair cut	$31.05	2024-10-15	89	2024-10-16 02:13:00.067137	2024-10-16 14:07:53.950441
743	Costco	$268.67	2024-11-03	63	2024-11-03 19:32:14.536921	2024-11-03 19:32:14.536921
744	Hmart	$51.57	2024-11-03	63	2024-11-03 19:33:23.347995	2024-11-03 19:33:23.347995
745	Revolving sus	$48.14	2024-11-03	63	2024-11-03 19:36:11.952197	2024-11-03 19:36:11.952197
746	Mortgage (11/5)	$2,000.00	2025-05-01	61	2024-11-05 13:20:13.236667	2024-11-05 13:20:13.236667
747	Apple Bill	$4.99	2024-11-05	73	2024-11-05 13:22:52.85309	2024-11-05 13:22:52.85309
748	HOA	$122.95	2024-11-05	61	2024-11-05 17:58:32.690861	2024-11-05 17:58:32.690861
749	USPS(medical bill)	$0.73	2024-11-06	65	2024-11-06 17:44:12.710326	2024-11-06 17:44:12.710326
750	Chevron	$21.64	2024-11-05	62	2024-11-06 17:44:53.408472	2024-11-06 17:44:53.408472
751	Chevron	$36.10	2024-11-05	62	2024-11-06 17:44:53.411569	2024-11-06 17:44:53.411569
753	Open Router, llc	$5.66	2024-11-05	87	2024-11-06 17:52:02.040605	2024-11-06 17:52:02.040605
754	Comcast cable	$25.00	2024-11-07	64	2024-11-07 13:48:54.113379	2024-11-07 13:48:54.113379
755	Farmer's	$91.69	2024-11-07	63	2024-11-08 01:05:44.264882	2024-11-08 01:05:44.264882
756	License registration 	$80.00	2024-11-08	87	2024-11-11 12:53:09.206808	2024-11-11 12:53:09.206808
757	Great Wall	$65.30	2024-11-10	63	2024-11-11 12:53:44.230267	2024-11-11 12:53:44.230267
758	Cursor, AI Powered	$20.00	2024-11-10	73	2024-11-11 12:54:18.674553	2024-11-11 12:54:18.674553
759	Chickfila	$19.22	2024-11-09	63	2024-11-11 12:54:40.852387	2024-11-11 12:54:40.852387
760	Parking at BOA	$5.00	2024-11-08	62	2024-11-11 12:55:00.287194	2024-11-11 12:55:00.287194
761	USPS	$5.58	2024-11-08	87	2024-11-11 12:55:27.485169	2024-11-11 12:55:27.485169
763	Amazon (Dad diaper & support seat)	$144.69	2024-11-10	72	2024-11-11 12:59:53.095157	2024-11-11 12:59:53.095157
764	GW BBQ Inc	$45.86	2024-11-10	63	2024-11-11 13:01:02.846771	2024-11-11 13:01:02.846771
767	Amazon( Dad PT Belt)	$19.38	2024-11-12	88	2024-11-13 18:34:37.719405	2024-11-13 18:34:37.719405
768	UnitedHealthOne	$134.64	2024-11-12	65	2024-11-13 18:36:45.363695	2024-11-13 18:36:45.363695
769	Scana Energy	$41.84	2024-11-14	64	2024-11-14 13:20:38.858431	2024-11-14 13:20:38.858431
770	Water Bill	$72.87	2024-11-14	64	2024-11-14 13:20:38.862388	2024-11-14 13:20:38.862388
771	Chickfila	$19.22	2024-11-13	63	2024-11-14 13:21:42.386726	2024-11-14 13:21:42.386726
765	Jinya Ramen	$66.75	2024-11-09	63	2024-11-11 13:01:26.825346	2024-11-14 13:23:30.11956
772	Estate Sale (Sofa)	$210.00	2024-11-16	72	2024-11-16 23:14:58.209449	2024-11-16 23:14:58.209449
773	Chickfila	$12.61	2024-11-15	63	2024-11-16 23:22:43.348335	2024-11-16 23:22:43.348335
774	Farmer's Market	$193.04	2024-11-14	63	2024-11-16 23:24:45.336359	2024-11-16 23:24:45.336359
775	Chewy	$64.22	2024-11-16	70	2024-11-16 23:28:08.419274	2024-11-16 23:28:08.419274
776	Williams Sonoma	$123.06	2024-11-16	72	2024-11-16 23:29:04.281578	2024-11-16 23:29:04.281578
777	Williams Sonoma	$161.95	2024-11-16	72	2024-11-16 23:29:04.285926	2024-11-16 23:29:04.285926
778	Amazon (Walker)	$83.58	2024-11-16	72	2024-11-16 23:32:32.393434	2024-11-16 23:32:32.393434
779	Willy's	$14.68	2024-11-14	63	2024-11-16 23:35:10.374551	2024-11-16 23:35:10.374551
766	CITGO	$20.82	2024-11-13	62	2024-11-13 18:33:54.759355	2024-11-16 23:36:37.407366
780	Mortgage (11/16)	$1,900.00	2025-06-01	61	2024-11-18 02:36:09.015534	2024-11-18 02:36:09.015534
781	Neurocare Center of At	$310.00	2024-11-18	65	2024-11-18 14:56:40.661094	2024-11-18 14:56:40.661094
782	Publix	$264.55	2024-11-17	63	2024-11-18 14:57:05.323846	2024-11-18 14:57:05.323846
783	AllStateHealthSolution	$453.11	2024-11-17	65	2024-11-18 14:57:53.811323	2024-11-18 14:57:53.811323
784	Henry Phone Bill	$26.50	2024-11-17	64	2024-11-18 14:57:53.817376	2024-11-18 14:57:53.817376
785	Supercellstore	$0.99	2024-11-18	88	2024-11-18 15:10:30.771665	2024-11-18 15:10:30.771665
786	Ming AT&T Phone	$42.50	2024-11-20	64	2024-11-20 14:34:49.317245	2024-11-20 14:34:49.317245
787	Farmer's	$124.65	2024-11-19	63	2024-11-20 14:36:13.966274	2024-11-20 14:36:13.966274
788	Kroger (Ming Pills)	$34.83	2024-11-19	65	2024-11-20 14:37:10.103881	2024-11-20 14:37:10.103881
789	Kroger	$52.82	2024-11-19	63	2024-11-20 14:37:24.344457	2024-11-20 14:37:24.344457
790	Ritual	$75.16	2024-11-19	63	2024-11-20 14:47:09.595459	2024-11-20 14:47:09.595459
791	Health E medical Center (Henry)	$262.53	2024-11-22	65	2024-11-22 16:36:58.828075	2024-11-22 16:36:58.828075
792	Costco	$242.32	2024-11-21	63	2024-11-22 16:37:14.07014	2024-11-22 16:37:14.07014
793	Chevron	$22.02	2024-11-21	62	2024-11-22 16:37:31.539227	2024-11-22 16:37:31.539227
794	Apple Bill	$2.99	2024-11-21	73	2024-11-22 16:37:51.077468	2024-11-22 16:37:51.077468
795	Amazon	$13.27	2024-11-20	88	2024-11-22 16:40:33.025855	2024-11-22 16:40:33.025855
796	Amazon	$8.63	2024-11-20	88	2024-11-22 16:40:33.028698	2024-11-22 16:40:33.028698
797	Hmart	$260.50	2024-11-23	63	2024-11-25 14:06:32.239772	2024-11-25 14:06:32.239772
798	CVS (Dad medicine)	$13.81	2024-11-23	65	2024-11-25 14:06:32.243187	2024-11-25 14:06:32.243187
799	CVS (Dad medicine)	$26.95	2024-11-23	65	2024-11-25 14:06:32.246239	2024-11-25 14:06:32.246239
800	Car wash (WHISTLE EXPRESS)	$16.00	2024-11-23	62	2024-11-25 14:06:32.248904	2024-11-25 14:06:32.248904
801	Sephora (Eye cream)	$38.88	2024-11-25	88	2024-11-25 14:07:13.670229	2024-11-25 14:07:13.670229
802	Chickfila	$12.61	2024-11-26	63	2024-11-26 18:05:25.840261	2024-11-26 18:05:25.840261
803	Kroger (Mom Hair )	$14.15	2024-11-25	88	2024-11-26 18:06:01.318647	2024-11-26 18:06:01.318647
804	Shell	$25.16	2024-11-28	62	2024-11-29 03:49:09.19507	2024-11-29 03:49:09.19507
805	AllStateHealthSolution	$104.05	2024-11-28	65	2024-11-29 03:49:09.197715	2024-11-29 03:49:09.197715
807	Amazon	$99.26	2024-11-28	88	2024-11-29 03:51:29.621988	2024-11-29 03:51:29.621988
808	Amazon	$34.55	2024-11-28	88	2024-11-29 03:51:29.626914	2024-11-29 03:51:29.626914
809	Amazon Prime	$16.19	2024-11-28	73	2024-11-29 03:51:29.702777	2024-11-29 03:51:29.702777
810	Piedmont Healthcare (Henry)	$120.20	2024-11-28	65	2024-11-29 03:52:37.653208	2024-11-29 03:52:37.653208
811	Med Rehabilitation	$100.00	2024-11-29	65	2024-11-30 16:00:49.004683	2024-11-30 16:00:49.004683
806	Kroger	$32.28	2024-11-28	63	2024-11-29 03:49:09.199647	2024-11-30 16:02:20.200142
813	Amazon	$36.29	2024-11-29	88	2024-11-30 16:03:58.846369	2024-11-30 16:03:58.846369
814	Amazon	$89.80	2024-11-29	88	2024-11-30 16:04:20.298364	2024-11-30 16:04:20.298364
815	Amazon	$17.26	2024-11-29	88	2024-11-30 16:04:37.724258	2024-11-30 16:04:37.724258
816	Mortgage (11/30)	$1,716.13	2025-07-01	61	2024-11-30 16:17:20.81748	2024-11-30 16:17:20.81748
817	Labcorp (Ming)	$26.26	2024-12-01	65	2024-12-01 18:04:21.32814	2024-12-01 18:04:21.32814
818	Spotify	$16.99	2024-12-01	73	2024-12-01 18:04:21.337629	2024-12-01 18:04:21.337629
819	Power Bill	$124.00	2024-12-02	64	2024-12-03 14:18:14.834921	2024-12-03 14:18:14.834921
820	Apple Bill	$4.89	2024-12-03	73	2024-12-03 14:19:49.041022	2024-12-03 14:19:49.041022
821	Farmer's	$12.30	2024-12-02	63	2024-12-03 14:20:21.426674	2024-12-03 14:20:21.426674
822	Farmer's	$117.47	2024-12-02	63	2024-12-03 14:20:21.430133	2024-12-03 14:20:21.430133
823	Render.com	$9.65	2024-12-03	73	2024-12-03 14:23:14.002113	2024-12-03 14:23:14.002113
824	Name Cheap.com	$17.16	2024-12-03	73	2024-12-03 14:23:14.004627	2024-12-03 14:23:14.004627
\.


--
-- Data for Name: income_sources; Type: TABLE DATA; Schema: public; Owner: -
--

COPY "public"."income_sources" ("id", "name", "user_id", "created_at", "updated_at") FROM stdin;
1	Rent	6	2024-01-03 00:01:34.06631	2024-01-03 00:01:34.06631
2	Salary	7	2024-01-03 16:29:02.077852	2024-01-03 16:29:02.077852
3	Henry's Payday	6	2024-01-10 00:44:07.568878	2024-01-10 00:44:07.568878
4	Miscellaneous	6	2024-01-10 00:46:02.726019	2024-01-10 00:46:02.726019
5	Ming's Payday	6	2024-01-17 04:50:34.257786	2024-01-17 04:50:34.257786
\.


--
-- Data for Name: paychecks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY "public"."paychecks" ("id", "date", "amount", "income_source_id", "created_at", "updated_at", "description") FROM stdin;
1	2024-01-02	$1,100.00	1	2024-01-03 00:01:34.08112	2024-01-03 00:01:34.08112	\N
2	2024-01-02	$900.00	2	2024-01-03 16:29:02.081265	2024-01-03 16:29:02.081265	
3	2023-12-20	$8,213.00	2	2024-01-03 16:38:29.990348	2024-01-03 16:38:29.990348	
5	2024-01-08	$1,115.92	3	2024-01-10 00:44:07.597447	2024-01-10 00:44:07.597447	
6	2024-01-04	$21.69	4	2024-01-10 00:46:02.729436	2024-01-10 00:46:02.729436	Ryan food money
7	2024-01-04	$22.00	4	2024-01-10 00:46:16.159548	2024-01-10 00:46:16.159548	Core food money
8	2024-01-04	$25.00	4	2024-01-10 00:46:40.612517	2024-01-10 00:46:40.612517	Ryan food money
9	2024-01-04	$43.50	4	2024-01-10 00:46:58.145986	2024-01-10 00:46:58.145986	Danial food money
10	2024-01-10	$30.00	4	2024-01-11 03:08:44.373325	2024-01-11 03:08:44.373325	Ryan food money
11	2024-01-10	$190.00	4	2024-01-11 03:09:01.288837	2024-01-11 03:09:01.288837	Zeke trip money
12	2024-01-12	$2,272.22	5	2024-01-17 04:50:34.262737	2024-01-17 04:50:34.262737	
13	2024-01-19	$1,097.17	3	2024-01-20 07:44:58.321363	2024-01-20 07:44:58.321363	
14	2024-01-25	$900.00	1	2024-01-25 05:31:51.289953	2024-01-25 05:31:51.289953	Chris Rent
15	2024-02-05	$1,455.87	3	2024-02-12 15:41:29.910003	2024-02-12 15:41:29.910003	
16	2024-02-01	$1,100.00	1	2024-02-12 15:41:58.000448	2024-02-12 15:41:58.000448	Jody
17	2024-02-01	$2,203.58	5	2024-02-12 15:42:52.224489	2024-02-12 15:42:52.224489	
18	2024-02-15	$2,310.34	5	2024-02-15 10:35:09.85445	2024-02-15 10:35:09.85445	
19	2024-02-13	$14.61	4	2024-02-15 10:36:39.698412	2024-02-15 10:36:39.698412	Henry's Insurance Check
20	2024-02-13	$1,724.00	4	2024-02-15 10:36:52.327938	2024-02-15 10:36:52.327938	Henry's Insurance Check
21	2024-02-22	$900.00	1	2024-02-23 01:42:07.689447	2024-02-23 01:42:07.689447	Chris Rent
22	2024-02-24	$278.00	4	2024-02-26 02:26:44.213876	2024-02-26 02:26:44.213876	GA ST TAX RFD
23	2024-03-01	$1,100.00	1	2024-03-01 15:05:00.822301	2024-03-01 15:05:00.822301	Jody Rent
24	2024-03-01	$2,203.58	5	2024-03-01 15:05:34.331065	2024-03-01 15:05:34.331065	
25	2024-02-27	$1,591.00	4	2024-03-01 15:15:08.639063	2024-03-01 15:15:08.639063	IRS TREAS
26	2024-03-04	$111.00	4	2024-03-05 04:33:50.350703	2024-03-05 04:33:50.350703	Jody Utility
27	2024-03-15	$2,299.74	5	2024-03-15 12:13:12.399817	2024-03-15 12:13:12.399817	
28	2024-03-17	$25.00	4	2024-03-17 20:10:20.52015	2024-03-17 20:10:20.52015	Ezekiel 5 day untility
29	2024-03-16	$1,303.47	3	2024-03-17 20:10:47.497271	2024-03-17 20:10:47.497271	
30	2024-03-16	$1,501.34	3	2024-03-17 20:11:06.800917	2024-03-17 20:11:06.800917	
31	2024-03-23	$23.60	4	2024-03-25 00:27:06.142765	2024-03-25 00:27:06.142765	Henry Poker Gain!
32	2024-03-23	$3,000.00	4	2024-03-25 00:27:39.003435	2024-03-25 00:27:39.003435	Henry's uncle from ShangHai
33	2024-03-26	$900.00	1	2024-03-27 00:21:43.531011	2024-03-27 00:21:43.531011	Chris Rent
35	2024-04-01	$1,486.18	3	2024-04-01 12:19:34.544835	2024-04-01 12:19:34.544835	(03-29)
36	2024-04-01	$2,203.58	5	2024-04-01 12:20:04.669301	2024-04-01 12:20:04.669301	(03-30)
37	2024-04-01	$1,100.00	1	2024-04-01 16:20:22.243835	2024-04-01 16:20:22.243835	Jody Rent
38	2024-04-01	$92.82	4	2024-04-01 16:20:56.321416	2024-04-01 16:20:56.321416	Jody Utility
39	2024-04-15	$2,214.48	5	2024-04-15 12:11:03.379362	2024-04-15 12:11:03.379362	
40	2024-04-17	$1,476.07	3	2024-04-17 12:19:41.429777	2024-04-17 12:19:41.429777	
41	2024-04-19	$900.00	1	2024-04-22 12:21:10.044973	2024-04-22 12:21:10.044973	Chris Rent
42	2024-04-24	$1,300.00	4	2024-04-25 00:33:51.646186	2024-04-25 00:33:51.646186	Henry's parents car
43	2024-05-01	$1,455.87	3	2024-04-29 11:54:03.873711	2024-04-29 11:54:03.873711	(04-27)
44	2024-05-01	$2,203.58	5	2024-05-01 12:45:36.037974	2024-05-01 12:45:36.037974	
45	2024-05-01	$83.36	4	2024-05-02 04:10:42.457589	2024-05-02 04:10:42.457589	Jody Utility
46	2024-05-01	$1,100.00	1	2024-05-02 04:12:27.722716	2024-05-02 04:12:27.722716	Jody Rent
47	2024-05-03	$238.64	4	2024-05-03 12:05:00.606725	2024-05-03 12:05:00.606725	Henry Insurance check
48	2024-05-07	$400.00	1	2024-05-08 12:13:44.806597	2024-05-08 12:13:44.806597	Chris Rent
49	2024-05-11	$1,496.29	3	2024-05-13 15:46:38.353944	2024-05-13 15:46:38.353944	
50	2024-05-15	$2,332.37	5	2024-05-15 12:23:46.240968	2024-05-15 12:23:46.240968	
51	2024-05-13	$29.20	4	2024-05-15 12:24:13.686616	2024-05-15 12:24:13.686616	Henry Insurance check
52	2024-05-13	$208.73	4	2024-05-15 12:24:33.745186	2024-05-15 12:24:33.745186	Henry Insurance check
53	2024-05-13	$400.00	1	2024-05-15 12:26:00.751643	2024-05-15 12:26:00.751643	Summer Sublease (part of deposit)
54	2024-05-15	$950.00	1	2024-05-16 03:02:25.707335	2024-05-16 03:02:25.707335	summer sublease (500 deposit and May rent 450)
55	2024-06-01	$1,556.92	3	2024-05-30 12:29:32.536146	2024-05-30 12:29:32.536146	(05/30)
56	2024-06-01	$2,203.58	5	2024-05-31 11:57:18.995113	2024-05-31 11:57:18.995113	
57	2024-06-01	$1,100.00	1	2024-06-01 22:34:18.143833	2024-06-01 22:34:18.143833	Jody Rent
58	2024-06-01	$900.00	1	2024-06-01 22:34:45.110894	2024-06-01 22:34:45.110894	JiaWei Rent
59	2024-06-10	$1,455.86	3	2024-06-11 12:28:40.086284	2024-06-11 12:28:40.086284	
60	2024-06-03	$98.86	4	2024-06-11 12:29:44.078253	2024-06-11 12:29:44.078253	Jody Utility
61	2024-06-14	$45.20	4	2024-06-18 12:40:01.54483	2024-06-18 12:40:01.54483	Jia Wei Utility
62	2024-06-14	$2,203.58	5	2024-06-18 12:40:29.06067	2024-06-18 12:40:29.06067	
63	2024-06-25	$1,678.20	3	2024-06-25 12:05:52.437334	2024-06-25 12:05:52.437334	
64	2024-07-01	$2,203.58	5	2024-06-30 05:12:58.023834	2024-06-30 05:12:58.023834	
65	2024-07-08	$1,647.88	3	2024-07-10 04:02:37.149031	2024-07-10 04:02:37.149031	
66	2024-07-13	$2,420.39	5	2024-07-15 02:20:45.603431	2024-07-15 02:20:45.603431	
67	2024-08-01	$1,386.38	3	2024-08-11 03:03:40.159574	2024-08-11 03:03:40.159574	
68	2024-08-01	$2,205.67	5	2024-08-11 03:04:09.375692	2024-08-11 03:04:09.375692	
69	2024-07-26	$1,386.38	3	2024-08-11 03:07:17.773999	2024-08-11 03:07:17.773999	
70	2024-08-12	$1,000.00	1	2024-08-13 00:35:37.811414	2024-08-13 00:35:37.811414	Ming Parents
71	2024-08-15	$2,238.83	5	2024-08-15 11:44:43.391137	2024-08-15 11:44:43.391137	
72	2024-08-16	$900.00	1	2024-08-19 12:23:12.894346	2024-08-19 12:23:12.894346	Chris Rent (August)
73	2024-09-01	$900.00	1	2024-08-19 12:23:47.670119	2024-08-19 12:23:47.670119	Chris Rent (September)(08/16)
74	2024-08-22	$300.00	4	2024-08-24 03:01:14.046905	2024-08-24 03:01:14.046905	Coin Base
76	2024-09-01	$2,000.00	1	2024-08-30 03:10:17.740967	2024-08-30 03:10:17.740967	Ming Parents
77	2024-10-01	$2,000.00	1	2024-08-30 03:11:03.251689	2024-08-30 03:11:03.251689	Ming Parents
78	2024-08-29	$1,000.00	1	2024-08-30 03:13:23.801941	2024-08-30 03:13:23.801941	Ming Parents
79	2024-08-30	$6,775.32	4	2024-08-30 03:15:38.214221	2024-08-30 03:15:38.214221	Escrow To Mortgagor
80	2024-09-01	$2,205.67	5	2024-08-31 01:12:52.319571	2024-08-31 01:12:52.319571	
81	2024-08-30	$107.99	4	2024-08-31 01:22:14.80591	2024-08-31 01:22:14.80591	Amazon Return Refund
82	2024-11-01	$500.00	1	2024-09-02 01:39:50.963134	2024-09-02 01:39:50.963134	Ming Parents
83	2024-09-05	$1,396.51	3	2024-09-05 13:42:29.972876	2024-09-05 13:42:29.972876	
84	2024-11-01	$1,500.00	1	2024-09-06 12:17:20.153202	2024-09-06 12:17:20.153202	Ming Parents
85	2024-12-01	$500.00	1	2024-09-06 12:17:35.570439	2024-09-06 12:17:35.570439	Ming Parents
86	2024-12-01	$1,000.00	1	2024-09-09 18:55:58.644435	2024-09-09 18:55:58.644435	Ming Parents
87	2024-09-11	$914.22	5	2024-09-12 12:23:30.76612	2024-09-12 12:23:30.76612	Bonus
88	2024-09-13	$2,205.67	5	2024-09-13 12:20:24.301778	2024-09-13 12:20:24.301778	
89	2024-09-18	$1,502.74	3	2024-09-18 11:49:26.496322	2024-09-18 11:49:26.496322	
90	2024-09-18	$20.76	4	2024-09-19 14:37:56.357339	2024-09-19 14:37:56.357339	AllStateHealthSolution
91	2025-01-01	$1,500.00	1	2024-09-26 12:04:54.026421	2024-09-26 12:04:54.026421	Ming Parents (9/25)
92	2024-10-01	$900.00	1	2024-09-30 11:47:55.777058	2024-09-30 11:47:55.777058	Chris Rent
93	2024-09-30	$117.14	4	2024-09-30 11:53:07.027674	2024-09-30 11:53:07.027674	piedmont healthcare
94	2024-10-01	$2,205.67	5	2024-10-01 11:07:03.137012	2024-10-01 11:07:03.137012	
95	2025-02-01	$2,000.00	1	2024-10-03 02:52:21.913063	2024-10-03 02:52:21.913063	Ming Parents (10/2)
96	2024-10-03	$1,679.85	3	2024-10-03 12:09:07.935753	2024-10-03 12:09:07.935753	
97	2025-03-01	$1,000.00	1	2024-10-04 12:24:21.702309	2024-10-04 12:24:21.702309	Ming Parents(10/04)
98	2025-04-01	$2,000.00	1	2024-10-05 01:47:07.453997	2024-10-05 01:47:07.453997	Ming Parents
99	2024-10-12	$2,220.55	5	2024-10-16 02:10:20.397397	2024-10-16 02:10:20.397397	
100	2024-10-18	$1,760.79	3	2024-10-18 12:21:42.826129	2024-10-18 12:21:42.826129	
101	2025-05-01	$2,000.00	1	2024-10-21 02:53:08.456901	2024-10-21 02:53:08.456901	Ming Parents
102	2024-11-01	$900.00	1	2024-10-29 00:04:28.922616	2024-10-29 00:04:28.922616	Chris Rent
103	2024-11-01	$2,205.67	5	2024-11-01 12:17:17.715506	2024-11-01 12:17:17.715506	
104	2024-11-02	$1,295.31	3	2024-11-03 19:30:32.908892	2024-11-03 19:30:32.908892	
105	2025-06-01	$2,000.00	1	2024-11-05 13:17:43.850831	2024-11-05 13:17:43.850831	Ming Parents (11/5)
106	2024-11-06	$184.29	4	2024-11-06 17:43:03.022921	2024-11-06 17:43:03.022921	Health insurance check
107	2024-11-14	$1,669.71	3	2024-11-14 13:20:54.034465	2024-11-14 13:20:54.034465	
108	2024-11-15	$4,335.67	5	2024-11-16 23:15:42.101095	2024-11-16 23:15:42.101095	Exam Compensate
109	2024-12-01	$900.00	1	2024-11-25 14:03:42.114034	2024-11-25 14:03:42.114034	Chris Rent
110	2024-12-01	$2,205.67	5	2024-11-29 03:47:15.716313	2024-11-29 03:47:15.716313	
111	2024-12-01	$1,497.70	3	2024-11-30 15:57:23.726905	2024-11-30 15:57:23.726905	(11/1)
\.


--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY "public"."schema_migrations" ("version") FROM stdin;
20231026142326
20231026142327
20231026142328
20231026175015
20231026175349
20231026175508
20231026175625
20231026175736
20231026175938
20231026180022
20231227192702
20231227200225
20231227200548
20240103032034
\.


--
-- Data for Name: tasks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY "public"."tasks" ("id", "description", "completed", "upgrade_id", "created_at", "updated_at") FROM stdin;
\.


--
-- Data for Name: upgrades; Type: TABLE DATA; Schema: public; Owner: -
--

COPY "public"."upgrades" ("id", "potential_income", "minimum_downpayment", "income_source_id", "created_at", "updated_at") FROM stdin;
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: -
--

COPY "public"."users" ("id", "clerk_user_id", "created_at", "updated_at") FROM stdin;
1	user_2aLJJ2LpmYLgY4C1xceHdVmxLJZ	2024-01-02 15:21:25.007436	2024-01-02 15:21:25.007436
2	user_2aPaJTWTqHzemjZVAYWxFT52AmH	2024-01-02 19:09:56.321351	2024-01-02 19:09:56.321351
3	user_2aPap42gKnxM6YopHzNMJIB4JAz	2024-01-02 19:14:09.340345	2024-01-02 19:14:09.340345
4	user_2aPgtVU478dlxwjGH6itpYahvA5	2024-01-02 20:04:04.621061	2024-01-02 20:04:04.621061
5	user_2aPhJWArHf1ily7iflDLgmNSert	2024-01-02 20:07:31.328254	2024-01-02 20:07:31.328254
6	user_2aQ9G9zYQHRUqHo6kuinh95NTod	2024-01-02 23:57:19.373937	2024-01-02 23:57:19.373937
7	user_2aQYjrqRaT5LQykqOfFoLMe3AjT	2024-01-03 03:26:49.173536	2024-01-03 03:26:49.173536
\.


--
-- Name: asset_transactions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('"public"."asset_transactions_id_seq"', 9, true);


--
-- Name: asset_types_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('"public"."asset_types_id_seq"', 36, true);


--
-- Name: assets_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('"public"."assets_id_seq"', 10, true);


--
-- Name: categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('"public"."categories_id_seq"', 89, true);


--
-- Name: expenses_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('"public"."expenses_id_seq"', 824, true);


--
-- Name: income_sources_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('"public"."income_sources_id_seq"', 5, true);


--
-- Name: paychecks_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('"public"."paychecks_id_seq"', 111, true);


--
-- Name: tasks_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('"public"."tasks_id_seq"', 1, false);


--
-- Name: upgrades_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('"public"."upgrades_id_seq"', 1, false);


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('"public"."users_id_seq"', 7, true);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."ar_internal_metadata"
    ADD CONSTRAINT "ar_internal_metadata_pkey" PRIMARY KEY ("key");


--
-- Name: asset_transactions asset_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."asset_transactions"
    ADD CONSTRAINT "asset_transactions_pkey" PRIMARY KEY ("id");


--
-- Name: asset_types asset_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."asset_types"
    ADD CONSTRAINT "asset_types_pkey" PRIMARY KEY ("id");


--
-- Name: assets assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."assets"
    ADD CONSTRAINT "assets_pkey" PRIMARY KEY ("id");


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_pkey" PRIMARY KEY ("id");


--
-- Name: expenses expenses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_pkey" PRIMARY KEY ("id");


--
-- Name: income_sources income_sources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."income_sources"
    ADD CONSTRAINT "income_sources_pkey" PRIMARY KEY ("id");


--
-- Name: paychecks paychecks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."paychecks"
    ADD CONSTRAINT "paychecks_pkey" PRIMARY KEY ("id");


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."schema_migrations"
    ADD CONSTRAINT "schema_migrations_pkey" PRIMARY KEY ("version");


--
-- Name: tasks tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_pkey" PRIMARY KEY ("id");


--
-- Name: upgrades upgrades_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."upgrades"
    ADD CONSTRAINT "upgrades_pkey" PRIMARY KEY ("id");


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");


--
-- Name: index_asset_transactions_on_asset_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "index_asset_transactions_on_asset_id" ON "public"."asset_transactions" USING "btree" ("asset_id");


--
-- Name: index_asset_types_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "index_asset_types_on_user_id" ON "public"."asset_types" USING "btree" ("user_id");


--
-- Name: index_assets_on_asset_type_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "index_assets_on_asset_type_id" ON "public"."assets" USING "btree" ("asset_type_id");


--
-- Name: index_categories_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "index_categories_on_user_id" ON "public"."categories" USING "btree" ("user_id");


--
-- Name: index_expenses_on_category_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "index_expenses_on_category_id" ON "public"."expenses" USING "btree" ("category_id");


--
-- Name: index_income_sources_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "index_income_sources_on_user_id" ON "public"."income_sources" USING "btree" ("user_id");


--
-- Name: index_paychecks_on_income_source_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "index_paychecks_on_income_source_id" ON "public"."paychecks" USING "btree" ("income_source_id");


--
-- Name: index_tasks_on_upgrade_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "index_tasks_on_upgrade_id" ON "public"."tasks" USING "btree" ("upgrade_id");


--
-- Name: index_upgrades_on_income_source_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "index_upgrades_on_income_source_id" ON "public"."upgrades" USING "btree" ("income_source_id");


--
-- Name: expenses fk_rails_06966d0da0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "fk_rails_06966d0da0" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id");


--
-- Name: upgrades fk_rails_76e282aa2a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."upgrades"
    ADD CONSTRAINT "fk_rails_76e282aa2a" FOREIGN KEY ("income_source_id") REFERENCES "public"."income_sources"("id");


--
-- Name: income_sources fk_rails_77653b806c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."income_sources"
    ADD CONSTRAINT "fk_rails_77653b806c" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id");


--
-- Name: asset_types fk_rails_77d17e9bf5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."asset_types"
    ADD CONSTRAINT "fk_rails_77d17e9bf5" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id");


--
-- Name: assets fk_rails_a11d2cd914; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."assets"
    ADD CONSTRAINT "fk_rails_a11d2cd914" FOREIGN KEY ("asset_type_id") REFERENCES "public"."asset_types"("id");


--
-- Name: categories fk_rails_b8e2f7adfc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "fk_rails_b8e2f7adfc" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id");


--
-- Name: paychecks fk_rails_c1a4c83a58; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."paychecks"
    ADD CONSTRAINT "fk_rails_c1a4c83a58" FOREIGN KEY ("income_source_id") REFERENCES "public"."income_sources"("id");


--
-- Name: tasks fk_rails_c83fa9d046; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "fk_rails_c83fa9d046" FOREIGN KEY ("upgrade_id") REFERENCES "public"."upgrades"("id");


--
-- Name: asset_transactions fk_rails_f88204b817; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."asset_transactions"
    ADD CONSTRAINT "fk_rails_f88204b817" FOREIGN KEY ("asset_id") REFERENCES "public"."assets"("id");


--
-- PostgreSQL database dump complete
--

--
-- PostgreSQL database cluster dump complete
--

