-- ============================================================================
-- SCRIPT: 07_create_views.sql
-- SYSTEM: Intelligent EV Charging Station and Fleet/Depot Management System
-- DIALECT: Microsoft SQL Server (T-SQL)
-- DESCRIPTION: Implements operational reporting and decision-support views:
--              1. vw_StationCapacity
--              2. vw_CurrentSubstationLoad
--              3. vw_AvailableChargerBays
--              4. vw_ChargingPriority
--              5. vw_InvoiceSummary
--              6. vw_FleetChargingSummary
--              7. vw_MaintenanceStatus
-- ============================================================================

USE EVChargingDB;
GO

-- ============================================================================
-- 1. vw_StationCapacity
-- Real-time hardware capacity, bay availability, and load by charging station
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_StationCapacity
AS
SELECT 
    cs.station_id,
    cs.station_name,
    cs.city,
    cs.status AS station_status,
    sub.substation_id,
    sub.name AS substation_name,
    COUNT(cb.bay_id) AS total_bays,
    SUM(CASE WHEN cb.is_operational = 1 THEN 1 ELSE 0 END) AS operational_bays,
    SUM(CASE WHEN cb.is_operational = 0 THEN 1 ELSE 0 END) AS offline_bays,
    ISNULL(SUM(cb.max_kw_output), 0.00) AS total_nameplate_kw_capacity,
    ISNULL(active_sessions.active_session_count, 0) AS active_session_count,
    ISNULL(active_sessions.current_power_draw_kw, 0.00) AS current_power_draw_kw
FROM dbo.ChargingStation cs
INNER JOIN dbo.Substation sub ON cs.substation_id = sub.substation_id
LEFT JOIN dbo.ChargerBay cb ON cs.station_id = cb.station_id
OUTER APPLY (
    SELECT 
        COUNT(sess.session_id) AS active_session_count,
        SUM(sess.allocated_kw) AS current_power_draw_kw
    FROM dbo.ChargingSession sess
    INNER JOIN dbo.ChargerBay b ON sess.bay_id = b.bay_id
    WHERE b.station_id = cs.station_id
      AND sess.status IN ('STARTED', 'CHARGING')
) active_sessions
GROUP BY 
    cs.station_id, cs.station_name, cs.city, cs.status,
    sub.substation_id, sub.name, active_sessions.active_session_count, active_sessions.current_power_draw_kw;
GO
PRINT 'View vw_StationCapacity created.';
GO

-- ============================================================================
-- 2. vw_CurrentSubstationLoad
-- Substation grid capacity headroom, current load, and utilization percentage
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_CurrentSubstationLoad
AS
SELECT 
    sub.substation_id,
    sub.name AS substation_name,
    sub.region_code,
    sub.max_grid_capacity_kw,
    COUNT(DISTINCT cs.station_id) AS connected_stations,
    COUNT(DISTINCT cb.bay_id) AS connected_bays,
    ISNULL(SUM(active_sessions.allocated_kw), 0.00) AS current_allocated_load_kw,
    (sub.max_grid_capacity_kw - ISNULL(SUM(active_sessions.allocated_kw), 0.00)) AS available_headroom_kw,
    ROUND(
        (ISNULL(SUM(active_sessions.allocated_kw), 0.00) / NULLIF(sub.max_grid_capacity_kw, 0)) * 100.0,
        2
    ) AS grid_utilization_pct
FROM dbo.Substation sub
LEFT JOIN dbo.ChargingStation cs ON sub.substation_id = cs.substation_id
LEFT JOIN dbo.ChargerBay cb ON cs.station_id = cb.station_id
LEFT JOIN dbo.ChargingSession active_sessions 
    ON cb.bay_id = active_sessions.bay_id 
   AND active_sessions.status IN ('STARTED', 'CHARGING')
GROUP BY 
    sub.substation_id, sub.name, sub.region_code, sub.max_grid_capacity_kw;
GO
PRINT 'View vw_CurrentSubstationLoad created.';
GO

-- ============================================================================
-- 3. vw_AvailableChargerBays
-- Operational bays currently unoccupied by active charging sessions
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_AvailableChargerBays
AS
SELECT 
    cb.bay_id,
    cb.station_id,
    cs.station_name,
    cs.city,
    cb.bay_number,
    cb.plug_type,
    cb.max_kw_output,
    cb.is_operational,
    sub.name AS substation_name,
    (sub.max_grid_capacity_kw - ISNULL(sub_load.CurrentLoad, 0.00)) AS substation_headroom_kw
