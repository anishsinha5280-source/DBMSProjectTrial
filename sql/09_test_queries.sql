-- ============================================================================
-- SCRIPT: 09_test_queries.sql
-- SYSTEM: Intelligent EV Charging Station and Fleet/Depot Management System
-- DIALECT: Microsoft SQL Server (T-SQL)
-- DESCRIPTION: Implements and demonstrates the 15 required functional and business
--              rule verification tests, including positive tests and negative
--              concurrency / constraint validation tests.
-- ============================================================================

USE EVChargingDB;
GO

SET NOCOUNT ON;
PRINT '============================================================================';
PRINT 'RUNNING EV CHARGING STATION & DEPOT MANAGEMENT SYSTEM TEST SUITE';
PRINT '============================================================================';
GO

-- ============================================================================
-- TEST 1: List all charging stations supplied by a substation
-- ============================================================================
PRINT '>>> TEST 1: Charging stations supplied by Substation #1 (Central City Primary Grid)';

SELECT 
    sub.substation_id,
    sub.name AS substation_name,
    sub.max_grid_capacity_kw,
    cs.station_id,
    cs.station_name,
    cs.street_address,
    cs.city,
    cs.status AS station_status
FROM dbo.Substation sub
INNER JOIN dbo.ChargingStation cs ON sub.substation_id = cs.substation_id
WHERE sub.substation_id = 1
ORDER BY cs.station_id;
GO

-- ============================================================================
-- TEST 2: List all operational charger bays
-- ============================================================================
PRINT '>>> TEST 2: Operational charger bays across the entire network';

SELECT 
    cb.bay_id,
    cs.station_name,
    cb.bay_number,
    cb.plug_type,
    cb.max_kw_output,
    cb.is_operational
FROM dbo.ChargerBay cb
INNER JOIN dbo.ChargingStation cs ON cb.station_id = cs.station_id
WHERE cb.is_operational = 1
ORDER BY cs.station_name, cb.bay_number;
GO

-- ============================================================================
-- TEST 3: Find currently available charger bays for a given time interval
-- ============================================================================
PRINT '>>> TEST 3: Available charger bays for Station #1 between +6 hours and +8 hours';

DECLARE @test_start DATETIME2(7) = DATEADD(HOUR, 6, SYSDATETIME());
DECLARE @test_end   DATETIME2(7) = DATEADD(HOUR, 8, SYSDATETIME());

EXEC dbo.sp_GetAvailableBays 
    @p_station_id = 1,
    @p_start_time = @test_start,
    @p_end_time   = @test_end,
    @p_plug_type  = 'CCS2';
GO

-- ============================================================================
-- TEST 4: Attempt to create overlapping reservations and prove the database rejects them
-- ============================================================================
PRINT '>>> TEST 4: Attempting to create an overlapping reservation on Bay #2 (Expect rejection)';

DECLARE @t4_res_id INT;
DECLARE @t4_start DATETIME2(7) = DATEADD(HOUR, 2, SYSDATETIME());
DECLARE @t4_end   DATETIME2(7) = DATEADD(HOUR, 3, SYSDATETIME());

BEGIN TRY
    -- Existing Reservation #8 occupies Bay #2 from +2 hours to +3 hours.
    -- Attempt an overlapping reservation: +2:15 to +2:45
    PRINT 'Attempting conflicting insert: start = +2h15m, end = +2h45m on Bay #2...';
    EXEC dbo.sp_CreateReservation
        @p_bay_id         = 2,
        @p_vin            = '1FTFW1ED8NFA00002',
        @p_user_id        = 7,
        @p_start_time     = DATEADD(MINUTE, 15, @t4_start),
        @p_end_time       = DATEADD(MINUTE, 45, @t4_start),
        @p_reservation_id = @t4_res_id OUTPUT;

    PRINT 'FAILURE: Overlapping reservation was erroneously accepted!';
END TRY
BEGIN CATCH
    PRINT 'SUCCESS: Overlapping reservation rejected as expected.';
    PRINT 'Error Number: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + ' - ' + ERROR_MESSAGE();
END CATCH;
GO

-- ============================================================================
-- TEST 5: Attempt to reserve a non-operational bay and prove rejection
-- ============================================================================
PRINT '>>> TEST 5: Attempting to reserve non-operational Bay #4 (under active maintenance)';

DECLARE @t5_res_id INT;
DECLARE @t5_start DATETIME2(7) = DATEADD(HOUR, 1, SYSDATETIME());
DECLARE @t5_end   DATETIME2(7) = DATEADD(HOUR, 2, SYSDATETIME());

