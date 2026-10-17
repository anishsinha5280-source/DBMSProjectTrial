-- ============================================================================
-- SCRIPT: 06_create_procedures.sql
-- SYSTEM: Intelligent EV Charging Station and Fleet/Depot Management System
-- DIALECT: Microsoft SQL Server (T-SQL)
-- DESCRIPTION: Implements transactional, production-grade stored procedures:
--              1. sp_CreateReservation
--              2. sp_CancelReservation
--              3. sp_StartChargingSession (Smart Grid Capacity serialization)
--              4. sp_CompleteChargingSession (Automated Billing and Invoicing)
--              5. sp_RecordPayment (Credit line and invoice auto-settlement)
--              6. sp_OpenMaintenanceIssue
--              7. sp_ResolveMaintenanceIssue
--              8. sp_GetChargingPriority
--              9. sp_GetAvailableBays
-- ============================================================================

USE EVChargingDB;
GO

-- ============================================================================
-- 1. sp_CreateReservation
-- Prevents double bookings and vehicle time conflicts using serialized locking
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateReservation
    @p_bay_id          INT,
    @p_vin             VARCHAR(17),
    @p_user_id         INT,
    @p_start_time      DATETIME2(7),
    @p_end_time        DATETIME2(7),
    @p_reservation_id  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- Parameter validation
        IF @p_start_time >= @p_end_time
        BEGIN
            THROW 51001, 'Invalid reservation window: start_time must be strictly before end_time.', 1;
        END

        IF @p_start_time < DATEADD(MINUTE, -15, SYSDATETIME())
        BEGIN
            THROW 51002, 'Invalid reservation window: cannot create reservations in the past.', 1;
        END

        BEGIN TRANSACTION;

        -- 1. Check ChargerBay operational status with lock
        DECLARE @is_operational BIT;
        DECLARE @station_status VARCHAR(20);

        SELECT 
            @is_operational = cb.is_operational,
            @station_status = cs.status
        FROM dbo.ChargerBay cb WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.ChargingStation cs ON cb.station_id = cs.station_id
        WHERE cb.bay_id = @p_bay_id;

        IF @is_operational IS NULL
        BEGIN
            THROW 51003, 'Specified charger bay does not exist.', 1;
        END

        IF @station_status <> 'ACTIVE'
        BEGIN
            THROW 51004, 'Charging station is currently not ACTIVE.', 1;
        END

        IF @is_operational = 0
        BEGIN
            THROW 51005, 'Charger bay is currently out of service or undergoing maintenance.', 1;
        END

        -- 2. Validate Vehicle exists
        IF NOT EXISTS (SELECT 1 FROM dbo.Vehicle WHERE vin = @p_vin)
        BEGIN
            THROW 51006, 'Specified vehicle VIN does not exist.', 1;
        END

        -- 3. Validate User exists
        IF NOT EXISTS (SELECT 1 FROM dbo.AppUser WHERE user_id = @p_user_id)
        BEGIN
            THROW 51007, 'Specified user does not exist.', 1;
        END

        -- 4. Check for bay schedule collision (HoldLock prevents race conditions)
        IF EXISTS (
            SELECT 1
            FROM dbo.Reservation WITH (UPDLOCK, HOLDLOCK)
            WHERE bay_id = @p_bay_id
              AND reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE')
              AND start_time < @p_end_time
              AND end_time > @p_start_time
        )
        BEGIN
            THROW 51008, 'Reservation conflict: Charger bay is already booked for an overlapping time interval.', 1;
        END

        -- 5. Check for vehicle schedule collision
        IF EXISTS (
            SELECT 1
            FROM dbo.Reservation WITH (UPDLOCK, HOLDLOCK)
            WHERE vin = @p_vin
              AND reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE')
              AND start_time < @p_end_time
              AND end_time > @p_start_time
        )
        BEGIN
            THROW 51009, 'Reservation conflict: Vehicle is already scheduled for charging at another bay during this interval.', 1;
        END

        -- 6. Insert confirmed reservation
        INSERT INTO dbo.Reservation (
            bay_id, vin, user_id, start_time, end_time, reservation_status
        )
        VALUES (
            @p_bay_id, @p_vin, @p_user_id, @p_start_time, @p_end_time, 'CONFIRMED'
        );

        SET @p_reservation_id = SCOPE_IDENTITY();

        COMMIT TRANSACTION;
        PRINT 'Reservation #' + CAST(@p_reservation_id AS VARCHAR(10)) + ' created successfully.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