FROM dbo.ChargerBay cb
INNER JOIN dbo.ChargingStation cs ON cb.station_id = cs.station_id
INNER JOIN dbo.Substation sub ON cs.substation_id = sub.substation_id
OUTER APPLY (
    SELECT SUM(sess.allocated_kw) AS CurrentLoad
    FROM dbo.ChargingSession sess
    INNER JOIN dbo.ChargerBay b ON sess.bay_id = b.bay_id
    INNER JOIN dbo.ChargingStation s ON b.station_id = s.station_id
    WHERE s.substation_id = sub.substation_id
      AND sess.status IN ('STARTED', 'CHARGING')
) sub_load
WHERE cb.is_operational = 1
  AND cs.status = 'ACTIVE'
  AND NOT EXISTS (
      SELECT 1 
      FROM dbo.ChargingSession csess 
      WHERE csess.bay_id = cb.bay_id 
        AND csess.status IN ('STARTED', 'CHARGING')
  );
GO
PRINT 'View vw_AvailableChargerBays created.';
GO

-- ============================================================================
-- 4. vw_ChargingPriority
-- Deterministic scoring algorithm for prioritizing commercial fleet charging
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_ChargingPriority
AS
SELECT 
    fm.mission_id,
    v.vin,
    ISNULL(fo.company_name, 'Independent Retail Driver') AS organization_name,
    v.license_plate,
    v.ownership_type,
    v.battery_capacity_kwh,
    v.current_soc_pct AS current_soc,
    fm.target_soc_pct AS target_soc,
    fm.departure_time,
    DATEDIFF(MINUTE, SYSDATETIME(), fm.departure_time) AS minutes_until_departure,
    ROUND(
        (v.battery_capacity_kwh * (CASE WHEN fm.target_soc_pct > v.current_soc_pct THEN (fm.target_soc_pct - v.current_soc_pct) ELSE 0 END)) / 100.0,
        2
    ) AS estimated_energy_required_kwh,
    v.max_charge_rate_kw AS vehicle_max_charge_rate_kw,
    fm.route_distance_km,
    -- Deterministic Urgency Priority Score Formula:
    ROUND(
        (CASE WHEN v.ownership_type = 'FLEET' THEN 50.0 ELSE 10.0 END)
        + (CASE WHEN fm.target_soc_pct > v.current_soc_pct THEN (fm.target_soc_pct - v.current_soc_pct) * 0.5 ELSE 0 END)
        + (CASE 
            WHEN DATEDIFF(MINUTE, SYSDATETIME(), fm.departure_time) <= 0 THEN 100.0
            WHEN DATEDIFF(MINUTE, SYSDATETIME(), fm.departure_time) <= 60 THEN 80.0
            WHEN DATEDIFF(MINUTE, SYSDATETIME(), fm.departure_time) <= 180 THEN 50.0
            WHEN DATEDIFF(MINUTE, SYSDATETIME(), fm.departure_time) <= 360 THEN 30.0
            ELSE 10.0
           END),
        2
    ) AS priority_score,
    DENSE_RANK() OVER (
        ORDER BY 
            (CASE WHEN v.ownership_type = 'FLEET' THEN 50.0 ELSE 10.0 END)
            + (CASE WHEN fm.target_soc_pct > v.current_soc_pct THEN (fm.target_soc_pct - v.current_soc_pct) * 0.5 ELSE 0 END)
            + (CASE 
                WHEN DATEDIFF(MINUTE, SYSDATETIME(), fm.departure_time) <= 0 THEN 100.0
                WHEN DATEDIFF(MINUTE, SYSDATETIME(), fm.departure_time) <= 60 THEN 80.0
                WHEN DATEDIFF(MINUTE, SYSDATETIME(), fm.departure_time) <= 180 THEN 50.0
                WHEN DATEDIFF(MINUTE, SYSDATETIME(), fm.departure_time) <= 360 THEN 30.0
                ELSE 10.0
               END) DESC,
            fm.departure_time ASC
    ) AS priority_rank
FROM dbo.FleetMission fm
INNER JOIN dbo.Vehicle v ON fm.vin = v.vin
LEFT JOIN dbo.FleetOrg fo ON v.org_id = fo.org_id
WHERE fm.mission_status = 'SCHEDULED';
GO
PRINT 'View vw_ChargingPriority created.';
GO

