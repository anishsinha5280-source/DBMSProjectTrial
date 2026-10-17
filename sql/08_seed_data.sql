-- ============================================================================
-- SCRIPT: 08_seed_data.sql
-- SYSTEM: Intelligent EV Charging Station and Fleet/Depot Management System
-- DIALECT: Microsoft SQL Server (T-SQL)
-- DESCRIPTION: Populates realistic, interconnected seed data across all 13
--              tables using explicit IDENTITY values for deterministic testing.
-- ============================================================================

USE EVChargingDB;
GO

SET NOCOUNT ON;

PRINT 'Seeding database with production-grade test fixtures...';

-- Clean existing data in reverse dependency order
DELETE FROM dbo.Payment;
DELETE FROM dbo.Invoice;
DELETE FROM dbo.ChargingSession;
DELETE FROM dbo.Reservation;
DELETE FROM dbo.FleetMission;
DELETE FROM dbo.MaintenanceLog;
DELETE FROM dbo.Vehicle;
DELETE FROM dbo.AppUser;
DELETE FROM dbo.FleetOrg;
DELETE FROM dbo.TariffPlan;
DELETE FROM dbo.ChargerBay;
DELETE FROM dbo.ChargingStation;
DELETE FROM dbo.Substation;
GO

-- ============================================================================
-- 1. SUBSTATION (4 Substations)
-- ============================================================================
SET IDENTITY_INSERT dbo.Substation ON;

INSERT INTO dbo.Substation (substation_id, name, max_grid_capacity_kw, region_code)
VALUES 
(1, 'Central City Primary Grid 110kV', 1200.00, 'METRO-CENTRAL'),
(2, 'Port Maritime & Industrial Substation', 2500.00, 'PORT-EAST'),
(3, 'Airport Corridor High-Voltage Hub', 1800.00, 'AIRPORT-WEST'),
(4, 'Northern Logistics Transmission Substation', 3000.00, 'NORTH-DIST');

SET IDENTITY_INSERT dbo.Substation OFF;
PRINT 'Substations seeded.';
GO

-- ============================================================================
-- 2. CHARGING STATION (6 Charging Stations)
-- ============================================================================
SET IDENTITY_INSERT dbo.ChargingStation ON;

INSERT INTO dbo.ChargingStation (station_id, substation_id, station_name, street_address, city, status)
VALUES 
(1, 1, 'Central Fleet Depot Station', '100 Innovation Way', 'Metropolis', 'ACTIVE'),
(2, 1, 'Downtown Commercial Hub', '45 Market Street', 'Metropolis', 'ACTIVE'),
(3, 2, 'Harbor Freight & Transit Depot', '88 Pier Terminal Blvd', 'Port City', 'ACTIVE'),
(4, 3, 'Airport Fast-Charge Oasis', '500 Skyway Drive', 'Aero City', 'ACTIVE'),
(5, 4, 'North Logistics Depot Alpha', '12 Industrial Parkway', 'Northfield', 'ACTIVE'),
(6, 4, 'North Suburban Public Station', '300 Maple Avenue', 'Northfield', 'ACTIVE');

SET IDENTITY_INSERT dbo.ChargingStation OFF;
PRINT 'Charging stations seeded.';
GO

-- ============================================================================
-- 3. CHARGER BAY (16 Bays across stations with CCS2, TYPE2, NACS)
-- ============================================================================
SET IDENTITY_INSERT dbo.ChargerBay ON;

INSERT INTO dbo.ChargerBay (bay_id, station_id, bay_number, plug_type, max_kw_output, is_operational)
VALUES 
-- Station 1 (Central Fleet Depot)
(1,  1, 1, 'CCS2', 350.00, 1),
(2,  1, 2, 'CCS2', 350.00, 1),
(3,  1, 3, 'NACS', 250.00, 1),
(4,  1, 4, 'TYPE2', 50.00, 1),

-- Station 2 (Downtown Commercial Hub)
(5,  2, 1, 'CCS2', 150.00, 1),
(6,  2, 2, 'NACS', 250.00, 1),
(7,  2, 3, 'TYPE2', 22.00, 1),