BEGIN TRY
    -- Bay #4 has an OPEN fault in MaintenanceLog, so is_operational = 0
    EXEC dbo.sp_CreateReservation
        @p_bay_id         = 4,
        @p_vin            = '1FTFW1ED8NFA00001',
        @p_user_id        = 6,
        @p_start_time     = @t5_start,
        @p_end_time       = @t5_end,
        @p_reservation_id = @t5_res_id OUTPUT;

    PRINT 'FAILURE: Reservation on non-operational bay was erroneously accepted!';
END TRY
BEGIN CATCH
    PRINT 'SUCCESS: Reservation on offline bay rejected as expected.';
    PRINT 'Error Number: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + ' - ' + ERROR_MESSAGE();
END CATCH;
GO

-- ============================================================================
-- TEST 6: Calculate current substation charging load
-- ============================================================================
PRINT '>>> TEST 6: Substation active electrical load, capacity, and headroom';

SELECT 
    substation_id,
    substation_name,
    max_grid_capacity_kw,
    current_allocated_load_kw,
    available_headroom_kw,
    grid_utilization_pct
FROM dbo.vw_CurrentSubstationLoad
ORDER BY substation_id;
GO

-- ============================================================================
-- TEST 7: Attempt to exceed substation capacity and prove rejection
-- ============================================================================
PRINT '>>> TEST 7: Attempting to start charging session exceeding Substation capacity';

-- Substation #1 max capacity = 1200 kW.
-- Currently Session #4 draws 200 kW, headroom is 1000 kW.
-- We create a temporary reservation and attempt to start with 1500 kW (which exceeds both bay rating and grid capacity)
DECLARE @t7_res_id INT;
DECLARE @t7_sess_id INT;
DECLARE @t7_start DATETIME2(7) = DATEADD(MINUTE, 5, SYSDATETIME());
DECLARE @t7_end   DATETIME2(7) = DATEADD(MINUTE, 65, SYSDATETIME());

BEGIN TRY
    -- Book bay 2
    EXEC dbo.sp_CreateReservation
        @p_bay_id         = 3,
        @p_vin            = '5YJSA1E28HF00012',
        @p_user_id        = 9,
        @p_start_time     = @t7_start,
        @p_end_time       = @t7_end,
        @p_reservation_id = @t7_res_id OUTPUT;

    PRINT 'Created test reservation #' + CAST(@t7_res_id AS VARCHAR(10)) + '. Now requesting 1500 kW session...';

    -- Attempt to allocate 1500 kW
    EXEC dbo.sp_StartChargingSession
        @p_reservation_id = @t7_res_id,
        @p_requested_kw   = 1500.00,
        @p_session_id     = @t7_sess_id OUTPUT;

    PRINT 'FAILURE: Grid overload session was accepted!';
END TRY
BEGIN CATCH
    PRINT 'SUCCESS: Excessive power demand was safely rejected.';
    PRINT 'Error Number: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + ' - ' + ERROR_MESSAGE();
END CATCH;
GO

-- ============================================================================
-- TEST 8: Show fleet missions ordered by urgency
-- ============================================================================
PRINT '>>> TEST 8: Fleet missions ordered by calculated urgency priority score';

SELECT 
    priority_rank,
    mission_id,
    vin,
    organization_name,
    license_plate,
    current_soc,
    target_soc,
    estimated_energy_required_kwh,
    minutes_until_departure,
    priority_score
FROM dbo.vw_ChargingPriority
ORDER BY priority_rank ASC;
GO

-- ============================================================================
-- TEST 9: Complete a charging session and automatically generate invoice
-- ============================================================================
PRINT '>>> TEST 9: Completing active Charging Session #4 and generating Invoice';

DECLARE @t9_invoice_id INT;

-- Active session 4 is running on Bay 1 (Vehicle 1FTFW1ED8NFA00001)
EXEC dbo.sp_CompleteChargingSession
    @p_session_id           = 4,
    @p_energy_delivered_kwh = 110.500,
    @p_idle_minutes         = 10,
    @p_invoice_id           = @t9_invoice_id OUTPUT;

PRINT 'Verifying generated invoice and session completion...';
SELECT 
    invoice_id,
    session_id,
    energy_charge,
    idle_penalty_charge,
    tax_amount,
    total_amount,
    status
FROM dbo.Invoice
WHERE invoice_id = @t9_invoice_id;
GO

-- ============================================================================
-- TEST 10: Record payment and update invoice status
-- ============================================================================
PRINT '>>> TEST 10: Recording payment for newly created invoice';

DECLARE @latest_inv_id INT;
SELECT @latest_inv_id = MAX(invoice_id) FROM dbo.Invoice;

DECLARE @inv_total DECIMAL(10,2);
SELECT @inv_total = total_amount FROM dbo.Invoice WHERE invoice_id = @latest_inv_id;