PRINT 'Procedure sp_CreateReservation created.';
GO

-- ============================================================================
-- 2. sp_CancelReservation
-- Safely cancels a pending or confirmed reservation
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.sp_CancelReservation
    @p_reservation_id INT,
    @p_user_id        INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @current_status VARCHAR(20);
        DECLARE @res_user_id INT;

        SELECT 
            @current_status = reservation_status,
            @res_user_id = user_id
        FROM dbo.Reservation WITH (UPDLOCK)
        WHERE reservation_id = @p_reservation_id;

        IF @current_status IS NULL
        BEGIN
            THROW 52001, 'Reservation not found.', 1;
        END

        IF @current_status IN ('COMPLETED', 'CANCELLED', 'ACTIVE')
        BEGIN
            THROW 52002, 'Cannot cancel reservation in its current status.', 1;
        END

        UPDATE dbo.Reservation
        SET reservation_status = 'CANCELLED',
            updated_at = SYSDATETIME()
        WHERE reservation_id = @p_reservation_id;

        COMMIT TRANSACTION;
        PRINT 'Reservation #' + CAST(@p_reservation_id AS VARCHAR(10)) + ' cancelled successfully.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
PRINT 'Procedure sp_CancelReservation created.';
GO

-- ============================================================================
-- 3. sp_StartChargingSession
-- Enforces Grid Capacity, Substation Headroom, Bay Rating & Vehicle Ingestion limits
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.sp_StartChargingSession
    @p_reservation_id INT,
    @p_requested_kw   DECIMAL(8,2),
    @p_session_id     INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Fetch Reservation details
        DECLARE @bay_id INT;
        DECLARE @vin VARCHAR(17);
        DECLARE @user_id INT;
        DECLARE @res_status VARCHAR(20);

        SELECT 
            @bay_id = bay_id,
            @vin = vin,
            @user_id = user_id,
            @res_status = reservation_status
        FROM dbo.Reservation WITH (UPDLOCK)
        WHERE reservation_id = @p_reservation_id;

        IF @bay_id IS NULL
        BEGIN
            THROW 53001, 'Reservation not found.', 1;
        END

        IF @res_status NOT IN ('PENDING', 'CONFIRMED')
        BEGIN
            THROW 53002, 'Charging session can only be initiated for PENDING or CONFIRMED reservations.', 1;
        END

        -- 2. Validate Bay hardware and operational readiness
        DECLARE @bay_max_kw DECIMAL(8,2);
        DECLARE @is_operational BIT;
        DECLARE @station_id INT;

        SELECT 
            @bay_max_kw = max_kw_output,
            @is_operational = is_operational,
            @station_id = station_id
        FROM dbo.ChargerBay WITH (UPDLOCK)
        WHERE bay_id = @bay_id;

        IF @is_operational = 0
        BEGIN
            THROW 53003, 'Cannot start session: Charger bay is non-operational or undergoing maintenance.', 1;
        END

        IF @p_requested_kw > @bay_max_kw
        BEGIN
            THROW 53004, 'Requested power exceeds maximum charger bay hardware capacity.', 1;
        END

        -- 3. Validate Vehicle onboard maximum charging rate
        DECLARE @vehicle_max_rate DECIMAL(8,2);
        SELECT @vehicle_max_rate = max_charge_rate_kw
        FROM dbo.Vehicle
        WHERE vin = @vin;

        IF @p_requested_kw > @vehicle_max_rate
        BEGIN
            THROW 53005, 'Requested power exceeds vehicle onboard charging rate limit.', 1;
        END

        -- 4. Serialize Substation grid capacity check with UPDLOCK and HOLDLOCK
        DECLARE @substation_id INT;
        DECLARE @max_grid_capacity DECIMAL(10,2);

        SELECT 
            @substation_id = sub.substation_id,
            @max_grid_capacity = sub.max_grid_capacity_kw
        FROM dbo.ChargingStation cs
        INNER JOIN dbo.Substation sub WITH (UPDLOCK, HOLDLOCK) ON cs.substation_id = sub.substation_id
        WHERE cs.station_id = @station_id;

        -- Calculate current active load across all stations powered by this substation
        DECLARE @current_substation_load DECIMAL(10,2);
        SELECT @current_substation_load = ISNULL(SUM(csess.allocated_kw), 0.00)
        FROM dbo.ChargingSession csess
        INNER JOIN dbo.ChargerBay cb ON csess.bay_id = cb.bay_id
        INNER JOIN dbo.ChargingStation cs ON cb.station_id = cs.station_id
        WHERE cs.substation_id = @substation_id
          AND csess.status IN ('STARTED', 'CHARGING');

        DECLARE @available_headroom DECIMAL(10,2);
        SET @available_headroom = @max_grid_capacity - @current_substation_load;

        IF @p_requested_kw > @available_headroom
        BEGIN
            DECLARE @errMsg VARCHAR(300);
            SET @errMsg = 'Grid capacity constrained: Substation #' + CAST(@substation_id AS VARCHAR(10)) 
                        + ' has only ' + CAST(@available_headroom AS VARCHAR(15)) + ' kW available headroom. '
                        + 'Requested: ' + CAST(@p_requested_kw AS VARCHAR(15)) + ' kW. Session rejected.';
            THROW 53006, @errMsg, 1;
        END

        -- 5. Create Charging Session
        INSERT INTO dbo.ChargingSession (
            bay_id, vin, user_id, reservation_id, start_time,
            allocated_kw, energy_delivered_kwh, idle_minutes, status
        )
        VALUES (
            @bay_id, @vin, @user_id, @p_reservation_id, SYSDATETIME(),
            @p_requested_kw, 0.000, 0, 'CHARGING'
        );

        SET @p_session_id = SCOPE_IDENTITY();

        -- 6. Transition reservation status to ACTIVE
        UPDATE dbo.Reservation
        SET reservation_status = 'ACTIVE',
            updated_at = SYSDATETIME()
        WHERE reservation_id = @p_reservation_id;

        COMMIT TRANSACTION;
        PRINT 'Charging Session #' + CAST(@p_session_id AS VARCHAR(10)) + ' started at ' + CAST(@p_requested_kw AS VARCHAR(10)) + ' kW.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
