-- ============================================================================
-- SMART-EV-DBMS: Full PostgreSQL Schema + Seed Data for Supabase
-- Run this entire script once in the Supabase SQL Editor
-- ============================================================================

-- ============================================================================
-- TABLES

CREATE EXTENSION IF NOT EXISTS btree_gist;
-- ============================================================================

CREATE TABLE IF NOT EXISTS substation (
    substation_id       SERIAL PRIMARY KEY,
    name                VARCHAR(100)   NOT NULL,
    max_grid_capacity_kw DECIMAL(10,2) NOT NULL,
    region_code         VARCHAR(20)    NOT NULL,
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS charging_station (
    station_id          SERIAL PRIMARY KEY,
    substation_id       INT            NOT NULL REFERENCES substation(substation_id),
    station_name        VARCHAR(100)   NOT NULL,
    street_address      VARCHAR(255)   NOT NULL,
    city                VARCHAR(100)   NOT NULL,
    status              VARCHAR(20)    NOT NULL DEFAULT 'ACTIVE',
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS charger_bay (
    bay_id              SERIAL PRIMARY KEY,
    station_id          INT            NOT NULL REFERENCES charging_station(station_id),
    bay_number          INT            NOT NULL,
    plug_type           VARCHAR(20)    NOT NULL,
    max_kw_output       DECIMAL(8,2)   NOT NULL,
    is_operational      BOOLEAN        NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS tariff_plan (
    tariff_id           SERIAL PRIMARY KEY,
    station_id          INT            NOT NULL REFERENCES charging_station(station_id),
    plan_name           VARCHAR(50)    NOT NULL,
    start_hour          INT            NOT NULL,
    end_hour            INT            NOT NULL,
    base_rate_per_kwh   DECIMAL(10,4)  NOT NULL,
    idle_fee_per_min    DECIMAL(10,4)  NOT NULL DEFAULT 0.0000,
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fleet_org (
    org_id              SERIAL PRIMARY KEY,
    company_name        VARCHAR(150)   NOT NULL,
    tax_id              VARCHAR(50)    NOT NULL,
    credit_line_limit   DECIMAL(12,2)  NOT NULL DEFAULT 0.00,
    current_balance     DECIMAL(12,2)  NOT NULL DEFAULT 0.00,
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS app_user (
    user_id             SERIAL PRIMARY KEY,
    org_id              INT            REFERENCES fleet_org(org_id),
    full_name           VARCHAR(100)   NOT NULL,
    email               VARCHAR(150)   NOT NULL,
    phone               VARCHAR(25)    NOT NULL,
    user_role           VARCHAR(20)    NOT NULL,
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS vehicle (
    vehicle_id          SERIAL PRIMARY KEY,
    vin                 VARCHAR(17)    NOT NULL UNIQUE,
    org_id              INT            NOT NULL REFERENCES fleet_org(org_id),
    user_id             INT            NOT NULL REFERENCES app_user(user_id),
    license_plate       VARCHAR(20)    NOT NULL,
    battery_capacity_kwh DECIMAL(8,2)  NOT NULL,
    max_charge_rate_kw  DECIMAL(8,2)   NOT NULL,
    current_soc_pct     DECIMAL(5,2)   NOT NULL DEFAULT 50.00,
    ownership_type      VARCHAR(20)    NOT NULL DEFAULT 'FLEET',
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fleet_mission (
    mission_id          SERIAL PRIMARY KEY,
    vehicle_id          INT            REFERENCES vehicle(vehicle_id),
    fleet_org_id        INT            REFERENCES fleet_org(org_id),
    mission_label       VARCHAR(150),
    departure_time      TIMESTAMPTZ    NOT NULL,
    target_soc_pct      DECIMAL(5,2)   NOT NULL,
    priority_level      INT            NOT NULL DEFAULT 1,
    status              VARCHAR(20)    NOT NULL DEFAULT 'scheduled',
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS reservation (
    reservation_id      SERIAL PRIMARY KEY,
    bay_id              INT            NOT NULL REFERENCES charger_bay(bay_id),
    vehicle_id          INT            REFERENCES vehicle(vehicle_id),
    user_id             INT            NOT NULL REFERENCES app_user(user_id),
    time_slot           TSTZRANGE      NOT NULL,
    status              VARCHAR(20)    NOT NULL DEFAULT 'confirmed',
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    EXCLUDE USING GIST (bay_id WITH =, time_slot WITH &&)
        WHERE (status NOT IN ('cancelled', 'completed'))
);

CREATE TABLE IF NOT EXISTS charging_session (
    session_id          SERIAL PRIMARY KEY,
    bay_id              INT            NOT NULL REFERENCES charger_bay(bay_id),
    vehicle_id          INT            REFERENCES vehicle(vehicle_id),
    user_id             INT            NOT NULL REFERENCES app_user(user_id),
    reservation_id      INT            REFERENCES reservation(reservation_id),
    start_time          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    end_time            TIMESTAMPTZ,
    allocated_kw        DECIMAL(8,2)   NOT NULL,
    energy_delivered_kwh DECIMAL(10,3) NOT NULL DEFAULT 0.000,
    idle_minutes        INT            NOT NULL DEFAULT 0,
    status              VARCHAR(20)    NOT NULL DEFAULT 'STARTED',
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS maintenance_log (
    log_id              SERIAL PRIMARY KEY,
    bay_id              INT            NOT NULL REFERENCES charger_bay(bay_id),
    technician_id       INT            REFERENCES app_user(user_id),
    issue_reported      VARCHAR(500)   NOT NULL,
    reported_at         TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    resolved_at         TIMESTAMPTZ,
    repair_status       VARCHAR(20)    NOT NULL DEFAULT 'OPEN',
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS invoice (
    invoice_id          SERIAL PRIMARY KEY,
    session_id          INT            NOT NULL REFERENCES charging_session(session_id),
    energy_charge       DECIMAL(10,2)  NOT NULL DEFAULT 0.00,
    idle_penalty_charge DECIMAL(10,2)  NOT NULL DEFAULT 0.00,
    tax_amount          DECIMAL(10,2)  NOT NULL DEFAULT 0.00,
    total_amount        DECIMAL(10,2)  GENERATED ALWAYS AS (energy_charge + idle_penalty_charge + tax_amount) STORED,
    status              VARCHAR(20)    NOT NULL DEFAULT 'PENDING',
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS payment (
    payment_id          SERIAL PRIMARY KEY,
    invoice_id          INT            NOT NULL REFERENCES invoice(invoice_id),
    payment_method      VARCHAR(20)    NOT NULL,
    paid_amount         DECIMAL(10,2)  NOT NULL,
    transaction_ref     VARCHAR(100)   NOT NULL,
    settled_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_charging_station_substation ON charging_station(substation_id);
CREATE INDEX IF NOT EXISTS idx_charger_bay_station ON charger_bay(station_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_org ON vehicle(org_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_user ON vehicle(user_id);
CREATE INDEX IF NOT EXISTS idx_reservation_bay ON reservation(bay_id);
CREATE INDEX IF NOT EXISTS idx_reservation_vehicle ON reservation(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_fleet_mission_vehicle ON fleet_mission(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_charging_session_bay ON charging_session(bay_id);
CREATE INDEX IF NOT EXISTS idx_maintenance_bay ON maintenance_log(bay_id);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Auto-update updated_at on every table
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$ DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['substation','charging_station','charger_bay','fleet_org',
                             'app_user','vehicle','fleet_mission','reservation',
                             'charging_session','maintenance_log','invoice'] LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS trg_updated_at ON %I;
       CREATE TRIGGER trg_updated_at BEFORE UPDATE ON %I
       FOR EACH ROW EXECUTE FUNCTION set_updated_at();', t, t);
  END LOOP;
END $$;

-- Auto mark bay non-operational when a maintenance log is opened
CREATE OR REPLACE FUNCTION trg_maintenance_bay_status()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.repair_status = 'OPEN' OR NEW.repair_status = 'IN_PROGRESS' THEN
        UPDATE charger_bay SET is_operational = FALSE WHERE bay_id = NEW.bay_id;
    ELSIF NEW.repair_status = 'RESOLVED' THEN
        UPDATE charger_bay SET is_operational = TRUE  WHERE bay_id = NEW.bay_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_maintenance_status ON maintenance_log;
CREATE TRIGGER trg_maintenance_status
AFTER INSERT OR UPDATE ON maintenance_log
FOR EACH ROW EXECUTE FUNCTION trg_maintenance_bay_status();

-- ============================================================================
-- VIEWS
-- ============================================================================

CREATE OR REPLACE VIEW v_station_availability AS
SELECT
    cs.station_id,
    cs.station_name,
    cs.city,
    COUNT(cb.bay_id)                                          AS total_bays,
    COUNT(cb.bay_id) FILTER (WHERE cb.is_operational)        AS operational_bays,
    COUNT(cb.bay_id) FILTER (WHERE NOT cb.is_operational)    AS offline_bays
FROM charging_station cs
LEFT JOIN charger_bay cb ON cb.station_id = cs.station_id
GROUP BY cs.station_id, cs.station_name, cs.city;

CREATE OR REPLACE VIEW v_active_sessions AS
SELECT
    s.session_id,
    s.bay_id,
    s.vehicle_id,
    s.allocated_kw,
    s.energy_delivered_kwh,
    s.start_time,
    s.status,
    cs.station_name,
    cs.city
FROM charging_session s
JOIN charger_bay cb ON cb.bay_id = s.bay_id
JOIN charging_station cs ON cs.station_id = cb.station_id
WHERE s.status IN ('STARTED', 'CHARGING');

CREATE OR REPLACE VIEW v_fleet_dashboard AS
SELECT
    fo.org_id,
    fo.company_name,
    COUNT(v.vehicle_id)                                       AS total_vehicles,
    AVG(v.current_soc_pct)                                   AS avg_soc_pct,
    COUNT(fm.mission_id) FILTER (WHERE fm.status = 'scheduled') AS pending_missions
FROM fleet_org fo
LEFT JOIN vehicle v  ON v.org_id  = fo.org_id
LEFT JOIN fleet_mission fm ON fm.fleet_org_id = fo.org_id
GROUP BY fo.org_id, fo.company_name;

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- 1. Substations
INSERT INTO substation (substation_id, name, max_grid_capacity_kw, region_code) VALUES
(1, 'North Grid Hub',    1200.00, 'IN-KA-N'),
(2, 'South Grid Hub',    900.00,  'IN-KA-S'),
(3, 'East Grid Station', 600.00,  'IN-KA-E')
ON CONFLICT (substation_id) DO NOTHING;
SELECT setval('substation_substation_id_seq', (SELECT MAX(substation_id) FROM substation));

-- 2. Charging Stations
INSERT INTO charging_station (station_id, substation_id, station_name, street_address, city, status) VALUES
(1,  1, 'Indiranagar Hub',    '100 Feet Road, Indiranagar',  'Bengaluru', 'ACTIVE'),
(2,  1, 'Koramangala Depot',  '80 Feet Road, Koramangala',   'Bengaluru', 'ACTIVE'),
(3,  2, 'Whitefield Depot',   'ITPL Main Road, Whitefield',  'Bengaluru', 'ACTIVE'),
(4,  3, 'Hebbal Station',     'Hebbal Flyover Road',          'Bengaluru', 'ACTIVE')
ON CONFLICT (station_id) DO NOTHING;
SELECT setval('charging_station_station_id_seq', (SELECT MAX(station_id) FROM charging_station));

-- 3. Charger Bays
INSERT INTO charger_bay (bay_id, station_id, bay_number, plug_type, max_kw_output, is_operational) VALUES
(1,  1, 1, 'CCS2',   200.00, TRUE),
(2,  1, 2, 'CCS2',   200.00, TRUE),
(3,  1, 3, 'Type2',   22.00, TRUE),
(4,  1, 4, 'Type2',   22.00, FALSE),
(5,  2, 1, 'CCS2',   150.00, TRUE),
(6,  2, 2, 'CHAdeMO',150.00, TRUE),
(7,  2, 3, 'Type2',   22.00, TRUE),
(8,  3, 1, 'CCS2',   300.00, TRUE),
(9,  3, 2, 'CCS2',   300.00, TRUE),
(10, 3, 3, 'Type2',   22.00, TRUE),
(11, 4, 1, 'CCS2',   150.00, TRUE),
(12, 4, 2, 'Type2',   22.00, TRUE)
ON CONFLICT (bay_id) DO NOTHING;
SELECT setval('charger_bay_bay_id_seq', (SELECT MAX(bay_id) FROM charger_bay));

-- 4. Fleet Organisations
INSERT INTO fleet_org (org_id, company_name, tax_id, credit_line_limit, current_balance) VALUES
(1, 'Prime Logistics Pvt Ltd', 'IN-GST-PL-001', 500000.00, 125000.00),
(2, 'Metro Transit Authority',  'IN-GST-MT-002', 800000.00, 310000.00),
(3, 'EcoExpress Couriers',      'IN-GST-EC-003', 200000.00,  48000.00)
ON CONFLICT (org_id) DO NOTHING;
SELECT setval('fleet_org_org_id_seq', (SELECT MAX(org_id) FROM fleet_org));

-- 5. App Users
INSERT INTO app_user (user_id, org_id, full_name, email, phone, user_role) VALUES
(1,  NULL, 'Admin User',       'admin@gridsync.io',          '+91-9000000001', 'ADMIN'),
(2,  NULL, 'Grid Technician',  'tech1@gridsync.io',          '+91-9000000002', 'TECHNICIAN'),
(3,  NULL, 'Grid Technician2', 'tech2@gridsync.io',          '+91-9000000003', 'TECHNICIAN'),
(4,  1,    'Ravi Kumar',       'ravi.kumar@primelogistics.in','+91-9000000004', 'FLEET_MANAGER'),
(5,  2,    'Priya Sharma',     'priya.s@metrotransit.in',    '+91-9000000005', 'FLEET_MANAGER'),
(6,  1,    'Arjun Singh',      'arjun@primelogistics.in',    '+91-9000000006', 'DRIVER'),
(7,  1,    'Meena Pillai',     'meena@primelogistics.in',    '+91-9000000007', 'DRIVER'),
(8,  2,    'Kiran Reddy',      'kiran@metrotransit.in',      '+91-9000000008', 'DRIVER'),
(9,  3,    'Sunita Rao',       'sunita@ecoexpress.in',       '+91-9000000009', 'DRIVER'),
(10, 3,    'Vikram Nair',      'vikram@ecoexpress.in',       '+91-9000000010', 'DRIVER'),
(11, 3,    'Anjali Gupta',     'anjali@ecoexpress.in',       '+91-9000000011', 'DRIVER'),
(12, NULL, 'Personal User 1',  'user1@example.com',          '+91-9000000012', 'PERSONAL'),
(13, NULL, 'Personal User 2',  'user2@example.com',          '+91-9000000013', 'PERSONAL')
ON CONFLICT (user_id) DO NOTHING;
SELECT setval('app_user_user_id_seq', (SELECT MAX(user_id) FROM app_user));

-- 6. Vehicles
INSERT INTO vehicle (vehicle_id, vin, org_id, user_id, license_plate, battery_capacity_kwh, max_charge_rate_kw, current_soc_pct, ownership_type) VALUES
(1,  '1FTFW1ED8NFA00001', 1, 6,  'KA-01-AB-1001', 300.00, 200.00, 42.00, 'FLEET'),
(2,  '1FTFW1ED8NFA00002', 1, 7,  'KA-01-AB-1002', 300.00, 200.00, 78.50, 'FLEET'),
(3,  '4V4NC9EH1RN00003',  2, 8,  'KA-01-CD-2001', 400.00, 300.00, 15.00, 'FLEET'),
(4,  '4V4NC9EH1RN00004',  2, 8,  'KA-01-CD-2002', 400.00, 300.00, 91.00, 'FLEET'),
(5,  '2C4RC1ST9HR00005',  3, 9,  'KA-01-EF-3001', 100.00, 150.00, 60.00, 'FLEET'),
(6,  '2C4RC1ST9HR00006',  3, 10, 'KA-01-EF-3002', 100.00, 150.00, 22.00, 'FLEET'),
(7,  '3FA6P0HD4LR00007',  3, 11, 'KA-01-EF-3003',  75.00, 100.00, 55.00, 'FLEET'),
(8,  '3FA6P0HD4LR00008',  3, 11, 'KA-01-EF-3004',  75.00, 100.00, 88.00, 'FLEET'),
(9,  '5YJ3E1EB8MF00009',  1, 6,  'KA-01-GH-4001',  82.00,  11.00, 34.00, 'PERSONAL'),
(10, 'WAUZZZF28NA00010',  2, 8,  'KA-01-IJ-5001',  77.00,  50.00, 67.00, 'PERSONAL')
ON CONFLICT (vehicle_id) DO NOTHING;
SELECT setval('vehicle_vehicle_id_seq', (SELECT MAX(vehicle_id) FROM vehicle));

-- 7. Fleet Missions
INSERT INTO fleet_mission (mission_id, vehicle_id, fleet_org_id, mission_label, departure_time, target_soc_pct, priority_level, status) VALUES
(1, 1, 1, 'Imminent dispatch - Priority',    NOW() + INTERVAL '1 hour',   90.00, 1, 'scheduled'),
(2, 3, 2, 'Metro morning route',             NOW() + INTERVAL '2 hours',  95.00, 2, 'scheduled'),
(3, 6, 3, 'EcoExpress urgent run',           NOW() + INTERVAL '45 minutes',85.00, 1, 'scheduled'),
(4, 5, 3, 'EcoExpress afternoon run',        NOW() + INTERVAL '4 hours',  80.00, 3, 'scheduled'),
(5, 2, 1, 'Prime long-haul evening',         NOW() + INTERVAL '8 hours',  90.00, 2, 'scheduled'),
(6, 7, 3, 'GreenLine tomorrow',              NOW() + INTERVAL '14 hours', 85.00, 3, 'scheduled'),
(7, 4, 2, 'Metro yesterday completed',       NOW() - INTERVAL '1 day',    95.00, 1, 'completed'),
(8, 8, 3, 'EcoExpress completed 2 days ago', NOW() - INTERVAL '2 days',   80.00, 2, 'completed')
ON CONFLICT (mission_id) DO NOTHING;
SELECT setval('fleet_mission_mission_id_seq', (SELECT MAX(mission_id) FROM fleet_mission));

-- 8. Reservations
INSERT INTO reservation (reservation_id, bay_id, vehicle_id, user_id, time_slot, status) VALUES
(1,  1, 1, 6,  tstzrange(NOW() + INTERVAL '2 hours',  NOW() + INTERVAL '3 hours'),  'confirmed'),
(2,  2, 2, 7,  tstzrange(NOW() + INTERVAL '3 hours',  NOW() + INTERVAL '4 hours'),  'confirmed'),
(3,  8, 3, 8,  tstzrange(NOW() + INTERVAL '1 hour',   NOW() + INTERVAL '3 hours'),  'confirmed'),
(4,  5, 5, 9,  tstzrange(NOW() + INTERVAL '4 hours',  NOW() + INTERVAL '5 hours'),  'confirmed'),
(5,  9, 7, 11, tstzrange(NOW() + INTERVAL '5 hours',  NOW() + INTERVAL '7 hours'),  'confirmed'),
(6,  1, 9, 6,  tstzrange(NOW() - INTERVAL '2 hours',  NOW() - INTERVAL '1 hour'),   'completed'),
(7,  8, 3, 8,  tstzrange(NOW() - INTERVAL '3 hours',  NOW() - INTERVAL '1 hour'),   'completed')
ON CONFLICT (reservation_id) DO NOTHING;
SELECT setval('reservation_reservation_id_seq', (SELECT MAX(reservation_id) FROM reservation));

DO $$ BEGIN RAISE NOTICE 'Schema and seed data applied successfully!'; END $$;
