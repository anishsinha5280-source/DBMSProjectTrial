-- ============================================================================
-- SCRIPT: 05_create_triggers.sql
-- SYSTEM: Intelligent EV Charging Station and Fleet/Depot Management System
-- DIALECT: Microsoft SQL Server (T-SQL)
-- DESCRIPTION: Implements mission-critical business rule automation and safety
--              guards:
--              1. Reservation temporal collision prevention (SQL Server temporal range exclusion)
--              2. Maintenance fault bay operational status auto-toggle
--              3. Grid capacity limit enforcement defense-in-depth trigger
--              4. Payment invoice status auto-synchronization
-- ============================================================================

USE EVChargingDB;
GO

-- ============================================================================
-- 1. RESERVATION OVERLAP & OPERATIONAL VALIDATION TRIGGER
-- ============================================================================
CREATE OR ALTER TRIGGER dbo.trg_Reservation_ValidateAndPreventOverlap
ON dbo.Reservation
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Only evaluate if rows were inserted or relevant columns updated
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    -- RULE A: Cannot book a non-operational ChargerBay
    IF EXISTS (
        SELECT 1
        FROM inserted i
        INNER JOIN dbo.ChargerBay b ON i.bay_id = b.bay_id
        WHERE b.is_operational = 0
          AND i.reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE')
    )
    BEGIN
        THROW 50001, 'Reservation rejected: The requested charger bay is currently non-operational or under maintenance.', 1;
    END

    -- RULE B: Bay Temporal Collision Prevention
    -- Temporal Overlap Condition: existing.start_time < new.end_time AND existing.end_time > new.start_time
    IF EXISTS (
        SELECT 1
        FROM inserted i
        INNER JOIN dbo.Reservation r
            ON i.bay_id = r.bay_id
            AND i.reservation_id <> r.reservation_id
        WHERE i.reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE')
          AND r.reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE')
          AND r.start_time < i.end_time
          AND r.end_time > i.start_time
    )
    BEGIN
        THROW 50002, 'Double booking rejected: The requested charger bay is already reserved during the specified time interval.', 1;
    END

    -- RULE C: Vehicle Collision Prevention (A vehicle cannot be reserved at two bays at the same time)
    IF EXISTS (
        SELECT 1
        FROM inserted i
        INNER JOIN dbo.Reservation r
            ON i.vin = r.vin
            AND i.reservation_id <> r.reservation_id
        WHERE i.reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE')
          AND r.reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE')
          AND r.start_time < i.end_time
          AND r.end_time > i.start_time
    )
    BEGIN
        THROW 50003, 'Vehicle conflict rejected: The specified vehicle already has an active reservation during this time window.', 1;
    END
END;
GO
PRINT 'Trigger trg_Reservation_ValidateAndPreventOverlap created.';
GO

-- ============================================================================
-- 2. MAINTENANCE LOG AUTO-TOGGLE CHARGER BAY OPERATIONAL STATUS
-- ============================================================================
CREATE OR ALTER TRIGGER dbo.trg_MaintenanceLog_BayStatusSync
ON dbo.MaintenanceLog
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- Collect all affected bay IDs from inserted and deleted tables
    DECLARE @AffectedBays TABLE (bay_id INT PRIMARY KEY);

    INSERT INTO @AffectedBays (bay_id)
    SELECT DISTINCT bay_id FROM inserted
    UNION
    SELECT DISTINCT bay_id FROM deleted;

    -- For each affected bay, update is_operational:
    -- If there is at least one OPEN or IN_PROGRESS fault, is_operational = 0
    -- If all faults are RESOLVED or CANCELLED (or no faults exist), is_operational = 1
    UPDATE b
    SET b.is_operational = CASE
            WHEN EXISTS (
                SELECT 1
                FROM dbo.MaintenanceLog m
                WHERE m.bay_id = b.bay_id
                  AND m.repair_status IN ('OPEN', 'IN_PROGRESS')
            ) THEN 0
            ELSE 1
        END,
        b.updated_at = SYSDATETIME()
    FROM dbo.ChargerBay b
    INNER JOIN @AffectedBays ab ON b.bay_id = ab.bay_id;
END;
GO
PRINT 'Trigger trg_MaintenanceLog_BayStatusSync created.';
GO

