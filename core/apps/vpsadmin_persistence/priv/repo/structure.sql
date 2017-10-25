--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.3
-- Dumped by pg_dump version 9.6.3

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'SQL_ASCII';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET search_path = public, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: commands; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE commands (
    id integer NOT NULL,
    transaction_id integer NOT NULL,
    module character varying(255) NOT NULL,
    state integer DEFAULT 0 NOT NULL,
    params jsonb NOT NULL,
    output jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    node_id integer NOT NULL
);


--
-- Name: commands_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE commands_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: commands_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE commands_id_seq OWNED BY commands.id;


--
-- Name: inclusive_locks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE inclusive_locks (
    resource character varying(255) NOT NULL,
    resource_id jsonb NOT NULL,
    transaction_chain_id integer NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: locations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE locations (
    id bigint NOT NULL,
    label character varying(255) NOT NULL,
    domain character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    row_state integer DEFAULT 1 NOT NULL,
    row_changes jsonb,
    row_changed_by_id integer
);


--
-- Name: locations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE locations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: locations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE locations_id_seq OWNED BY locations.id;


--
-- Name: nodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE nodes (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    location_id bigint NOT NULL,
    ip_addr character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    row_state integer DEFAULT 1 NOT NULL,
    row_changes jsonb,
    row_changed_by_id integer
);


--
-- Name: nodes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE nodes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: nodes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE nodes_id_seq OWNED BY nodes.id;


--
-- Name: resource_locks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE resource_locks (
    resource character varying(255) NOT NULL,
    resource_id jsonb NOT NULL,
    transaction_chain_id integer,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    type integer NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp without time zone
);


--
-- Name: transaction_chains; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE transaction_chains (
    id integer NOT NULL,
    label character varying(255),
    state integer DEFAULT 0 NOT NULL,
    progress integer DEFAULT 0 NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: transaction_chains_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE transaction_chains_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: transaction_chains_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE transaction_chains_id_seq OWNED BY transaction_chains.id;


--
-- Name: transaction_confirmations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE transaction_confirmations (
    id integer NOT NULL,
    command_id integer NOT NULL,
    type integer NOT NULL,
    state integer DEFAULT 0 NOT NULL,
    "table" character varying(255) NOT NULL,
    row_pks jsonb NOT NULL,
    changes jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: transaction_confirmations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE transaction_confirmations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: transaction_confirmations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE transaction_confirmations_id_seq OWNED BY transaction_confirmations.id;


--
-- Name: transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE transactions (
    id integer NOT NULL,
    transaction_chain_id integer NOT NULL,
    label character varying(255) NOT NULL,
    state integer DEFAULT 0 NOT NULL,
    progress integer DEFAULT 0 NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE transactions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE transactions_id_seq OWNED BY transactions.id;


--
-- Name: commands id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY commands ALTER COLUMN id SET DEFAULT nextval('commands_id_seq'::regclass);


--
-- Name: locations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations ALTER COLUMN id SET DEFAULT nextval('locations_id_seq'::regclass);


--
-- Name: nodes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY nodes ALTER COLUMN id SET DEFAULT nextval('nodes_id_seq'::regclass);


--
-- Name: transaction_chains id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY transaction_chains ALTER COLUMN id SET DEFAULT nextval('transaction_chains_id_seq'::regclass);


--
-- Name: transaction_confirmations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY transaction_confirmations ALTER COLUMN id SET DEFAULT nextval('transaction_confirmations_id_seq'::regclass);


--
-- Name: transactions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY transactions ALTER COLUMN id SET DEFAULT nextval('transactions_id_seq'::regclass);


--
-- Name: commands commands_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY commands
    ADD CONSTRAINT commands_pkey PRIMARY KEY (id);


--
-- Name: inclusive_locks inclusive_locks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY inclusive_locks
    ADD CONSTRAINT inclusive_locks_pkey PRIMARY KEY (resource, resource_id, transaction_chain_id);


--
-- Name: locations locations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations
    ADD CONSTRAINT locations_pkey PRIMARY KEY (id);


--
-- Name: nodes nodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY nodes
    ADD CONSTRAINT nodes_pkey PRIMARY KEY (id);


--
-- Name: resource_locks resource_locks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY resource_locks
    ADD CONSTRAINT resource_locks_pkey PRIMARY KEY (resource, resource_id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: transaction_chains transaction_chains_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY transaction_chains
    ADD CONSTRAINT transaction_chains_pkey PRIMARY KEY (id);


--
-- Name: transaction_confirmations transaction_confirmations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY transaction_confirmations
    ADD CONSTRAINT transaction_confirmations_pkey PRIMARY KEY (id);


--
-- Name: transactions transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY transactions
    ADD CONSTRAINT transactions_pkey PRIMARY KEY (id);


--
-- Name: commands_module_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commands_module_index ON commands USING btree (module);


--
-- Name: commands_state_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commands_state_index ON commands USING btree (state);


--
-- Name: commands_transaction_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commands_transaction_id_index ON commands USING btree (transaction_id);


--
-- Name: nodes_location_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX nodes_location_id_index ON nodes USING btree (location_id);


--
-- Name: nodes_name_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX nodes_name_unique ON nodes USING btree (name, location_id);


--
-- Name: transaction_chains_state_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX transaction_chains_state_index ON transaction_chains USING btree (state);


--
-- Name: transaction_confirmations_command_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX transaction_confirmations_command_id_index ON transaction_confirmations USING btree (command_id);


--
-- Name: transactions_state_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX transactions_state_index ON transactions USING btree (state);


--
-- Name: transactions_transaction_chain_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX transactions_transaction_chain_id_index ON transactions USING btree (transaction_chain_id);


--
-- Name: commands commands_node_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY commands
    ADD CONSTRAINT commands_node_id_fkey FOREIGN KEY (node_id) REFERENCES nodes(id);


--
-- Name: commands commands_transaction_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY commands
    ADD CONSTRAINT commands_transaction_id_fkey FOREIGN KEY (transaction_id) REFERENCES transactions(id);


--
-- Name: inclusive_locks inclusive_locks_resource_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY inclusive_locks
    ADD CONSTRAINT inclusive_locks_resource_fkey FOREIGN KEY (resource, resource_id) REFERENCES resource_locks(resource, resource_id);


--
-- Name: inclusive_locks inclusive_locks_transaction_chain_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY inclusive_locks
    ADD CONSTRAINT inclusive_locks_transaction_chain_id_fkey FOREIGN KEY (transaction_chain_id) REFERENCES transaction_chains(id);


--
-- Name: locations locations_row_changed_by_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY locations
    ADD CONSTRAINT locations_row_changed_by_id_fkey FOREIGN KEY (row_changed_by_id) REFERENCES transaction_chains(id);


--
-- Name: nodes nodes_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY nodes
    ADD CONSTRAINT nodes_location_id_fkey FOREIGN KEY (location_id) REFERENCES locations(id);


--
-- Name: nodes nodes_row_changed_by_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY nodes
    ADD CONSTRAINT nodes_row_changed_by_id_fkey FOREIGN KEY (row_changed_by_id) REFERENCES transaction_chains(id);


--
-- Name: resource_locks resource_locks_transaction_chain_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY resource_locks
    ADD CONSTRAINT resource_locks_transaction_chain_id_fkey FOREIGN KEY (transaction_chain_id) REFERENCES transaction_chains(id);


--
-- Name: transaction_confirmations transaction_confirmations_command_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY transaction_confirmations
    ADD CONSTRAINT transaction_confirmations_command_id_fkey FOREIGN KEY (command_id) REFERENCES commands(id);


--
-- Name: transactions transactions_transaction_chain_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY transactions
    ADD CONSTRAINT transactions_transaction_chain_id_fkey FOREIGN KEY (transaction_chain_id) REFERENCES transaction_chains(id);


--
-- PostgreSQL database dump complete
--

INSERT INTO "schema_migrations" (version) VALUES (20170925121931), (20170926075010), (20171016064306), (20171017111059);