-- Station 3 (Harbor Freight Depot - Heavy Commercial)
(8,  3, 1, 'CCS2', 400.00, 1),
(9,  3, 2, 'CCS2', 400.00, 1),
(10, 3, 3, 'NACS', 300.00, 1),

-- Station 4 (Airport Fast-Charge)
(11, 4, 1, 'CCS2', 350.00, 1),
(12, 4, 2, 'NACS', 250.00, 1),
(13, 4, 3, 'TYPE2', 50.00, 1),

-- Station 5 & 6 (North Logistics Depot & Suburban)
(14, 5, 1, 'CCS2', 350.00, 1),
(15, 5, 2, 'CCS2', 350.00, 1),
(16, 6, 1, 'NACS', 150.00, 1);

SET IDENTITY_INSERT dbo.ChargerBay OFF;
PRINT 'Charger bays seeded.';
GO

-- ============================================================================
-- 4. TARIFF PLAN (Peak, Off-Peak, Overnight)
-- ============================================================================
SET IDENTITY_INSERT dbo.TariffPlan ON;

INSERT INTO dbo.TariffPlan (tariff_id, station_id, plan_name, start_hour, end_hour, base_rate_per_kwh, idle_fee_per_min)
VALUES 
-- Station 1: Day Peak & Overnight Super Off-Peak
(1,  1, 'Central Day Peak',            6, 22, 0.3500, 0.7500),
(2,  1, 'Central Overnight Super Off-Peak', 22,  6, 0.1500, 0.2500),

-- Station 2: Commercial Mid-Day & Standard
(3,  2, 'Downtown Standard Rate',      8, 20, 0.4000, 1.0000),
(4,  2, 'Downtown Evening Discount',  20,  8, 0.2000, 0.5000),

-- Station 3: Harbor Commercial Freight Rate
(5,  3, 'Harbor Freight Industrial',   0, 24, 0.2200, 0.3000),

-- Station 4: Airport Transit Rates
(6,  4, 'Airport Day Rush',            7, 21, 0.4500, 1.2500),
(7,  4, 'Airport Night Transit',      21,  7, 0.2500, 0.5000),

-- Station 5: Logistics Depot Flat Enterprise
(8,  5, 'Logistics Enterprise Flat',   0, 24, 0.1800, 0.2000),

-- Station 6: North Suburban Rates
(9,  6, 'Suburban Daytime',            6, 22, 0.3000, 0.5000),
(10, 6, 'Suburban Off-Peak Night',    22,  6, 0.1600, 0.2500);

SET IDENTITY_INSERT dbo.TariffPlan OFF;
PRINT 'Tariff plans seeded.';
GO

-- ============================================================================
-- 5. FLEET ORGANIZATION (4 Organizations)
-- ============================================================================
SET IDENTITY_INSERT dbo.FleetOrg ON;

INSERT INTO dbo.FleetOrg (org_id, company_name, tax_id, credit_line_limit, current_balance)
VALUES 
(1, 'Prime Global Logistics Corp', 'US-TAX-8829101', 50000.00, 12500.00),
(2, 'Metro Transit & Bus Authority', 'US-TAX-3391822', 80000.00, 4200.00),
(3, 'EcoExpress Last-Mile Delivery', 'US-TAX-7716290', 25000.00, 8900.00),
(4, 'GreenLine Courier Services LLC', 'US-TAX-9901844', 30000.00, 1500.00);

SET IDENTITY_INSERT dbo.FleetOrg OFF;
PRINT 'Fleet organizations seeded.';
GO

-- ============================================================================
-- 6. APP USER (14 Users across Roles: DRIVER, DEPOT_MANAGER, TECHNICIAN, ADMIN)
-- ============================================================================
SET IDENTITY_INSERT dbo.AppUser ON;