-- ============================================================================
-- 3. GRID CAPACITY & HARDWARE RATINGS ENFORCEMENT TRIGGER
-- ============================================================================
CREATE OR ALTER TRIGGER dbo.trg_ChargingSession_EnforceGridCapacity
ON dbo.ChargingSession
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    -- RULE A: Allocated power cannot exceed ChargerBay.max_kw_output
    IF EXISTS (
        SELECT 1
        FROM inserted i
        INNER JOIN dbo.ChargerBay cb ON i.bay_id = cb.bay_id
        WHERE i.allocated_kw > cb.max_kw_output
          AND i.status IN ('STARTED', 'CHARGING')
    )
    BEGIN
        THROW 50010, 'Safety limit exceeded: Requested allocated power exceeds maximum charger bay hardware output.', 1;
    END

    -- RULE B: Allocated power cannot exceed Vehicle.max_charge_rate_kw
    IF EXISTS (
        SELECT 1
        FROM inserted i
        INNER JOIN dbo.Vehicle v ON i.vin = v.vin
        WHERE i.allocated_kw > v.max_charge_rate_kw
          AND i.status IN ('STARTED', 'CHARGING')
    )
    BEGIN
        THROW 50011, 'Safety limit exceeded: Requested allocated power exceeds vehicle onboard charging rate acceptance limit.', 1;
    END

    -- RULE C: Upstream Substation Grid Capacity check
    -- For any substation affected by active sessions in the inserted batch:
    IF EXISTS (
        SELECT sub.substation_id
        FROM dbo.Substation sub
        WHERE sub.substation_id IN (
            SELECT DISTINCT cs_station.substation_id
            FROM inserted ins
            INNER JOIN dbo.ChargerBay ins_bay ON ins.bay_id = ins_bay.bay_id
            INNER JOIN dbo.ChargingStation cs_station ON ins_bay.station_id = cs_station.station_id
            WHERE ins.status IN ('STARTED', 'CHARGING')
        )
        AND (
            SELECT ISNULL(SUM(active_session.allocated_kw), 0.00)
            FROM dbo.ChargingSession active_session
            INNER JOIN dbo.ChargerBay active_bay ON active_session.bay_id = active_bay.bay_id
            INNER JOIN dbo.ChargingStation station_conn ON active_bay.station_id = station_conn.station_id
            WHERE station_conn.substation_id = sub.substation_id
              AND active_session.status IN ('STARTED', 'CHARGING')
        ) > sub.max_grid_capacity_kw
    )
    BEGIN
        THROW 50012, 'Grid capacity exceeded: Total active load under the supplying substation would exceed maximum licensed grid capacity.', 1;
    END
END;
GO
PRINT 'Trigger trg_ChargingSession_EnforceGridCapacity created.';
GO

-- ============================================================================
-- 4. PAYMENT AUTO-UPDATE INVOICE STATUS TRIGGER
-- ============================================================================
CREATE OR ALTER TRIGGER dbo.trg_Payment_SyncInvoiceStatus
ON dbo.Payment
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- Collect affected invoice IDs
    DECLARE @AffectedInvoices TABLE (invoice_id INT PRIMARY KEY);

    INSERT INTO @AffectedInvoices (invoice_id)
    SELECT DISTINCT invoice_id FROM inserted
    UNION
    SELECT DISTINCT invoice_id FROM deleted;

    -- Synchronize Invoice status based on total paid amount vs total_amount
    UPDATE inv
    SET inv.status = CASE
            WHEN ISNULL(pay.TotalPaid, 0.00) >= inv.total_amount AND inv.total_amount > 0 THEN 'PAID'
            WHEN ISNULL(pay.TotalPaid, 0.00) > 0.00 AND ISNULL(pay.TotalPaid, 0.00) < inv.total_amount THEN 'PARTIALLY_PAID'
            WHEN ISNULL(pay.TotalPaid, 0.00) = 0.00 AND inv.status NOT IN ('CANCELLED', 'OVERDUE') THEN 'PENDING'
            ELSE inv.status
        END,
        inv.updated_at = SYSDATETIME()
    FROM dbo.Invoice inv
    INNER JOIN @AffectedInvoices ai ON inv.invoice_id = ai.invoice_id
    OUTER APPLY (
        SELECT SUM(p.paid_amount) AS TotalPaid
        FROM dbo.Payment p
        WHERE p.invoice_id = inv.invoice_id
    ) pay;
END;
GO
PRINT 'Trigger trg_Payment_SyncInvoiceStatus created.';
GO

PRINT 'All triggers created successfully.';
GO
