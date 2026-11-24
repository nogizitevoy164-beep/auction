-- Базовая схема единого игрового сервера.
-- В production пароли хранятся только как password_hash.

CREATE TABLE game_servers (
    id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    region TEXT NOT NULL DEFAULT 'global',
    max_players INTEGER NOT NULL DEFAULT 500,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE players (
    id BIGSERIAL PRIMARY KEY,
    login TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    server_id BIGINT NOT NULL REFERENCES game_servers(id),
    coins BIGINT NOT NULL DEFAULT 1000 CHECK (coins >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE item_definitions (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    item_type TEXT NOT NULL,
    rarity SMALLINT NOT NULL DEFAULT 1 CHECK (rarity BETWEEN 1 AND 5),
    base_cost BIGINT NOT NULL DEFAULT 1 CHECK (base_cost >= 1),
    size_x SMALLINT NOT NULL DEFAULT 1,
    size_y SMALLINT NOT NULL DEFAULT 1,
    config JSONB NOT NULL DEFAULT '{}',
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE item_instances (
    id UUID PRIMARY KEY,
    definition_id TEXT NOT NULL REFERENCES item_definitions(id),
    owner_id BIGINT NOT NULL REFERENCES players(id),
    state TEXT NOT NULL DEFAULT 'inventory',
    acquired_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE player_equipment (
    player_id BIGINT NOT NULL REFERENCES players(id),
    slot TEXT NOT NULL,
    item_instance_id UUID NOT NULL UNIQUE REFERENCES item_instances(id),
    PRIMARY KEY (player_id, slot)
);

CREATE TABLE market_listings (
    id UUID PRIMARY KEY,
    seller_id BIGINT NOT NULL REFERENCES players(id),
    item_instance_id UUID NOT NULL UNIQUE REFERENCES item_instances(id),
    price BIGINT NOT NULL CHECK (price > 0),
    expires_at TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE legendary_auctions (
    id UUID PRIMARY KEY,
    seller_id BIGINT NOT NULL REFERENCES players(id),
    item_instance_id UUID NOT NULL UNIQUE REFERENCES item_instances(id),
    start_price BIGINT NOT NULL CHECK (start_price > 0),
    current_price BIGINT NOT NULL CHECK (current_price >= start_price),
    ends_at TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    winner_id BIGINT REFERENCES players(id)
);

CREATE TABLE auction_bids (
    id BIGSERIAL PRIMARY KEY,
    auction_id UUID NOT NULL REFERENCES legendary_auctions(id),
    bidder_id BIGINT NOT NULL REFERENCES players(id),
    amount BIGINT NOT NULL CHECK (amount > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE castles (
    player_id BIGINT PRIMARY KEY REFERENCES players(id),
    level INTEGER NOT NULL DEFAULT 1,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE castle_buildings (
    id BIGSERIAL PRIMARY KEY,
    player_id BIGINT NOT NULL REFERENCES players(id),
    building_type TEXT NOT NULL,
    level INTEGER NOT NULL DEFAULT 1,
    stored_coins BIGINT NOT NULL DEFAULT 0,
    last_income_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    config JSONB NOT NULL DEFAULT '{}',
    UNIQUE (player_id, building_type)
);

CREATE TABLE crafting_orders (
    id UUID PRIMARY KEY,
    player_id BIGINT NOT NULL REFERENCES players(id),
    recipe_id TEXT NOT NULL,
    finishes_at TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL DEFAULT 'active'
);

CREATE TABLE server_news (
    id BIGSERIAL PRIMARY KEY,
    server_id BIGINT REFERENCES game_servers(id),
    news_type TEXT NOT NULL,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    priority SMALLINT NOT NULL DEFAULT 0,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE transactions (
    id BIGSERIAL PRIMARY KEY,
    player_id BIGINT NOT NULL REFERENCES players(id),
    transaction_type TEXT NOT NULL,
    amount BIGINT NOT NULL,
    balance_before BIGINT NOT NULL,
    balance_after BIGINT NOT NULL,
    reference_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