DECLARE @t10_payment_id INT;

PRINT 'Paying invoice #' + CAST(@latest_inv_id AS VARCHAR(10)) + ' total amount of $' + CAST(@inv_total AS VARCHAR(10)) + ' via CREDIT_LINE...';

EXEC dbo.sp_RecordPayment
    @p_invoice_id      = @latest_inv_id,
    @p_payment_method  = 'CREDIT_LINE',
    @p_paid_amount     = @inv_total,
    @p_transaction_ref = 'TXN-TEST-SETTLED-009',
    @p_payment_id      = @t10_payment_id OUTPUT;

PRINT 'Verifying updated invoice status (Expect PAID):';
SELECT 
    invoice_id,
    total_amount,
    status AS current_invoice_status,
    updated_at
FROM dbo.Invoice
WHERE invoice_id = @latest_inv_id;
GO

-- ============================================================================
-- TEST 11: Open maintenance fault and verify bay becomes non-operational
-- ============================================================================
PRINT '>>> TEST 11: Logging maintenance fault on Bay #1 (Expect is_operational = 0)';

DECLARE @t11_log_id INT;

PRINT 'Bay #1 status before maintenance:';
SELECT bay_id, bay_number, is_operational FROM dbo.ChargerBay WHERE bay_id = 1;

EXEC dbo.sp_OpenMaintenanceIssue
    @p_bay_id         = 1,
    @p_technician_id  = 4,
    @p_issue_reported = 'Coolant level low in liquid-cooled CCS cable assembly.',
    @p_log_id         = @t11_log_id OUTPUT;

PRINT 'Bay #1 status after logging fault (Expect is_operational = 0):';
SELECT bay_id, bay_number, is_operational FROM dbo.ChargerBay WHERE bay_id = 1;
GO

-- ============================================================================
-- TEST 12: Resolve maintenance fault and verify bay becomes operational
-- ============================================================================
PRINT '>>> TEST 12: Resolving maintenance fault on Bay #1 (Expect is_operational = 1)';

DECLARE @t12_log_id INT;
SELECT @t12_log_id = MAX(log_id) FROM dbo.MaintenanceLog WHERE bay_id = 1 AND repair_status = 'OPEN';

EXEC dbo.sp_ResolveMaintenanceIssue
    @p_log_id = @t12_log_id;

PRINT 'Bay #1 status after resolving fault (Expect is_operational = 1):';
SELECT bay_id, bay_number, is_operational FROM dbo.ChargerBay WHERE bay_id = 1;
GO

-- ============================================================================
-- TEST 13: Find unpaid invoices
-- ============================================================================
PRINT '>>> TEST 13: Finding all unpaid and partially paid invoices';

SELECT 
    invoice_id,
    session_id,
    billing_account,
    driver_name,
    total_amount,
    total_paid,
    balance_due,
    invoice_status
FROM dbo.vw_InvoiceSummary
WHERE invoice_status IN ('PENDING', 'PARTIALLY_PAID', 'OVERDUE')
ORDER BY balance_due DESC;
GO

-- ============================================================================
-- TEST 14: Calculate fleet organization's outstanding balance
-- ============================================================================
PRINT '>>> TEST 14: Outstanding balances, credit lines, and consumption by Fleet Org';

SELECT 
    org_id,
    company_name,
    credit_line_limit,
    credit_utilized,
    available_credit,
    registered_vehicles,
    total_energy_consumed_kwh,
    total_invoiced_amount,
    total_amount_settled
FROM dbo.vw_FleetChargingSummary
ORDER BY org_id;
GO

-- ============================================================================
-- TEST 15: Show charging energy consumption by station
-- ============================================================================
PRINT '>>> TEST 15: Total historical energy consumption and revenue by station';

SELECT 
    cs.station_id,
    cs.station_name,
    cs.city,
    COUNT(sess.session_id) AS total_sessions_completed,
    ISNULL(SUM(sess.energy_delivered_kwh), 0.000) AS total_energy_kwh,
    ISNULL(SUM(inv.total_amount), 0.00) AS total_revenue_generated
FROM dbo.ChargingStation cs
LEFT JOIN dbo.ChargerBay cb ON cs.station_id = cb.station_id
LEFT JOIN dbo.ChargingSession sess ON cb.bay_id = sess.bay_id AND sess.status = 'COMPLETED'
LEFT JOIN dbo.Invoice inv ON sess.session_id = inv.session_id
GROUP BY cs.station_id, cs.station_name, cs.city
ORDER BY total_energy_kwh DESC;
GO

PRINT '============================================================================';
PRINT 'ALL 15 TESTS EXECUTED SUCCESSFULLY.';
PRINT '============================================================================';
GO