PRINT 'Procedure sp_StartChargingSession created.';
GO

-- ============================================================================
-- 4. sp_CompleteChargingSession
-- Finalizes session, computes tariff rates & idle penalties, and creates Invoice
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.sp_CompleteChargingSession
    @p_session_id           INT,
    @p_energy_delivered_kwh DECIMAL(10,3),
    @p_idle_minutes         INT,
    @p_invoice_id           INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @bay_id INT;
        DECLARE @vin VARCHAR(17);
        DECLARE @reservation_id INT;
        DECLARE @session_status VARCHAR(20);
        DECLARE @session_start DATETIME2(7);
        DECLARE @station_id INT;
        DECLARE @battery_capacity DECIMAL(8,2);
        DECLARE @current_soc DECIMAL(5,2);

        SELECT 
            @bay_id = cs.bay_id,
            @vin = cs.vin,
            @reservation_id = cs.reservation_id,
            @session_status = cs.status,
            @session_start = cs.start_time,
            @station_id = cb.station_id,
            @battery_capacity = v.battery_capacity_kwh,
            @current_soc = v.current_soc_pct
        FROM dbo.ChargingSession cs WITH (UPDLOCK)
        INNER JOIN dbo.ChargerBay cb ON cs.bay_id = cb.bay_id
        INNER JOIN dbo.Vehicle v ON cs.vin = v.vin
        WHERE cs.session_id = @p_session_id;

        IF @session_status IS NULL
        BEGIN
            THROW 54001, 'Charging session not found.', 1;
        END

        IF @session_status NOT IN ('STARTED', 'CHARGING')
        BEGIN
            THROW 54002, 'Charging session is not currently active.', 1;
        END

        IF @p_energy_delivered_kwh < 0.000 OR @p_idle_minutes < 0
        BEGIN
            THROW 54003, 'Energy delivered and idle minutes must be non-negative values.', 1;
        END

        DECLARE @end_time DATETIME2(7) = SYSDATETIME();
        DECLARE @session_hour INT = DATEPART(HOUR, @session_start);

        -- Determine applicable tariff plan for this station at session start hour
        -- Handles both standard Daytime hours (start <= end) and Overnight wrapping hours (start > end)
        DECLARE @base_rate DECIMAL(10,4) = 0.2500; -- Default fallback rate
        DECLARE @idle_rate DECIMAL(10,4) = 0.5000; -- Default fallback idle rate

        SELECT TOP 1
            @base_rate = base_rate_per_kwh,
            @idle_rate = idle_fee_per_min
        FROM dbo.TariffPlan
        WHERE station_id = @station_id
          AND (
                (start_hour <= end_hour AND @session_hour >= start_hour AND @session_hour < end_hour)
             OR (start_hour > end_hour  AND (@session_hour >= start_hour OR @session_hour < end_hour))
          )
        ORDER BY tariff_id DESC;

        -- Financial calculations
        DECLARE @energy_charge DECIMAL(10,2);
        DECLARE @idle_penalty_charge DECIMAL(10,2);
        DECLARE @tax_amount DECIMAL(10,2);

        SET @energy_charge = ROUND(@p_energy_delivered_kwh * @base_rate, 2);
        SET @idle_penalty_charge = ROUND(@p_idle_minutes * @idle_rate, 2);
        SET @tax_amount = ROUND((@energy_charge + @idle_penalty_charge) * 0.18, 2); -- 18% statutory tax

        -- 1. Create Invoice (total_amount is PERSISTED computed column)
        INSERT INTO dbo.Invoice (
            session_id, energy_charge, idle_penalty_charge, tax_amount, status
        )
        VALUES (
            @p_session_id, @energy_charge, @idle_penalty_charge, @tax_amount, 'PENDING'
        );

        SET @p_invoice_id = SCOPE_IDENTITY();

        -- 2. Mark ChargingSession COMPLETED
        UPDATE dbo.ChargingSession
        SET end_time = @end_time,
            energy_delivered_kwh = @p_energy_delivered_kwh,
            idle_minutes = @p_idle_minutes,
            status = 'COMPLETED',
            updated_at = SYSDATETIME()
        WHERE session_id = @p_session_id;

        -- 3. Mark Reservation COMPLETED
        UPDATE dbo.Reservation
        SET reservation_status = 'COMPLETED',
            updated_at = SYSDATETIME()
        WHERE reservation_id = @p_reservation_id;

        -- 4. Update Vehicle SOC based on energy delivered
        IF @battery_capacity > 0
        BEGIN
            DECLARE @new_soc DECIMAL(5,2);
            SET @new_soc = @current_soc + ((@p_energy_delivered_kwh / @battery_capacity) * 100.00);
            IF @new_soc > 100.00 SET @new_soc = 100.00;

            UPDATE dbo.Vehicle
            SET current_soc_pct = @new_soc,
                updated_at = SYSDATETIME()
            WHERE vin = @vin;
        END

        COMMIT TRANSACTION;
        PRINT 'Session #' + CAST(@p_session_id AS VARCHAR(10)) + ' completed. Generated Invoice #' + CAST(@p_invoice_id AS VARCHAR(10)) + '.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