INSERT INTO dbo.AppUser (user_id, org_id, full_name, email, phone, user_role)
VALUES 
-- Depot Managers & Admins
(1,  1,    'Marcus Vance',       'm.vance@primelogistics.com',   '+1-555-0101', 'DEPOT_MANAGER'),
(2,  2,    'Elena Rostova',      'e.rostova@metrotransit.org',   '+1-555-0102', 'DEPOT_MANAGER'),
(3,  NULL, 'Sarah Jenkins',      'sarah.admin@evcharging.io',    '+1-555-0103', 'ADMIN'),

-- Technicians
(4,  NULL, 'David Kalu',         'd.kalu@evmaintenance.net',    '+1-555-0104', 'TECHNICIAN'),
(5,  NULL, 'Carlos Mendez',      'c.mendez@evmaintenance.net',  '+1-555-0105', 'TECHNICIAN'),

-- Commercial Fleet Drivers
(6,  1,    'James Wilson',       'j.wilson@primelogistics.com',  '+1-555-0106', 'DRIVER'),
(7,  1,    'Amina Patel',        'a.patel@primelogistics.com',   '+1-555-0107', 'DRIVER'),
(8,  2,    'Robert Chang',       'r.chang@metrotransit.org',     '+1-555-0108', 'DRIVER'),
(9,  3,    'Lucas Silva',        'l.silva@ecoexpress.com',       '+1-555-0109', 'DRIVER'),
(10, 3,    'Fatima Al-Mansoor',  'f.almansoor@ecoexpress.com',   '+1-555-0110', 'DRIVER'),
(11, 4,    'Liam O''Connor',     'l.oconnor@greenline.com',      '+1-555-0111', 'DRIVER'),

-- Retail / Independent Drivers (org_id = NULL)
(12, NULL, 'Alex Morgan',        'alex.morgan@gmail.com',        '+1-555-0112', 'DRIVER'),
(13, NULL, 'Samantha Reed',      's.reed@outlook.com',           '+1-555-0113', 'DRIVER'),
(14, NULL, 'Daniel Fischer',     'dfischer@techconsult.de',      '+1-555-0114', 'DRIVER');

SET IDENTITY_INSERT dbo.AppUser OFF;
PRINT 'App users seeded.';
GO

-- ============================================================================
-- 7. VEHICLE (12 Vehicles: Commercial Fleets, Vans, Freight, Private)
-- ============================================================================
INSERT INTO dbo.Vehicle (
    vin, org_id, user_id, license_plate, battery_capacity_kwh, max_charge_rate_kw, current_soc_pct, ownership_type
)
VALUES 
-- Prime Global Logistics (Heavy Trucks & Delivery Vans)
('1FTFW1ED8NFA00001', 1, 6,  'PL-901-TR', 180.00, 250.00, 22.00, 'FLEET'),
('1FTFW1ED8NFA00002', 1, 7,  'PL-902-TR', 180.00, 250.00, 65.00, 'FLEET'),

-- Metro Transit (Heavy Transit Buses)
('4V4NC9EH1RN00003', 2, 8,  'MT-BUS-10', 280.00, 350.00, 18.00, 'FLEET'),
('4V4NC9EH1RN00004', 2, 8,  'MT-BUS-11', 280.00, 350.00, 80.00, 'FLEET'),

-- EcoExpress Last-Mile Delivery (Electric Vans)
('2C4RC1ST9HR00005', 3, 9,  'EE-VAN-01',  95.00, 150.00, 34.00, 'FLEET'),
('2C4RC1ST9HR00006', 3, 10, 'EE-VAN-02',  95.00, 150.00, 15.00, 'FLEET'),

-- GreenLine Courier Services
('3FA6P0HD4LR00007', 4, 11, 'GL-EXP-55',  75.00, 120.00, 48.00, 'LEASED'),
('3FA6P0HD4LR00008', 4, 11, 'GL-EXP-56',  75.00, 120.00, 72.00, 'LEASED'),

