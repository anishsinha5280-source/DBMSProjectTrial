-- ============================================================================
-- SCRIPT: 04_create_indexes.sql
-- SYSTEM: Intelligent EV Charging Station and Fleet/Depot Management System
-- DIALECT: Microsoft SQL Server (T-SQL)
-- DESCRIPTION: Creates targeted indexes for foreign keys, join performance,
--              concurrency optimization, temporal overlap lookups, and grid
--              capacity calculations. Includes filtered indexes where appropriate.
-- ============================================================================

USE EVChargingDB;
GO

PRINT 'Creating performance and relational indexes...';

-- 1. ChargingStation foreign key to Substation
-- Speeds up upstream grid load aggregation across all stations under a substation
CREATE NONCLUSTERED INDEX IX_ChargingStation_SubstationId
ON dbo.ChargingStation (substation_id)
INCLUDE (station_name, status);
GO

-- 2. ChargerBay foreign key to ChargingStation
-- Speeds up bay retrieval and status checks per station
CREATE NONCLUSTERED INDEX IX_ChargerBay_StationId
ON dbo.ChargerBay (station_id)
INCLUDE (bay_number, plug_type, max_kw_output, is_operational);
GO

-- 3. TariffPlan foreign key to ChargingStation
-- Speeds up hourly tariff rate resolution during session completion
CREATE NONCLUSTERED INDEX IX_TariffPlan_StationId_Hours
ON dbo.TariffPlan (station_id, start_hour, end_hour)
INCLUDE (base_rate_per_kwh, idle_fee_per_min);
GO

-- 4. AppUser foreign key to FleetOrg
CREATE NONCLUSTERED INDEX IX_AppUser_OrgId
ON dbo.AppUser (org_id)
INCLUDE (full_name, email, user_role);
GO

-- 5. Vehicle foreign keys
CREATE NONCLUSTERED INDEX IX_Vehicle_OrgId
ON dbo.Vehicle (org_id)
INCLUDE (license_plate, battery_capacity_kwh, current_soc_pct, ownership_type);
GO

CREATE NONCLUSTERED INDEX IX_Vehicle_UserId
ON dbo.Vehicle (user_id)
INCLUDE (vin, license_plate);
GO

-- 6. FleetMission foreign keys and temporal queries
CREATE NONCLUSTERED INDEX IX_FleetMission_Vin
ON dbo.FleetMission (vin)
INCLUDE (departure_time, target_soc_pct, mission_status);
GO

CREATE NONCLUSTERED INDEX IX_FleetMission_DriverId
ON dbo.FleetMission (driver_id)
INCLUDE (departure_time, mission_status);
GO

-- Speeds up mission dispatch and priority scheduling queries ordered by departure time
CREATE NONCLUSTERED INDEX IX_FleetMission_DepartureTime
ON dbo.FleetMission (departure_time, mission_status)
INCLUDE (vin, driver_id, target_soc_pct, route_distance_km);
GO

-- 7. Reservation indexes (Critical for temporal collision detection)
CREATE NONCLUSTERED INDEX IX_Reservation_UserId
ON dbo.Reservation (user_id)
INCLUDE (bay_id, vin, start_time, end_time, reservation_status);
GO

-- Composite covering index for bay reservation overlap checks
CREATE NONCLUSTERED INDEX IX_Reservation_Bay_TimeRange
ON dbo.Reservation (bay_id, start_time, end_time)
INCLUDE (reservation_status, vin, user_id);
GO

-- Composite covering index for vehicle reservation overlap checks (prevents double-reserving same car)
CREATE NONCLUSTERED INDEX IX_Reservation_Vehicle_TimeRange
ON dbo.Reservation (vin, start_time, end_time)
INCLUDE (reservation_status, bay_id, user_id);
GO

-- Filtered index on active reservations to make concurrency locks and overlap searches extremely fast
CREATE NONCLUSTERED INDEX IX_Reservation_ActiveOnly
ON dbo.Reservation (bay_id, start_time, end_time)
INCLUDE (vin, reservation_status)
WHERE reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE');
GO

-- 8. ChargingSession indexes
CREATE NONCLUSTERED INDEX IX_ChargingSession_BayId
ON dbo.ChargingSession (bay_id)
INCLUDE (vin, status, allocated_kw, start_time, end_time);
GO

CREATE NONCLUSTERED INDEX IX_ChargingSession_Vin
ON dbo.ChargingSession (vin)
INCLUDE (status, energy_delivered_kwh, start_time, end_time);
GO

CREATE NONCLUSTERED INDEX IX_ChargingSession_UserId
ON dbo.ChargingSession (user_id)
INCLUDE (session_id, status);
GO

CREATE NONCLUSTERED INDEX IX_ChargingSession_ReservationId
ON dbo.ChargingSession (reservation_id)
INCLUDE (status, allocated_kw);
GO

-- Filtered index for Grid Capacity calculations:
-- Only scans active sessions that actually consume electrical grid power
CREATE NONCLUSTERED INDEX IX_ChargingSession_ActiveGridLoad
ON dbo.ChargingSession (bay_id, allocated_kw)
INCLUDE (vin, status)
WHERE status IN ('STARTED', 'CHARGING');
GO

-- 9. MaintenanceLog indexes
CREATE NONCLUSTERED INDEX IX_MaintenanceLog_BayId
ON dbo.MaintenanceLog (bay_id, repair_status)
INCLUDE (reported_at, resolved_at);
GO

CREATE NONCLUSTERED INDEX IX_MaintenanceLog_TechnicianId
ON dbo.MaintenanceLog (technician_id)
INCLUDE (repair_status, reported_at);
GO

-- Filtered index for unresolved faults (used by triggers to toggle bay operational status)
CREATE NONCLUSTERED INDEX IX_MaintenanceLog_UnresolvedFaults
ON dbo.MaintenanceLog (bay_id, repair_status)
WHERE repair_status IN ('OPEN', 'IN_PROGRESS');
GO

-- 10. Payment indexes
CREATE NONCLUSTERED INDEX IX_Payment_InvoiceId
ON dbo.Payment (invoice_id)
INCLUDE (paid_amount, payment_method, settled_at);
GO

PRINT 'All indexes created successfully.';
GO