PRINT 'Procedure sp_CompleteChargingSession created.';
GO

-- ============================================================================
-- 5. sp_RecordPayment
-- Records payment, validates credit lines, and triggers invoice status updates
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.sp_RecordPayment
    @p_invoice_id      INT,
    @p_payment_method  VARCHAR(20),
    @p_paid_amount     DECIMAL(10,2),
    @p_transaction_ref VARCHAR(100),
    @p_payment_id      INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Validate Invoice
        DECLARE @invoice_status VARCHAR(20);
        DECLARE @total_amount DECIMAL(10,2);
        DECLARE @session_id INT;

        SELECT 
            @invoice_status = status,
            @total_amount = total_amount,
            @session_id = session_id
        FROM dbo.Invoice WITH (UPDLOCK)
        WHERE invoice_id = @p_invoice_id;

        IF @invoice_status IS NULL
        BEGIN
            THROW 55001, 'Invoice not found.', 1;
        END

        IF @invoice_status = 'PAID'
        BEGIN
            THROW 55002, 'Invoice has already been settled in full.', 1;
        END

        IF @invoice_status = 'CANCELLED'
        BEGIN
            THROW 55003, 'Cannot process payment for a cancelled invoice.', 1;
        END

        IF @p_paid_amount <= 0.00
        BEGIN
            THROW 55004, 'Payment amount must be greater than zero.', 1;
        END

        -- 2. If CREDIT_LINE payment, validate fleet organization credit limits
        IF @p_payment_method = 'CREDIT_LINE'
        BEGIN
            DECLARE @org_id INT;
            DECLARE @credit_limit DECIMAL(12,2);
            DECLARE @current_balance DECIMAL(12,2);

            SELECT 
                @org_id = fo.org_id,
                @credit_limit = fo.credit_line_limit,
                @current_balance = fo.current_balance
            FROM dbo.Invoice inv
            INNER JOIN dbo.ChargingSession cs ON inv.session_id = cs.session_id
            INNER JOIN dbo.Vehicle v ON cs.vin = v.vin
            INNER JOIN dbo.FleetOrg fo WITH (UPDLOCK) ON v.org_id = fo.org_id
            WHERE inv.invoice_id = @p_invoice_id;

            IF @org_id IS NULL
            BEGIN
                THROW 55005, 'Credit line payment rejected: Vehicle or user is not enrolled under an enterprise Fleet Organization.', 1;
            END

            IF (@current_balance + @p_paid_amount) > @credit_limit
            BEGIN
                DECLARE @creditErr VARCHAR(250);
                SET @creditErr = 'Credit line limit exceeded for organization #' + CAST(@org_id AS VARCHAR(10))
                               + '. Credit Limit: ' + CAST(@credit_limit AS VARCHAR(15))
                               + ', Current Balance: ' + CAST(@current_balance AS VARCHAR(15))
                               + ', Requested Charge: ' + CAST(@p_paid_amount AS VARCHAR(15));
                THROW 55006, @creditErr, 1;
            END

            -- Increase fleet organization utilized balance
            UPDATE dbo.FleetOrg
            SET current_balance = current_balance + @p_paid_amount,
                updated_at = SYSDATETIME()
            WHERE org_id = @org_id;
        END

        -- 3. Insert Payment record (trg_Payment_SyncInvoiceStatus will auto-update invoice status)
        INSERT INTO dbo.Payment (
            invoice_id, payment_method, paid_amount, transaction_ref, settled_at
        )
        VALUES (
            @p_invoice_id, @p_payment_method, @p_paid_amount, @p_transaction_ref, SYSDATETIME()
        );

        SET @p_payment_id = SCOPE_IDENTITY();

        COMMIT TRANSACTION;
        PRINT 'Payment #' + CAST(@p_payment_id AS VARCHAR(10)) + ' of $' + CAST(@p_paid_amount AS VARCHAR(10)) + ' recorded successfully.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