-- Private / Retail Vehicles (belong to an individual registered user, assigned default fleet sponsor or retail holding org)
('5YJ3E1EB8MF00009', 1, 12, 'PRV-TES-9',  82.00, 250.00, 45.00, 'PRIVATE'),
('WAUZZZF28NA00010', 1, 13, 'PRV-AUD-4',  93.00, 270.00, 50.00, 'PRIVATE'),
('1G1RA6E42HU00011', 2, 14, 'PRV-CHV-7',  65.00, 100.00, 30.00, 'PRIVATE'),
('5YJSA1E28HF00012', 3, 9,  'EE-SUP-09', 100.00, 250.00, 60.00, 'FLEET');

PRINT 'Vehicles seeded.';
GO

-- ============================================================================
-- 8. FLEET MISSION (8 Missions with varying deadlines and target SOCs)
-- ============================================================================
SET IDENTITY_INSERT dbo.FleetMission ON;

INSERT INTO dbo.FleetMission (
    mission_id, vin, driver_id, departure_time, target_soc_pct, route_distance_km, mission_status
)
VALUES 
-- Imminent departure (1 hour from now - Highest Urgency)
(1, '1FTFW1ED8NFA00001', 6,  DATEADD(MINUTE, 60, SYSDATETIME()),  90.00, 240.00, 'SCHEDULED'),

-- Critical Metro Transit morning route (2 hours from now)
(2, '4V4NC9EH1RN00003', 8,  DATEADD(MINUTE, 120, SYSDATETIME()), 95.00, 320.00, 'SCHEDULED'),

-- EcoExpress urgent dispatch (45 mins from now - Low SOC)
(3, '2C4RC1ST9HR00006', 10, DATEADD(MINUTE, 45, SYSDATETIME()),  85.00, 180.00, 'SCHEDULED'),

-- Standard EcoExpress afternoon run (4 hours from now)
(4, '2C4RC1ST9HR00005', 9,  DATEADD(MINUTE, 240, SYSDATETIME()), 80.00, 120.00, 'SCHEDULED'),

-- Prime Logistics long-haul evening run (8 hours from now)
(5, '1FTFW1ED8NFA00002', 7,  DATEADD(HOUR, 8, SYSDATETIME()),     90.00, 450.00, 'SCHEDULED'),

-- GreenLine Courier scheduled tomorrow
(6, '3FA6P0HD4LR00007', 11, DATEADD(HOUR, 14, SYSDATETIME()),    85.00, 160.00, 'SCHEDULED'),

-- Completed historical missions
(7, '4V4NC9EH1RN00004', 8,  DATEADD(DAY, -1, SYSDATETIME()),     95.00, 300.00, 'COMPLETED'),
(8, '3FA6P0HD4LR00008', 11, DATEADD(DAY, -2, SYSDATETIME()),     80.00, 140.00, 'COMPLETED');

SET IDENTITY_INSERT dbo.FleetMission OFF;
PRINT 'Fleet missions seeded.';
GO

-- ============================================================================
-- 9. MAINTENANCE LOG (Faults on Bays 4 and 7)
-- Bay 4: Active Open Fault -> Trigger will automatically set is_operational = 0
-- Bay 7: Resolved Fault -> Trigger maintains is_operational = 1
-- ============================================================================
SET IDENTITY_INSERT dbo.MaintenanceLog ON;

INSERT INTO dbo.MaintenanceLog (
    log_id, bay_id, technician_id, issue_reported, reported_at, resolved_at, repair_status
)
VALUES 
-- Open active fault on Bay 4 (Central Depot Type2)
(1, 4, 4, 'CCS connector lock solenoid failed to release; cable insulation damaged.', DATEADD(HOUR, -5, SYSDATETIME()), NULL, 'OPEN'),

-- Resolved fault on Bay 7 (Downtown Hub)
(2, 7, 5, 'Ground fault interrupter tripped during surge; reset and re-calibrated.', DATEADD(DAY, -3, SYSDATETIME()), DATEADD(DAY, -2, SYSDATETIME()), 'RESOLVED'),

