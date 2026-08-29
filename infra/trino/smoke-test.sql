CREATE SCHEMA IF NOT EXISTS lakehouse.demo
WITH (location = 's3://warehouse/demo/');

CREATE TABLE IF NOT EXISTS lakehouse.demo.events (
    event_id BIGINT,
    event_name VARCHAR,
    occurred_at TIMESTAMP(6)
);

INSERT INTO lakehouse.demo.events
VALUES (1, 'lakehouse_started', CURRENT_TIMESTAMP);

SELECT * FROM lakehouse.demo.events;