PRINT 'Procedure sp_RecordPayment created.';
GO

-- ============================================================================
-- 6. sp_OpenMaintenanceIssue
-- Automatically logs maintenance fault and deactivates charger bay
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.sp_OpenMaintenanceIssue
    @p_bay_id         INT,
    @p_technician_id  INT,
    @p_issue_reported VARCHAR(500),
    @p_log_id         INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM dbo.ChargerBay WHERE bay_id = @p_bay_id)
        BEGIN
            THROW 56001, 'Specified charger bay does not exist.', 1;
        END

        IF NOT EXISTS (
            SELECT 1 FROM dbo.AppUser 
            WHERE user_id = @p_technician_id 
              AND user_role IN ('TECHNICIAN', 'ADMIN', 'DEPOT_MANAGER')
        )
        BEGIN
            THROW 56002, 'Technician must have role TECHNICIAN, ADMIN, or DEPOT_MANAGER.', 1;
        END

        INSERT INTO dbo.MaintenanceLog (
            bay_id, technician_id, issue_reported, reported_at, repair_status
        )
        VALUES (
            @p_bay_id, @p_technician_id, @p_issue_reported, SYSDATETIME(), 'OPEN'
        );

        SET @p_log_id = SCOPE_IDENTITY();

        -- Note: Trigger trg_MaintenanceLog_BayStatusSync automatically sets is_operational = 0

        COMMIT TRANSACTION;
        PRINT 'Maintenance Issue #' + CAST(@p_log_id AS VARCHAR(10)) + ' logged. Bay #' + CAST(@p_bay_id AS VARCHAR(10)) + ' taken offline.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
PRINT 'Procedure sp_OpenMaintenanceIssue created.';
GO