-- ============================================================================
-- 5. vw_InvoiceSummary
-- Full financial breakdown with paid amounts, balance due, and status
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_InvoiceSummary
AS
SELECT 
    inv.invoice_id,
    inv.session_id,
    cs.vin,
    v.license_plate,
    u.full_name AS driver_name,
    ISNULL(fo.company_name, 'Retail Customer') AS billing_account,
    stat.station_name,
    cs.energy_delivered_kwh,
    cs.idle_minutes,
    inv.energy_charge,
    inv.idle_penalty_charge,
    inv.tax_amount,
    inv.total_amount,
    ISNULL(payments.total_paid, 0.00) AS total_paid,
    (inv.total_amount - ISNULL(payments.total_paid, 0.00)) AS balance_due,
    inv.status AS invoice_status,
    inv.created_at AS invoice_date
FROM dbo.Invoice inv
INNER JOIN dbo.ChargingSession cs ON inv.session_id = cs.session_id
INNER JOIN dbo.ChargerBay cb ON cs.bay_id = cb.bay_id
INNER JOIN dbo.ChargingStation stat ON cb.station_id = stat.station_id
INNER JOIN dbo.Vehicle v ON cs.vin = v.vin
INNER JOIN dbo.AppUser u ON cs.user_id = u.user_id
LEFT JOIN dbo.FleetOrg fo ON v.org_id = fo.org_id
OUTER APPLY (
    SELECT SUM(p.paid_amount) AS total_paid
    FROM dbo.Payment p
    WHERE p.invoice_id = inv.invoice_id
) payments;
GO
PRINT 'View vw_InvoiceSummary created.';
GO

-- ============================================================================
-- 6. vw_FleetChargingSummary
-- Fleet organization portfolio metrics, consumption, expenditures, and credit
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_FleetChargingSummary
AS
SELECT 
    fo.org_id,
    fo.company_name,
    fo.tax_id,
    fo.credit_line_limit,
    fo.current_balance AS credit_utilized,
    (fo.credit_line_limit - fo.current_balance) AS available_credit,
    COUNT(DISTINCT v.vin) AS registered_vehicles,
    COUNT(DISTINCT fm.mission_id) AS scheduled_missions,
    ISNULL(SUM(cs.energy_delivered_kwh), 0.000) AS total_energy_consumed_kwh,
    ISNULL(SUM(inv.total_amount), 0.00) AS total_invoiced_amount,
    ISNULL(SUM(pay.paid_amount), 0.00) AS total_amount_settled
FROM dbo.FleetOrg fo
LEFT JOIN dbo.Vehicle v ON fo.org_id = v.org_id
LEFT JOIN dbo.FleetMission fm ON v.vin = fm.vin AND fm.mission_status = 'SCHEDULED'
LEFT JOIN dbo.ChargingSession cs ON v.vin = cs.vin AND cs.status = 'COMPLETED'
LEFT JOIN dbo.Invoice inv ON cs.session_id = inv.session_id
LEFT JOIN dbo.Payment pay ON inv.invoice_id = pay.invoice_id
GROUP BY 
    fo.org_id, fo.company_name, fo.tax_id, fo.credit_line_limit, fo.current_balance;
GO
PRINT 'View vw_FleetChargingSummary created.';
GO

-- ============================================================================
-- 7. vw_MaintenanceStatus
-- Real-time hardware health monitor across all charger bays
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_MaintenanceStatus
AS
SELECT 
    ml.log_id,
    ml.bay_id,
    cb.bay_number,
    cs.station_name,
    cs.city,
    cb.plug_type,
    cb.is_operational,
    u.full_name AS technician_name,
    ml.issue_reported,
    ml.reported_at,
    ml.resolved_at,
    ml.repair_status,
    DATEDIFF(HOUR, ml.reported_at, ISNULL(ml.resolved_at, SYSDATETIME())) AS downtime_hours
FROM dbo.MaintenanceLog ml
INNER JOIN dbo.ChargerBay cb ON ml.bay_id = cb.bay_id
INNER JOIN dbo.ChargingStation cs ON cb.station_id = cs.station_id
INNER JOIN dbo.AppUser u ON ml.technician_id = u.user_id;
GO
PRINT 'View vw_MaintenanceStatus created.';
GO

PRINT 'All views created successfully.';
GO