-- Resolved historical fault on Bay 1
(3, 1, 4, 'Firmware communication timeout with vehicle CAN bus controller.', DATEADD(DAY, -10, SYSDATETIME()), DATEADD(DAY, -9, SYSDATETIME()), 'RESOLVED'),

-- Open in-progress fault on Bay 16 (North Suburban)
(4, 16, 5, 'Thermal sensor reporting over-temperature warning on power inverter.', DATEADD(HOUR, -2, SYSDATETIME()), NULL, 'IN_PROGRESS');

SET IDENTITY_INSERT dbo.MaintenanceLog OFF;
PRINT 'Maintenance logs seeded (Bays 4 and 16 automatically marked non-operational).';
GO

-- ============================================================================
-- 10. RESERVATION (10 Reservations: Past, Active, Future)
-- Note: Bays 4 and 16 are non-operational, so only operational bays are reserved!
-- ============================================================================
SET IDENTITY_INSERT dbo.Reservation ON;

INSERT INTO dbo.Reservation (
    reservation_id, bay_id, vin, user_id, start_time, end_time, reservation_status
)
VALUES 
-- Past completed reservations (for historical billing demonstration)
(1, 1, '1FTFW1ED8NFA00001', 6,  DATEADD(DAY, -1, '2026-09-12 08:00:00'), DATEADD(DAY, -1, '2026-09-12 09:30:00'), 'COMPLETED'),
(2, 2, '1FTFW1ED8NFA00002', 7,  DATEADD(DAY, -1, '2026-09-12 10:00:00'), DATEADD(DAY, -1, '2026-09-12 11:15:00'), 'COMPLETED'),
(3, 8, '4V4NC9EH1RN00003', 8,  DATEADD(DAY, -1, '2026-09-12 14:00:00'), DATEADD(DAY, -1, '2026-09-12 16:00:00'), 'COMPLETED'),
(4, 5, '2C4RC1ST9HR00005', 9,  DATEADD(DAY, -1, '2026-09-12 18:00:00'), DATEADD(DAY, -1, '2026-09-12 19:00:00'), 'COMPLETED'),

-- Active reservations right now
(5, 1, '1FTFW1ED8NFA00001', 6,  DATEADD(MINUTE, -30, SYSDATETIME()), DATEADD(MINUTE, 60, SYSDATETIME()), 'ACTIVE'),
(6, 8, '4V4NC9EH1RN00003', 8,  DATEADD(MINUTE, -45, SYSDATETIME()), DATEADD(MINUTE, 75, SYSDATETIME()), 'ACTIVE'),
(7, 11, 'WAUZZZF28NA00010', 13, DATEADD(MINUTE, -15, SYSDATETIME()), DATEADD(MINUTE, 45, SYSDATETIME()), 'ACTIVE'),

-- Future upcoming reservations
(8, 2, '2C4RC1ST9HR00006', 10, DATEADD(HOUR, 2, SYSDATETIME()), DATEADD(HOUR, 3, SYSDATETIME()), 'CONFIRMED'),
(9, 3, '5YJ3E1EB8MF00009', 12, DATEADD(HOUR, 4, SYSDATETIME()), DATEADD(HOUR, 5, SYSDATETIME()), 'CONFIRMED'),
(10, 9, '3FA6P0HD4LR00007', 11, DATEADD(HOUR, 5, SYSDATETIME()), DATEADD(HOUR, 7, SYSDATETIME()), 'CONFIRMED');

SET IDENTITY_INSERT dbo.Reservation OFF;
PRINT 'Reservations seeded.';
GO

-- ============================================================================
-- 11. CHARGING SESSION (6 Sessions: 3 Completed, 3 Active Charging)
-- ============================================================================
SET IDENTITY_INSERT dbo.ChargingSession ON;

INSERT INTO dbo.ChargingSession (
    session_id, bay_id, vin, user_id, reservation_id, start_time, end_time,
    allocated_kw, energy_delivered_kwh, idle_minutes, status
)
VALUES 
-- Historical completed sessions (1, 2, 3)
(1, 1, '1FTFW1ED8NFA00001', 6, 1, 
 DATEADD(DAY, -1, '2026-09-12 08:00:00'), DATEADD(DAY, -1, '2026-09-12 09:30:00'),
 200.00, 142.500, 15, 'COMPLETED'),