-- ============================================================================
-- 7. sp_ResolveMaintenanceIssue
-- Closes maintenance fault and reactivates bay if no other active faults remain
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.sp_ResolveMaintenanceIssue
    @p_log_id INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @current_status VARCHAR(20);
        DECLARE @bay_id INT;

        SELECT 
            @current_status = repair_status,
            @bay_id = bay_id
        FROM dbo.MaintenanceLog WITH (UPDLOCK)
        WHERE log_id = @p_log_id;

        IF @current_status IS NULL
        BEGIN
            THROW 57001, 'Maintenance log record not found.', 1;
        END

        IF @current_status = 'RESOLVED'
        BEGIN
            THROW 57002, 'Maintenance issue is already resolved.', 1;
        END

        UPDATE dbo.MaintenanceLog
        SET repair_status = 'RESOLVED',
            resolved_at = SYSDATETIME(),
            updated_at = SYSDATETIME()
        WHERE log_id = @p_log_id;

        -- Note: Trigger trg_MaintenanceLog_BayStatusSync evaluates whether all faults are closed
        -- and reactivates bay (is_operational = 1) if no other faults exist.

        COMMIT TRANSACTION;
        PRINT 'Maintenance Issue #' + CAST(@p_log_id AS VARCHAR(10)) + ' resolved successfully.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
PRINT 'Procedure sp_ResolveMaintenanceIssue created.';
GO

-- ============================================================================
-- 8. sp_GetChargingPriority
-- Returns ranked queue of vehicles needing charging based on mission deadlines
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetChargingPriority
    @p_station_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        fm.mission_id,
        v.vin,
        fo.company_name AS organization,
        v.license_plate,
        v.ownership_type,
        v.current_soc_pct AS current_soc,
        fm.target_soc_pct AS target_soc,
        fm.departure_time,
        v.battery_capacity_kwh AS battery_capacity,
        ROUND((v.battery_capacity_kwh * (CASE WHEN fm.target_soc_pct > v.current_soc_pct THEN (fm.target_soc_pct - v.current_soc_pct) ELSE 0 END)) / 100.0, 2) AS estimated_energy_required_kwh,
        v.max_charge_rate_kw AS max_charge_rate,
        DATEDIFF(MINUTE, SYSDATETIME(), fm.departure_time) AS minutes_until_departure,
        -- Deterministic priority scoring algorithm:
        -- 1. Fleet Mission weight: Commercial fleet missions receive 50 priority points
        -- 2. SOC Deficit weight: 0.5 points per % energy needed
        -- 3. Departure Urgency weight: Imminent or overdue departure receives up to 100 points
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
        ) AS urgency_priority_score
    FROM dbo.FleetMission fm
    INNER JOIN dbo.Vehicle v ON fm.vin = v.vin
    LEFT JOIN dbo.FleetOrg fo ON v.org_id = fo.org_id
    WHERE fm.mission_status = 'SCHEDULED'
    ORDER BY urgency_priority_score DESC, fm.departure_time ASC;
END;
GO
PRINT 'Procedure sp_GetChargingPriority created.';
GO

-- ============================================================================
-- 9. sp_GetAvailableBays
-- Finds charger bays with zero temporal reservations and operational hardware
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.sp_GetAvailableBays
    @p_station_id INT,
    @p_start_time DATETIME2(7),
    @p_end_time   DATETIME2(7),
    @p_plug_type  VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @p_start_time >= @p_end_time
    BEGIN
        THROW 58001, 'start_time must be strictly earlier than end_time.', 1;
    END

    SELECT 
        cb.bay_id,
        cb.station_id,
        cs.station_name,
        cb.bay_number,
        cb.plug_type,
        cb.max_kw_output,
        cb.is_operational,
        cs.city
    FROM dbo.ChargerBay cb
    INNER JOIN dbo.ChargingStation cs ON cb.station_id = cs.station_id
    WHERE cb.station_id = @p_station_id
      AND cb.is_operational = 1
      AND cs.status = 'ACTIVE'
      AND (@p_plug_type IS NULL OR cb.plug_type = @p_plug_type)
      AND NOT EXISTS (
          SELECT 1
          FROM dbo.Reservation r
          WHERE r.bay_id = cb.bay_id
            AND r.reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE')
            AND r.start_time < @p_end_time
            AND r.end_time > @p_start_time
      )
    ORDER BY cb.bay_number ASC;
END;
GO
PRINT 'Procedure sp_GetAvailableBays created.';
GO

PRINT 'All stored procedures created successfully.';
GO