(2, 2, '1FTFW1ED8NFA00002', 7, 2, 
 DATEADD(DAY, -1, '2026-09-12 10:00:00'), DATEADD(DAY, -1, '2026-09-12 11:15:00'),
 180.00, 95.200, 0, 'COMPLETED'),

(3, 8, '4V4NC9EH1RN00003', 8, 3, 
 DATEADD(DAY, -1, '2026-09-12 14:00:00'), DATEADD(DAY, -1, '2026-09-12 16:00:00'),
 300.00, 220.000, 25, 'COMPLETED'),

-- Active Sessions in progress right now (Grid Load demonstration)
-- Session 4: Station 1 (Substation 1) -> 200 kW
(4, 1, '1FTFW1ED8NFA00001', 6, 5, 
 DATEADD(MINUTE, -30, SYSDATETIME()), NULL,
 200.00, 65.000, 0, 'CHARGING'),

-- Session 5: Station 3 (Substation 2) -> 300 kW
(5, 8, '4V4NC9EH1RN00003', 8, 6, 
 DATEADD(MINUTE, -45, SYSDATETIME()), NULL,
 300.00, 130.000, 0, 'CHARGING'),

-- Session 6: Station 4 (Substation 3) -> 150 kW
(6, 11, 'WAUZZZF28NA00010', 13, 7, 
 DATEADD(MINUTE, -15, SYSDATETIME()), NULL,
 150.00, 32.500, 0, 'CHARGING');

SET IDENTITY_INSERT dbo.ChargingSession OFF;
PRINT 'Charging sessions seeded.';
GO

-- ============================================================================
-- 12. INVOICE (3 Invoices for Completed Sessions)
-- Note: total_amount is a PERSISTED computed column, so it is omitted from INSERT
-- ============================================================================
SET IDENTITY_INSERT dbo.Invoice ON;

INSERT INTO dbo.Invoice (
    invoice_id, session_id, energy_charge, idle_penalty_charge, tax_amount, status
)
VALUES 
-- Invoice 1 for Session 1: 142.5 kWh * 0.35 = $49.88, 15 min idle * $0.75 = $11.25, Tax = $11.00 -> Total = $72.13
(1, 1, 49.88, 11.25, 11.00, 'PAID'),

-- Invoice 2 for Session 2: 95.2 kWh * 0.35 = $33.32, 0 min idle, Tax = $6.00 -> Total = $39.32
(2, 2, 33.32, 0.00, 6.00, 'PARTIALLY_PAID'),

-- Invoice 3 for Session 3: 220 kWh * 0.22 = $48.40, 25 min idle * $0.30 = $7.50, Tax = $10.06 -> Total = $65.96
(3, 3, 48.40, 7.50, 10.06, 'PENDING');

SET IDENTITY_INSERT dbo.Invoice OFF;
PRINT 'Invoices seeded.';
GO

-- ============================================================================
-- 13. PAYMENT (4 Payments demonstrating Full, Partial, and Pending States)
-- ============================================================================
SET IDENTITY_INSERT dbo.Payment ON;

INSERT INTO dbo.Payment (
    payment_id, invoice_id, payment_method, paid_amount, transaction_ref, settled_at
)
VALUES 
-- Full payment for Invoice 1 via Fleet Credit Line
(1, 1, 'CREDIT_LINE', 72.13, 'TXN-PL-20260912-001', DATEADD(DAY, -1, '2026-09-12 10:00:00')),

-- Partial payment for Invoice 2 via Card ($20.00 out of $39.32)
(2, 2, 'CARD', 20.00, 'TXN-CARD-9912048-002', DATEADD(DAY, -1, '2026-09-12 12:00:00'));

SET IDENTITY_INSERT dbo.Payment OFF;
PRINT 'Payments seeded.';
GO

PRINT 'Database seed data population finished successfully.';
GO
