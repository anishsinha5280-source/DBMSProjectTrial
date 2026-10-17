-- ============================================================================
-- SCRIPT: schema.sql
-- SYSTEM: Intelligent EV Charging Station and Fleet/Depot Management System
-- DIALECT: Microsoft SQL Server (T-SQL)
-- DESCRIPTION: Complete standalone master schema containing database creation,
--              all 13 tables, primary/foreign/unique/check constraints,
--              performance indexes, automated triggers, stored procedures,
--              and analytical views.
-- ============================================================================

USE master;
GO

IF EXISTS (SELECT 1 FROM sys.databases WHERE name = N'EVChargingDB')
BEGIN
    PRINT 'Existing database EVChargingDB found. Resetting...';
    ALTER DATABASE EVChargingDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE EVChargingDB;
END
GO

CREATE DATABASE EVChargingDB
COLLATE Latin1_General_100_CI_AS_SC_UTF8;
GO

ALTER DATABASE EVChargingDB SET RECOVERY FULL;
ALTER DATABASE EVChargingDB SET ALLOW_SNAPSHOT_ISOLATION ON;
ALTER DATABASE EVChargingDB SET READ_COMMITTED_SNAPSHOT ON;
ALTER DATABASE EVChargingDB SET AUTO_UPDATE_STATISTICS ON;
GO

USE EVChargingDB;
GO

-- ============================================================================
-- SECTION 1: CORE TABLES
-- ============================================================================

CREATE TABLE dbo.Substation (
    substation_id           INT IDENTITY(1,1) NOT NULL,
    name                    VARCHAR(100)      NOT NULL,
    max_grid_capacity_kw    DECIMAL(10,2)     NOT NULL,
    region_code             VARCHAR(20)       NOT NULL,
    created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_Substation_CreatedAt DEFAULT SYSDATETIME(),
    updated_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_Substation_UpdatedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_Substation PRIMARY KEY CLUSTERED (substation_id)
);
GO

CREATE TABLE dbo.ChargingStation (
    station_id              INT IDENTITY(1,1) NOT NULL,
    substation_id           INT               NOT NULL,
    station_name            VARCHAR(100)      NOT NULL,
    street_address          VARCHAR(255)      NOT NULL,
    city                    VARCHAR(100)      NOT NULL,
    status                  VARCHAR(20)       NOT NULL CONSTRAINT DF_ChargingStation_Status DEFAULT 'ACTIVE',
    created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_ChargingStation_CreatedAt DEFAULT SYSDATETIME(),
    updated_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_ChargingStation_UpdatedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_ChargingStation PRIMARY KEY CLUSTERED (station_id)
);
GO

CREATE TABLE dbo.ChargerBay (
    bay_id                  INT IDENTITY(1,1) NOT NULL,
    station_id              INT               NOT NULL,
    bay_number              INT               NOT NULL,
    plug_type               VARCHAR(20)       NOT NULL,
    max_kw_output           DECIMAL(8,2)      NOT NULL,
    is_operational          BIT               NOT NULL CONSTRAINT DF_ChargerBay_IsOperational DEFAULT 1,
    created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_ChargerBay_CreatedAt DEFAULT SYSDATETIME(),
    updated_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_ChargerBay_UpdatedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_ChargerBay PRIMARY KEY CLUSTERED (bay_id)
);
GO

CREATE TABLE dbo.TariffPlan (
    tariff_id               INT IDENTITY(1,1) NOT NULL,
    station_id              INT               NOT NULL,
    plan_name               VARCHAR(50)       NOT NULL,
    start_hour              INT               NOT NULL,
    end_hour                INT               NOT NULL,
    base_rate_per_kwh       DECIMAL(10,4)     NOT NULL,
    idle_fee_per_min        DECIMAL(10,4)     NOT NULL CONSTRAINT DF_TariffPlan_IdleFee DEFAULT 0.0000,
    created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_TariffPlan_CreatedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_TariffPlan PRIMARY KEY CLUSTERED (tariff_id)
);
GO

CREATE TABLE dbo.FleetOrg (
    org_id                  INT IDENTITY(1,1) NOT NULL,
    company_name            VARCHAR(150)      NOT NULL,
    tax_id                  VARCHAR(50)       NOT NULL,
    credit_line_limit       DECIMAL(12,2)     NOT NULL CONSTRAINT DF_FleetOrg_CreditLimit DEFAULT 0.00,
    current_balance         DECIMAL(12,2)     NOT NULL CONSTRAINT DF_FleetOrg_CurrentBalance DEFAULT 0.00,
    created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_FleetOrg_CreatedAt DEFAULT SYSDATETIME(),
    updated_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_FleetOrg_UpdatedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_FleetOrg PRIMARY KEY CLUSTERED (org_id)
);
GO

CREATE TABLE dbo.AppUser (
    user_id                 INT IDENTITY(1,1) NOT NULL,
    org_id                  INT               NULL,
    full_name               VARCHAR(100)      NOT NULL,
    email                   VARCHAR(150)      NOT NULL,
    phone                   VARCHAR(25)       NOT NULL,
    user_role               VARCHAR(20)       NOT NULL,
    created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_AppUser_CreatedAt DEFAULT SYSDATETIME(),
    updated_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_AppUser_UpdatedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_AppUser PRIMARY KEY CLUSTERED (user_id)
);
GO

CREATE TABLE dbo.Vehicle (
    vin                     VARCHAR(17)       NOT NULL,
    org_id                  INT               NOT NULL,
    user_id                 INT               NOT NULL,
    license_plate           VARCHAR(20)       NOT NULL,
    battery_capacity_kwh    DECIMAL(8,2)      NOT NULL,
    max_charge_rate_kw      DECIMAL(8,2)      NOT NULL,
    current_soc_pct         DECIMAL(5,2)      NOT NULL CONSTRAINT DF_Vehicle_CurrentSoc DEFAULT 50.00,
    ownership_type          VARCHAR(20)       NOT NULL CONSTRAINT DF_Vehicle_OwnershipType DEFAULT 'FLEET',
    created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_Vehicle_CreatedAt DEFAULT SYSDATETIME(),
    updated_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_Vehicle_UpdatedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_Vehicle PRIMARY KEY CLUSTERED (vin)
);
GO

CREATE TABLE dbo.FleetMission (
    mission_id              INT IDENTITY(1,1) NOT NULL,
    vin                     VARCHAR(17)       NOT NULL,
    driver_id               INT               NOT NULL,
    departure_time          DATETIME2(7)      NOT NULL,
    target_soc_pct          DECIMAL(5,2)      NOT NULL,
    route_distance_km       DECIMAL(8,2)      NOT NULL CONSTRAINT DF_FleetMission_RouteDistance DEFAULT 0.00,
    mission_status          VARCHAR(20)       NOT NULL CONSTRAINT DF_FleetMission_Status DEFAULT 'SCHEDULED',
    created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_FleetMission_CreatedAt DEFAULT SYSDATETIME(),
    updated_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_FleetMission_UpdatedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_FleetMission PRIMARY KEY CLUSTERED (mission_id)
);
GO

CREATE TABLE dbo.Reservation (
    reservation_id          INT IDENTITY(1,1) NOT NULL,
    bay_id                  INT               NOT NULL,
    vin                     VARCHAR(17)       NOT NULL,
    user_id                 INT               NOT NULL,
    start_time              DATETIME2(7)      NOT NULL,
    end_time                DATETIME2(7)      NOT NULL,
    reservation_status      VARCHAR(20)       NOT NULL CONSTRAINT DF_Reservation_Status DEFAULT 'PENDING',
    created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_Reservation_CreatedAt DEFAULT SYSDATETIME(),
    updated_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_Reservation_UpdatedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_Reservation PRIMARY KEY CLUSTERED (reservation_id)
);
GO

CREATE TABLE dbo.ChargingSession (
    session_id              INT IDENTITY(1,1) NOT NULL,
    bay_id                  INT               NOT NULL,
    vin                     VARCHAR(17)       NOT NULL,
    user_id                 INT               NOT NULL,
    reservation_id          INT               NOT NULL,
    start_time              DATETIME2(7)      NOT NULL CONSTRAINT DF_ChargingSession_StartTime DEFAULT SYSDATETIME(),
    end_time                DATETIME2(7)      NULL,
    allocated_kw            DECIMAL(8,2)      NOT NULL,
    energy_delivered_kwh    DECIMAL(10,3)     NOT NULL CONSTRAINT DF_ChargingSession_Energy DEFAULT 0.000,
    idle_minutes            INT               NOT NULL CONSTRAINT DF_ChargingSession_IdleMin DEFAULT 0,
    status                  VARCHAR(20)       NOT NULL CONSTRAINT DF_ChargingSession_Status DEFAULT 'STARTED',
    created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_ChargingSession_CreatedAt DEFAULT SYSDATETIME(),
    updated_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_ChargingSession_UpdatedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_ChargingSession PRIMARY KEY CLUSTERED (session_id)
);
GO

CREATE TABLE dbo.MaintenanceLog (
    log_id                  INT IDENTITY(1,1) NOT NULL,
    bay_id                  INT               NOT NULL,
    technician_id           INT               NOT NULL,
    issue_reported          VARCHAR(500)      NOT NULL,
    reported_at             DATETIME2(7)      NOT NULL CONSTRAINT DF_MaintenanceLog_ReportedAt DEFAULT SYSDATETIME(),
    resolved_at             DATETIME2(7)      NULL,
    repair_status           VARCHAR(20)       NOT NULL CONSTRAINT DF_MaintenanceLog_RepairStatus DEFAULT 'OPEN',
    created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_MaintenanceLog_CreatedAt DEFAULT SYSDATETIME(),
    updated_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_MaintenanceLog_UpdatedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_MaintenanceLog PRIMARY KEY CLUSTERED (log_id)
);
GO

CREATE TABLE dbo.Invoice (
    invoice_id              INT IDENTITY(1,1) NOT NULL,
    session_id              INT               NOT NULL,
    energy_charge           DECIMAL(10,2)     NOT NULL CONSTRAINT DF_Invoice_EnergyCharge DEFAULT 0.00,
    idle_penalty_charge     DECIMAL(10,2)     NOT NULL CONSTRAINT DF_Invoice_IdlePenalty DEFAULT 0.00,
    tax_amount              DECIMAL(10,2)     NOT NULL CONSTRAINT DF_Invoice_TaxAmount DEFAULT 0.00,
    total_amount            AS (energy_charge + idle_penalty_charge + tax_amount) PERSISTED,
    status                  VARCHAR(20)       NOT NULL CONSTRAINT DF_Invoice_Status DEFAULT 'PENDING',
    created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_Invoice_CreatedAt DEFAULT SYSDATETIME(),
    updated_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_Invoice_UpdatedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_Invoice PRIMARY KEY CLUSTERED (invoice_id)
);
GO

CREATE TABLE dbo.Payment (
    payment_id              INT IDENTITY(1,1) NOT NULL,
    invoice_id              INT               NOT NULL,
    payment_method          VARCHAR(20)       NOT NULL,
    paid_amount             DECIMAL(10,2)     NOT NULL,
    transaction_ref         VARCHAR(100)      NOT NULL,
    settled_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_Payment_SettledAt DEFAULT SYSDATETIME(),
    created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_Payment_CreatedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_Payment PRIMARY KEY CLUSTERED (payment_id)
);
GO

-- ============================================================================
-- SECTION 2: CONSTRAINTS (FOREIGN KEYS, UNIQUE, CHECK)
-- ============================================================================

-- Foreign Keys
ALTER TABLE dbo.ChargingStation ADD CONSTRAINT FK_ChargingStation_Substation
    FOREIGN KEY (substation_id) REFERENCES dbo.Substation (substation_id) ON DELETE NO ACTION ON UPDATE CASCADE;

ALTER TABLE dbo.ChargerBay ADD CONSTRAINT FK_ChargerBay_ChargingStation
    FOREIGN KEY (station_id) REFERENCES dbo.ChargingStation (station_id) ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE dbo.TariffPlan ADD CONSTRAINT FK_TariffPlan_ChargingStation
    FOREIGN KEY (station_id) REFERENCES dbo.ChargingStation (station_id) ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE dbo.AppUser ADD CONSTRAINT FK_AppUser_FleetOrg
    FOREIGN KEY (org_id) REFERENCES dbo.FleetOrg (org_id) ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE dbo.Vehicle ADD CONSTRAINT FK_Vehicle_FleetOrg
    FOREIGN KEY (org_id) REFERENCES dbo.FleetOrg (org_id) ON DELETE NO ACTION ON UPDATE CASCADE;

ALTER TABLE dbo.Vehicle ADD CONSTRAINT FK_Vehicle_AppUser
    FOREIGN KEY (user_id) REFERENCES dbo.AppUser (user_id) ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE dbo.FleetMission ADD CONSTRAINT FK_FleetMission_Vehicle
    FOREIGN KEY (vin) REFERENCES dbo.Vehicle (vin) ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE dbo.FleetMission ADD CONSTRAINT FK_FleetMission_AppUser
    FOREIGN KEY (driver_id) REFERENCES dbo.AppUser (user_id) ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE dbo.Reservation ADD CONSTRAINT FK_Reservation_ChargerBay
    FOREIGN KEY (bay_id) REFERENCES dbo.ChargerBay (bay_id) ON DELETE NO ACTION ON UPDATE CASCADE;

ALTER TABLE dbo.Reservation ADD CONSTRAINT FK_Reservation_Vehicle
    FOREIGN KEY (vin) REFERENCES dbo.Vehicle (vin) ON DELETE NO ACTION ON UPDATE CASCADE;

ALTER TABLE dbo.Reservation ADD CONSTRAINT FK_Reservation_AppUser
    FOREIGN KEY (user_id) REFERENCES dbo.AppUser (user_id) ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE dbo.ChargingSession ADD CONSTRAINT FK_ChargingSession_ChargerBay
    FOREIGN KEY (bay_id) REFERENCES dbo.ChargerBay (bay_id) ON DELETE NO ACTION ON UPDATE CASCADE;

ALTER TABLE dbo.ChargingSession ADD CONSTRAINT FK_ChargingSession_Vehicle
    FOREIGN KEY (vin) REFERENCES dbo.Vehicle (vin) ON DELETE NO ACTION ON UPDATE CASCADE;

ALTER TABLE dbo.ChargingSession ADD CONSTRAINT FK_ChargingSession_AppUser
    FOREIGN KEY (user_id) REFERENCES dbo.AppUser (user_id) ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE dbo.ChargingSession ADD CONSTRAINT FK_ChargingSession_Reservation
    FOREIGN KEY (reservation_id) REFERENCES dbo.Reservation (reservation_id) ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE dbo.MaintenanceLog ADD CONSTRAINT FK_MaintenanceLog_ChargerBay
    FOREIGN KEY (bay_id) REFERENCES dbo.ChargerBay (bay_id) ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE dbo.MaintenanceLog ADD CONSTRAINT FK_MaintenanceLog_AppUser
    FOREIGN KEY (technician_id) REFERENCES dbo.AppUser (user_id) ON DELETE NO ACTION ON UPDATE NO ACTION;

ALTER TABLE dbo.Invoice ADD CONSTRAINT FK_Invoice_ChargingSession
    FOREIGN KEY (session_id) REFERENCES dbo.ChargingSession (session_id) ON DELETE NO ACTION ON UPDATE CASCADE;

ALTER TABLE dbo.Payment ADD CONSTRAINT FK_Payment_Invoice
    FOREIGN KEY (invoice_id) REFERENCES dbo.Invoice (invoice_id) ON DELETE CASCADE ON UPDATE CASCADE;

-- Unique Constraints
ALTER TABLE dbo.ChargerBay ADD CONSTRAINT UQ_ChargerBay_Station_Bay UNIQUE (station_id, bay_number);
ALTER TABLE dbo.FleetOrg ADD CONSTRAINT UQ_FleetOrg_TaxId UNIQUE (tax_id);
ALTER TABLE dbo.AppUser ADD CONSTRAINT UQ_AppUser_Email UNIQUE (email);
ALTER TABLE dbo.Vehicle ADD CONSTRAINT UQ_Vehicle_LicensePlate UNIQUE (license_plate);
ALTER TABLE dbo.Invoice ADD CONSTRAINT UQ_Invoice_SessionId UNIQUE (session_id);
ALTER TABLE dbo.Payment ADD CONSTRAINT UQ_Payment_TransactionRef UNIQUE (transaction_ref);

-- Check Constraints
ALTER TABLE dbo.Substation ADD CONSTRAINT CK_Substation_MaxCapacity CHECK (max_grid_capacity_kw > 0.00);
ALTER TABLE dbo.ChargingStation ADD CONSTRAINT CK_ChargingStation_Status CHECK (status IN ('ACTIVE', 'INACTIVE', 'MAINTENANCE', 'OFFLINE'));
ALTER TABLE dbo.ChargerBay ADD CONSTRAINT CK_ChargerBay_PlugType CHECK (plug_type IN ('CCS2', 'TYPE2', 'NACS'));
ALTER TABLE dbo.ChargerBay ADD CONSTRAINT CK_ChargerBay_MaxKw CHECK (max_kw_output > 0.00);
ALTER TABLE dbo.TariffPlan ADD CONSTRAINT CK_TariffPlan_StartHour CHECK (start_hour BETWEEN 0 AND 23);
ALTER TABLE dbo.TariffPlan ADD CONSTRAINT CK_TariffPlan_EndHour CHECK (end_hour BETWEEN 0 AND 23);
ALTER TABLE dbo.TariffPlan ADD CONSTRAINT CK_TariffPlan_BaseRate CHECK (base_rate_per_kwh >= 0.0000);
ALTER TABLE dbo.TariffPlan ADD CONSTRAINT CK_TariffPlan_IdleFee CHECK (idle_fee_per_min >= 0.0000);
ALTER TABLE dbo.FleetOrg ADD CONSTRAINT CK_FleetOrg_CreditLimit CHECK (credit_line_limit >= 0.00);
ALTER TABLE dbo.FleetOrg ADD CONSTRAINT CK_FleetOrg_CurrentBalance CHECK (current_balance >= 0.00);
ALTER TABLE dbo.AppUser ADD CONSTRAINT CK_AppUser_UserRole CHECK (user_role IN ('DRIVER', 'DEPOT_MANAGER', 'TECHNICIAN', 'ADMIN'));
ALTER TABLE dbo.Vehicle ADD CONSTRAINT CK_Vehicle_BatteryCapacity CHECK (battery_capacity_kwh > 0.00);
ALTER TABLE dbo.Vehicle ADD CONSTRAINT CK_Vehicle_MaxChargeRate CHECK (max_charge_rate_kw > 0.00);
ALTER TABLE dbo.Vehicle ADD CONSTRAINT CK_Vehicle_CurrentSoc CHECK (current_soc_pct >= 0.00 AND current_soc_pct <= 100.00);
ALTER TABLE dbo.Vehicle ADD CONSTRAINT CK_Vehicle_OwnershipType CHECK (ownership_type IN ('FLEET', 'PRIVATE', 'LEASED'));
ALTER TABLE dbo.FleetMission ADD CONSTRAINT CK_FleetMission_TargetSoc CHECK (target_soc_pct >= 0.00 AND target_soc_pct <= 100.00);
ALTER TABLE dbo.FleetMission ADD CONSTRAINT CK_FleetMission_RouteDistance CHECK (route_distance_km >= 0.00);
ALTER TABLE dbo.FleetMission ADD CONSTRAINT CK_FleetMission_Status CHECK (mission_status IN ('SCHEDULED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'));
ALTER TABLE dbo.Reservation ADD CONSTRAINT CK_Reservation_TimeInterval CHECK (start_time < end_time);
ALTER TABLE dbo.Reservation ADD CONSTRAINT CK_Reservation_Status CHECK (reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE', 'COMPLETED', 'CANCELLED', 'NO_SHOW'));
ALTER TABLE dbo.ChargingSession ADD CONSTRAINT CK_ChargingSession_TimeInterval CHECK (end_time IS NULL OR start_time <= end_time);
ALTER TABLE dbo.ChargingSession ADD CONSTRAINT CK_ChargingSession_AllocatedKw CHECK (allocated_kw > 0.00);
ALTER TABLE dbo.ChargingSession ADD CONSTRAINT CK_ChargingSession_EnergyDelivered CHECK (energy_delivered_kwh >= 0.000);
ALTER TABLE dbo.ChargingSession ADD CONSTRAINT CK_ChargingSession_IdleMinutes CHECK (idle_minutes >= 0);
ALTER TABLE dbo.ChargingSession ADD CONSTRAINT CK_ChargingSession_Status CHECK (status IN ('STARTED', 'CHARGING', 'COMPLETED', 'CANCELLED', 'FAULT'));
ALTER TABLE dbo.MaintenanceLog ADD CONSTRAINT CK_MaintenanceLog_TimeInterval CHECK (resolved_at IS NULL OR reported_at <= resolved_at);
ALTER TABLE dbo.MaintenanceLog ADD CONSTRAINT CK_MaintenanceLog_RepairStatus CHECK (repair_status IN ('OPEN', 'IN_PROGRESS', 'RESOLVED', 'CANCELLED'));
ALTER TABLE dbo.Invoice ADD CONSTRAINT CK_Invoice_EnergyCharge CHECK (energy_charge >= 0.00);
ALTER TABLE dbo.Invoice ADD CONSTRAINT CK_Invoice_IdlePenalty CHECK (idle_penalty_charge >= 0.00);
ALTER TABLE dbo.Invoice ADD CONSTRAINT CK_Invoice_TaxAmount CHECK (tax_amount >= 0.00);
ALTER TABLE dbo.Invoice ADD CONSTRAINT CK_Invoice_Status CHECK (status IN ('PENDING', 'PAID', 'PARTIALLY_PAID', 'CANCELLED', 'OVERDUE'));
ALTER TABLE dbo.Payment ADD CONSTRAINT CK_Payment_PaidAmount CHECK (paid_amount > 0.00);
ALTER TABLE dbo.Payment ADD CONSTRAINT CK_Payment_PaymentMethod CHECK (payment_method IN ('UPI', 'CARD', 'NET_BANKING', 'WALLET', 'CREDIT_LINE'));
GO

-- ============================================================================
-- SECTION 3: PERFORMANCE INDEXES
-- ============================================================================

CREATE NONCLUSTERED INDEX IX_ChargingStation_SubstationId ON dbo.ChargingStation (substation_id) INCLUDE (station_name, status);
CREATE NONCLUSTERED INDEX IX_ChargerBay_StationId ON dbo.ChargerBay (station_id) INCLUDE (bay_number, plug_type, max_kw_output, is_operational);
CREATE NONCLUSTERED INDEX IX_TariffPlan_StationId_Hours ON dbo.TariffPlan (station_id, start_hour, end_hour) INCLUDE (base_rate_per_kwh, idle_fee_per_min);
CREATE NONCLUSTERED INDEX IX_AppUser_OrgId ON dbo.AppUser (org_id) INCLUDE (full_name, email, user_role);
CREATE NONCLUSTERED INDEX IX_Vehicle_OrgId ON dbo.Vehicle (org_id) INCLUDE (license_plate, battery_capacity_kwh, current_soc_pct, ownership_type);
CREATE NONCLUSTERED INDEX IX_Vehicle_UserId ON dbo.Vehicle (user_id) INCLUDE (vin, license_plate);
CREATE NONCLUSTERED INDEX IX_FleetMission_Vin ON dbo.FleetMission (vin) INCLUDE (departure_time, target_soc_pct, mission_status);
CREATE NONCLUSTERED INDEX IX_FleetMission_DriverId ON dbo.FleetMission (driver_id) INCLUDE (departure_time, mission_status);
CREATE NONCLUSTERED INDEX IX_FleetMission_DepartureTime ON dbo.FleetMission (departure_time, mission_status) INCLUDE (vin, driver_id, target_soc_pct, route_distance_km);

CREATE NONCLUSTERED INDEX IX_Reservation_UserId ON dbo.Reservation (user_id) INCLUDE (bay_id, vin, start_time, end_time, reservation_status);
CREATE NONCLUSTERED INDEX IX_Reservation_Bay_TimeRange ON dbo.Reservation (bay_id, start_time, end_time) INCLUDE (reservation_status, vin, user_id);
CREATE NONCLUSTERED INDEX IX_Reservation_Vehicle_TimeRange ON dbo.Reservation (vin, start_time, end_time) INCLUDE (reservation_status, bay_id, user_id);
CREATE NONCLUSTERED INDEX IX_Reservation_ActiveOnly ON dbo.Reservation (bay_id, start_time, end_time) INCLUDE (vin, reservation_status) WHERE reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE');

CREATE NONCLUSTERED INDEX IX_ChargingSession_BayId ON dbo.ChargingSession (bay_id) INCLUDE (vin, status, allocated_kw, start_time, end_time);
CREATE NONCLUSTERED INDEX IX_ChargingSession_Vin ON dbo.ChargingSession (vin) INCLUDE (status, energy_delivered_kwh, start_time, end_time);
CREATE NONCLUSTERED INDEX IX_ChargingSession_UserId ON dbo.ChargingSession (user_id) INCLUDE (session_id, status);
CREATE NONCLUSTERED INDEX IX_ChargingSession_ReservationId ON dbo.ChargingSession (reservation_id) INCLUDE (status, allocated_kw);
CREATE NONCLUSTERED INDEX IX_ChargingSession_ActiveGridLoad ON dbo.ChargingSession (bay_id, allocated_kw) INCLUDE (vin, status) WHERE status IN ('STARTED', 'CHARGING');

CREATE NONCLUSTERED INDEX IX_MaintenanceLog_BayId ON dbo.MaintenanceLog (bay_id, repair_status) INCLUDE (reported_at, resolved_at);
CREATE NONCLUSTERED INDEX IX_MaintenanceLog_TechnicianId ON dbo.MaintenanceLog (technician_id) INCLUDE (repair_status, reported_at);
CREATE NONCLUSTERED INDEX IX_MaintenanceLog_UnresolvedFaults ON dbo.MaintenanceLog (bay_id, repair_status) WHERE repair_status IN ('OPEN', 'IN_PROGRESS');

CREATE NONCLUSTERED INDEX IX_Payment_InvoiceId ON dbo.Payment (invoice_id) INCLUDE (paid_amount, payment_method, settled_at);
GO

-- ============================================================================
-- SECTION 4: AUTOMATED TRIGGERS
-- ============================================================================

CREATE OR ALTER TRIGGER dbo.trg_Reservation_ValidateAndPreventOverlap
ON dbo.Reservation
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    IF EXISTS (
        SELECT 1 FROM inserted i
        INNER JOIN dbo.ChargerBay b ON i.bay_id = b.bay_id
        WHERE b.is_operational = 0 AND i.reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE')
    )
    BEGIN
        THROW 50001, 'Reservation rejected: The requested charger bay is currently non-operational or under maintenance.', 1;
    END

    IF EXISTS (
        SELECT 1 FROM inserted i
        INNER JOIN dbo.Reservation r ON i.bay_id = r.bay_id AND i.reservation_id <> r.reservation_id
        WHERE i.reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE')
          AND r.reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE')
          AND r.start_time < i.end_time AND r.end_time > i.start_time
    )
    BEGIN
        THROW 50002, 'Double booking rejected: The requested charger bay is already reserved during the specified time interval.', 1;
    END

    IF EXISTS (
        SELECT 1 FROM inserted i
        INNER JOIN dbo.Reservation r ON i.vin = r.vin AND i.reservation_id <> r.reservation_id
        WHERE i.reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE')
          AND r.reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE')
          AND r.start_time < i.end_time AND r.end_time > i.start_time
    )
    BEGIN
        THROW 50003, 'Vehicle conflict rejected: The specified vehicle already has an active reservation during this time window.', 1;
    END
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_MaintenanceLog_BayStatusSync
ON dbo.MaintenanceLog
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AffectedBays TABLE (bay_id INT PRIMARY KEY);
    INSERT INTO @AffectedBays (bay_id)
    SELECT DISTINCT bay_id FROM inserted UNION SELECT DISTINCT bay_id FROM deleted;

    UPDATE b
    SET b.is_operational = CASE
            WHEN EXISTS (
                SELECT 1 FROM dbo.MaintenanceLog m
                WHERE m.bay_id = b.bay_id AND m.repair_status IN ('OPEN', 'IN_PROGRESS')
            ) THEN 0 ELSE 1
        END,
        b.updated_at = SYSDATETIME()
    FROM dbo.ChargerBay b
    INNER JOIN @AffectedBays ab ON b.bay_id = ab.bay_id;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_ChargingSession_EnforceGridCapacity
ON dbo.ChargingSession
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    IF EXISTS (
        SELECT 1 FROM inserted i
        INNER JOIN dbo.ChargerBay cb ON i.bay_id = cb.bay_id
        WHERE i.allocated_kw > cb.max_kw_output AND i.status IN ('STARTED', 'CHARGING')
    )
    BEGIN
        THROW 50010, 'Safety limit exceeded: Requested allocated power exceeds maximum charger bay hardware output.', 1;
    END

    IF EXISTS (
        SELECT 1 FROM inserted i
        INNER JOIN dbo.Vehicle v ON i.vin = v.vin
        WHERE i.allocated_kw > v.max_charge_rate_kw AND i.status IN ('STARTED', 'CHARGING')
    )
    BEGIN
        THROW 50011, 'Safety limit exceeded: Requested allocated power exceeds vehicle onboard charging rate acceptance limit.', 1;
    END

    IF EXISTS (
        SELECT sub.substation_id FROM dbo.Substation sub
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

CREATE OR ALTER TRIGGER dbo.trg_Payment_SyncInvoiceStatus
ON dbo.Payment
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AffectedInvoices TABLE (invoice_id INT PRIMARY KEY);
    INSERT INTO @AffectedInvoices (invoice_id)
    SELECT DISTINCT invoice_id FROM inserted UNION SELECT DISTINCT invoice_id FROM deleted;

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
        SELECT SUM(p.paid_amount) AS TotalPaid FROM dbo.Payment p WHERE p.invoice_id = inv.invoice_id
    ) pay;
END;
GO

-- ============================================================================
-- SECTION 5: STORED PROCEDURES
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
        IF @p_start_time >= @p_end_time THROW 51001, 'start_time must be strictly before end_time.', 1;
        IF @p_start_time < DATEADD(MINUTE, -15, SYSDATETIME()) THROW 51002, 'Cannot create reservations in the past.', 1;

        BEGIN TRANSACTION;

        DECLARE @is_operational BIT, @station_status VARCHAR(20);
        SELECT @is_operational = cb.is_operational, @station_status = cs.status
        FROM dbo.ChargerBay cb WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.ChargingStation cs ON cb.station_id = cs.station_id
        WHERE cb.bay_id = @p_bay_id;

        IF @is_operational IS NULL THROW 51003, 'Specified charger bay does not exist.', 1;
        IF @station_status <> 'ACTIVE' THROW 51004, 'Charging station is not ACTIVE.', 1;
        IF @is_operational = 0 THROW 51005, 'Charger bay is out of service.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.Vehicle WHERE vin = @p_vin) THROW 51006, 'Vehicle VIN does not exist.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.AppUser WHERE user_id = @p_user_id) THROW 51007, 'User does not exist.', 1;

        IF EXISTS (
            SELECT 1 FROM dbo.Reservation WITH (UPDLOCK, HOLDLOCK)
            WHERE bay_id = @p_bay_id AND reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE')
              AND start_time < @p_end_time AND end_time > @p_start_time
        )
            THROW 51008, 'Reservation conflict: Charger bay already reserved for overlapping interval.', 1;

        IF EXISTS (
            SELECT 1 FROM dbo.Reservation WITH (UPDLOCK, HOLDLOCK)
            WHERE vin = @p_vin AND reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE')
              AND start_time < @p_end_time AND end_time > @p_start_time
        )
            THROW 51009, 'Reservation conflict: Vehicle already scheduled elsewhere during this interval.', 1;

        INSERT INTO dbo.Reservation (bay_id, vin, user_id, start_time, end_time, reservation_status)
        VALUES (@p_bay_id, @p_vin, @p_user_id, @p_start_time, @p_end_time, 'CONFIRMED');

        SET @p_reservation_id = SCOPE_IDENTITY();
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

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
        SELECT @current_status = reservation_status FROM dbo.Reservation WITH (UPDLOCK) WHERE reservation_id = @p_reservation_id;

        IF @current_status IS NULL THROW 52001, 'Reservation not found.', 1;
        IF @current_status IN ('COMPLETED', 'CANCELLED', 'ACTIVE') THROW 52002, 'Cannot cancel reservation in current status.', 1;

        UPDATE dbo.Reservation SET reservation_status = 'CANCELLED', updated_at = SYSDATETIME() WHERE reservation_id = @p_reservation_id;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

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

        DECLARE @bay_id INT, @vin VARCHAR(17), @user_id INT, @res_status VARCHAR(20);
        SELECT @bay_id = bay_id, @vin = vin, @user_id = user_id, @res_status = reservation_status
        FROM dbo.Reservation WITH (UPDLOCK) WHERE reservation_id = @p_reservation_id;

        IF @bay_id IS NULL THROW 53001, 'Reservation not found.', 1;
        IF @res_status NOT IN ('PENDING', 'CONFIRMED') THROW 53002, 'Session only allowed for PENDING or CONFIRMED reservations.', 1;

        DECLARE @bay_max_kw DECIMAL(8,2), @is_operational BIT, @station_id INT;
        SELECT @bay_max_kw = max_kw_output, @is_operational = is_operational, @station_id = station_id
        FROM dbo.ChargerBay WITH (UPDLOCK) WHERE bay_id = @bay_id;

        IF @is_operational = 0 THROW 53003, 'Charger bay is non-operational.', 1;
        IF @p_requested_kw > @bay_max_kw THROW 53004, 'Requested power exceeds bay max output.', 1;

        DECLARE @vehicle_max_rate DECIMAL(8,2);
        SELECT @vehicle_max_rate = max_charge_rate_kw FROM dbo.Vehicle WHERE vin = @vin;
        IF @p_requested_kw > @vehicle_max_rate THROW 53005, 'Requested power exceeds vehicle max charging rate.', 1;

        DECLARE @substation_id INT, @max_grid_capacity DECIMAL(10,2);
        SELECT @substation_id = sub.substation_id, @max_grid_capacity = sub.max_grid_capacity_kw
        FROM dbo.ChargingStation cs
        INNER JOIN dbo.Substation sub WITH (UPDLOCK, HOLDLOCK) ON cs.substation_id = sub.substation_id
        WHERE cs.station_id = @station_id;

        DECLARE @current_substation_load DECIMAL(10,2);
        SELECT @current_substation_load = ISNULL(SUM(csess.allocated_kw), 0.00)
        FROM dbo.ChargingSession csess
        INNER JOIN dbo.ChargerBay cb ON csess.bay_id = cb.bay_id
        INNER JOIN dbo.ChargingStation cs ON cb.station_id = cs.station_id
        WHERE cs.substation_id = @substation_id AND csess.status IN ('STARTED', 'CHARGING');

        DECLARE @available_headroom DECIMAL(10,2) = @max_grid_capacity - @current_substation_load;
        IF @p_requested_kw > @available_headroom
        BEGIN
            DECLARE @errMsg VARCHAR(300) = 'Grid capacity constrained: Substation #' + CAST(@substation_id AS VARCHAR(10)) 
                        + ' has only ' + CAST(@available_headroom AS VARCHAR(15)) + ' kW headroom. Requested: ' 
                        + CAST(@p_requested_kw AS VARCHAR(15)) + ' kW. Session rejected.';
            THROW 53006, @errMsg, 1;
        END

        INSERT INTO dbo.ChargingSession (bay_id, vin, user_id, reservation_id, start_time, allocated_kw, energy_delivered_kwh, idle_minutes, status)
        VALUES (@bay_id, @vin, @user_id, @p_reservation_id, SYSDATETIME(), @p_requested_kw, 0.000, 0, 'CHARGING');

        SET @p_session_id = SCOPE_IDENTITY();

        UPDATE dbo.Reservation SET reservation_status = 'ACTIVE', updated_at = SYSDATETIME() WHERE reservation_id = @p_reservation_id;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

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

        DECLARE @bay_id INT, @vin VARCHAR(17), @reservation_id INT, @session_status VARCHAR(20), @session_start DATETIME2(7), @station_id INT, @battery_capacity DECIMAL(8,2), @current_soc DECIMAL(5,2);
        SELECT @bay_id = cs.bay_id, @vin = cs.vin, @reservation_id = cs.reservation_id, @session_status = cs.status, @session_start = cs.start_time, @station_id = cb.station_id, @battery_capacity = v.battery_capacity_kwh, @current_soc = v.current_soc_pct
        FROM dbo.ChargingSession cs WITH (UPDLOCK)
        INNER JOIN dbo.ChargerBay cb ON cs.bay_id = cb.bay_id
        INNER JOIN dbo.Vehicle v ON cs.vin = v.vin
        WHERE cs.session_id = @p_session_id;

        IF @session_status IS NULL THROW 54001, 'Charging session not found.', 1;
        IF @session_status NOT IN ('STARTED', 'CHARGING') THROW 54002, 'Charging session is not active.', 1;
        IF @p_energy_delivered_kwh < 0.000 OR @p_idle_minutes < 0 THROW 54003, 'Energy and idle minutes must be non-negative.', 1;

        DECLARE @session_hour INT = DATEPART(HOUR, @session_start);
        DECLARE @base_rate DECIMAL(10,4) = 0.2500;
        DECLARE @idle_rate DECIMAL(10,4) = 0.5000;

        SELECT TOP 1 @base_rate = base_rate_per_kwh, @idle_rate = idle_fee_per_min
        FROM dbo.TariffPlan
        WHERE station_id = @station_id
          AND ((start_hour <= end_hour AND @session_hour >= start_hour AND @session_hour < end_hour)
            OR (start_hour > end_hour  AND (@session_hour >= start_hour OR @session_hour < end_hour)))
        ORDER BY tariff_id DESC;

        DECLARE @energy_charge DECIMAL(10,2) = ROUND(@p_energy_delivered_kwh * @base_rate, 2);
        DECLARE @idle_penalty_charge DECIMAL(10,2) = ROUND(@p_idle_minutes * @idle_rate, 2);
        DECLARE @tax_amount DECIMAL(10,2) = ROUND((@energy_charge + @idle_penalty_charge) * 0.18, 2);

        INSERT INTO dbo.Invoice (session_id, energy_charge, idle_penalty_charge, tax_amount, status)
        VALUES (@p_session_id, @energy_charge, @idle_penalty_charge, @tax_amount, 'PENDING');
        SET @p_invoice_id = SCOPE_IDENTITY();

        UPDATE dbo.ChargingSession
        SET end_time = SYSDATETIME(), energy_delivered_kwh = @p_energy_delivered_kwh, idle_minutes = @p_idle_minutes, status = 'COMPLETED', updated_at = SYSDATETIME()
        WHERE session_id = @p_session_id;

        UPDATE dbo.Reservation SET reservation_status = 'COMPLETED', updated_at = SYSDATETIME() WHERE reservation_id = @p_reservation_id;

        IF @battery_capacity > 0
        BEGIN
            DECLARE @new_soc DECIMAL(5,2) = @current_soc + ((@p_energy_delivered_kwh / @battery_capacity) * 100.00);
            IF @new_soc > 100.00 SET @new_soc = 100.00;
            UPDATE dbo.Vehicle SET current_soc_pct = @new_soc, updated_at = SYSDATETIME() WHERE vin = @vin;
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

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

        DECLARE @invoice_status VARCHAR(20), @total_amount DECIMAL(10,2), @session_id INT;
        SELECT @invoice_status = status, @total_amount = total_amount, @session_id = session_id
        FROM dbo.Invoice WITH (UPDLOCK) WHERE invoice_id = @p_invoice_id;

        IF @invoice_status IS NULL THROW 55001, 'Invoice not found.', 1;
        IF @invoice_status = 'PAID' THROW 55002, 'Invoice already paid in full.', 1;
        IF @invoice_status = 'CANCELLED' THROW 55003, 'Cannot pay cancelled invoice.', 1;
        IF @p_paid_amount <= 0.00 THROW 55004, 'Paid amount must be > 0.', 1;

        IF @p_payment_method = 'CREDIT_LINE'
        BEGIN
            DECLARE @org_id INT, @credit_limit DECIMAL(12,2), @current_balance DECIMAL(12,2);
            SELECT @org_id = fo.org_id, @credit_limit = fo.credit_line_limit, @current_balance = fo.current_balance
            FROM dbo.Invoice inv
            INNER JOIN dbo.ChargingSession cs ON inv.session_id = cs.session_id
            INNER JOIN dbo.Vehicle v ON cs.vin = v.vin
            INNER JOIN dbo.FleetOrg fo WITH (UPDLOCK) ON v.org_id = fo.org_id
            WHERE inv.invoice_id = @p_invoice_id;

            IF @org_id IS NULL THROW 55005, 'Vehicle not enrolled in an enterprise fleet organization.', 1;
            IF (@current_balance + @p_paid_amount) > @credit_limit
                THROW 55006, 'Credit line limit exceeded.', 1;

            UPDATE dbo.FleetOrg SET current_balance = current_balance + @p_paid_amount, updated_at = SYSDATETIME() WHERE org_id = @org_id;
        END

        INSERT INTO dbo.Payment (invoice_id, payment_method, paid_amount, transaction_ref, settled_at)
        VALUES (@p_invoice_id, @p_payment_method, @p_paid_amount, @p_transaction_ref, SYSDATETIME());
        SET @p_payment_id = SCOPE_IDENTITY();

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

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
        IF NOT EXISTS (SELECT 1 FROM dbo.ChargerBay WHERE bay_id = @p_bay_id) THROW 56001, 'Charger bay does not exist.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.AppUser WHERE user_id = @p_technician_id AND user_role IN ('TECHNICIAN', 'ADMIN', 'DEPOT_MANAGER'))
            THROW 56002, 'User must have role TECHNICIAN, ADMIN, or DEPOT_MANAGER.', 1;

        INSERT INTO dbo.MaintenanceLog (bay_id, technician_id, issue_reported, reported_at, repair_status)
        VALUES (@p_bay_id, @p_technician_id, @p_issue_reported, SYSDATETIME(), 'OPEN');
        SET @p_log_id = SCOPE_IDENTITY();

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ResolveMaintenanceIssue
    @p_log_id INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @current_status VARCHAR(20);
        SELECT @current_status = repair_status FROM dbo.MaintenanceLog WITH (UPDLOCK) WHERE log_id = @p_log_id;

        IF @current_status IS NULL THROW 57001, 'Maintenance log record not found.', 1;
        IF @current_status = 'RESOLVED' THROW 57002, 'Issue already resolved.', 1;

        UPDATE dbo.MaintenanceLog SET repair_status = 'RESOLVED', resolved_at = SYSDATETIME(), updated_at = SYSDATETIME() WHERE log_id = @p_log_id;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_GetChargingPriority
    @p_station_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT 
        fm.mission_id, v.vin, fo.company_name AS organization, v.license_plate, v.ownership_type,
        v.current_soc_pct AS current_soc, fm.target_soc_pct AS target_soc, fm.departure_time,
        v.battery_capacity_kwh AS battery_capacity,
        ROUND((v.battery_capacity_kwh * (CASE WHEN fm.target_soc_pct > v.current_soc_pct THEN (fm.target_soc_pct - v.current_soc_pct) ELSE 0 END)) / 100.0, 2) AS estimated_energy_required_kwh,
        v.max_charge_rate_kw AS max_charge_rate,
        DATEDIFF(MINUTE, SYSDATETIME(), fm.departure_time) AS minutes_until_departure,
        ROUND(
            (CASE WHEN v.ownership_type = 'FLEET' THEN 50.0 ELSE 10.0 END)
            + (CASE WHEN fm.target_soc_pct > v.current_soc_pct THEN (fm.target_soc_pct - v.current_soc_pct) * 0.5 ELSE 0 END)
            + (CASE 
                WHEN DATEDIFF(MINUTE, SYSDATETIME(), fm.departure_time) <= 0 THEN 100.0
                WHEN DATEDIFF(MINUTE, SYSDATETIME(), fm.departure_time) <= 60 THEN 80.0
                WHEN DATEDIFF(MINUTE, SYSDATETIME(), fm.departure_time) <= 180 THEN 50.0
                WHEN DATEDIFF(MINUTE, SYSDATETIME(), fm.departure_time) <= 360 THEN 30.0
                ELSE 10.0
               END), 2
        ) AS urgency_priority_score
    FROM dbo.FleetMission fm
    INNER JOIN dbo.Vehicle v ON fm.vin = v.vin
    LEFT JOIN dbo.FleetOrg fo ON v.org_id = fo.org_id
    WHERE fm.mission_status = 'SCHEDULED'
    ORDER BY urgency_priority_score DESC, fm.departure_time ASC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_GetAvailableBays
    @p_station_id INT,
    @p_start_time DATETIME2(7),
    @p_end_time   DATETIME2(7),
    @p_plug_type  VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @p_start_time >= @p_end_time THROW 58001, 'start_time must be earlier than end_time.', 1;

    SELECT 
        cb.bay_id, cb.station_id, cs.station_name, cb.bay_number, cb.plug_type,
        cb.max_kw_output, cb.is_operational, cs.city
    FROM dbo.ChargerBay cb
    INNER JOIN dbo.ChargingStation cs ON cb.station_id = cs.station_id
    WHERE cb.station_id = @p_station_id
      AND cb.is_operational = 1
      AND cs.status = 'ACTIVE'
      AND (@p_plug_type IS NULL OR cb.plug_type = @p_plug_type)
      AND NOT EXISTS (
          SELECT 1 FROM dbo.Reservation r
          WHERE r.bay_id = cb.bay_id
            AND r.reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE')
            AND r.start_time < @p_end_time AND r.end_time > @p_start_time
      )
    ORDER BY cb.bay_number ASC;
END;
GO

-- ============================================================================
-- SECTION 6: ANALYTICAL & REPORTING VIEWS
-- ============================================================================

CREATE OR ALTER VIEW dbo.vw_StationCapacity
AS
SELECT 
    cs.station_id, cs.station_name, cs.city, cs.status AS station_status,
    sub.substation_id, sub.name AS substation_name,
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
    SELECT COUNT(sess.session_id) AS active_session_count, SUM(sess.allocated_kw) AS current_power_draw_kw
    FROM dbo.ChargingSession sess
    INNER JOIN dbo.ChargerBay b ON sess.bay_id = b.bay_id
    WHERE b.station_id = cs.station_id AND sess.status IN ('STARTED', 'CHARGING')
) active_sessions
GROUP BY cs.station_id, cs.station_name, cs.city, cs.status, sub.substation_id, sub.name, active_sessions.active_session_count, active_sessions.current_power_draw_kw;
GO

CREATE OR ALTER VIEW dbo.vw_CurrentSubstationLoad
AS
SELECT 
    sub.substation_id, sub.name AS substation_name, sub.region_code, sub.max_grid_capacity_kw,
    COUNT(DISTINCT cs.station_id) AS connected_stations,
    COUNT(DISTINCT cb.bay_id) AS connected_bays,
    ISNULL(SUM(active_sessions.allocated_kw), 0.00) AS current_allocated_load_kw,
    (sub.max_grid_capacity_kw - ISNULL(SUM(active_sessions.allocated_kw), 0.00)) AS available_headroom_kw,
    ROUND((ISNULL(SUM(active_sessions.allocated_kw), 0.00) / NULLIF(sub.max_grid_capacity_kw, 0)) * 100.0, 2) AS grid_utilization_pct
FROM dbo.Substation sub
LEFT JOIN dbo.ChargingStation cs ON sub.substation_id = cs.substation_id
LEFT JOIN dbo.ChargerBay cb ON cs.station_id = cb.station_id
LEFT JOIN dbo.ChargingSession active_sessions ON cb.bay_id = active_sessions.bay_id AND active_sessions.status IN ('STARTED', 'CHARGING')
GROUP BY sub.substation_id, sub.name, sub.region_code, sub.max_grid_capacity_kw;
GO

CREATE OR ALTER VIEW dbo.vw_AvailableChargerBays
AS
SELECT 
    cb.bay_id, cb.station_id, cs.station_name, cs.city, cb.bay_number, cb.plug_type, cb.max_kw_output, cb.is_operational,
    sub.name AS substation_name, (sub.max_grid_capacity_kw - ISNULL(sub_load.CurrentLoad, 0.00)) AS substation_headroom_kw
FROM dbo.ChargerBay cb
INNER JOIN dbo.ChargingStation cs ON cb.station_id = cs.station_id
INNER JOIN dbo.Substation sub ON cs.substation_id = sub.substation_id
OUTER APPLY (
    SELECT SUM(sess.allocated_kw) AS CurrentLoad
    FROM dbo.ChargingSession sess
    INNER JOIN dbo.ChargerBay b ON sess.bay_id = b.bay_id
    INNER JOIN dbo.ChargingStation s ON b.station_id = s.station_id
    WHERE s.substation_id = sub.substation_id AND sess.status IN ('STARTED', 'CHARGING')
) sub_load
WHERE cb.is_operational = 1 AND cs.status = 'ACTIVE'
  AND NOT EXISTS (
      SELECT 1 FROM dbo.ChargingSession csess WHERE csess.bay_id = cb.bay_id AND csess.status IN ('STARTED', 'CHARGING')
  );
GO

CREATE OR ALTER VIEW dbo.vw_ChargingPriority
AS
SELECT 
    fm.mission_id, v.vin, ISNULL(fo.company_name, 'Independent Retail Driver') AS organization_name,
    v.license_plate, v.ownership_type, v.battery_capacity_kwh, v.current_soc_pct AS current_soc,
    fm.target_soc_pct AS target_soc, fm.departure_time,
    DATEDIFF(MINUTE, SYSDATETIME(), fm.departure_time) AS minutes_until_departure,
    ROUND((v.battery_capacity_kwh * (CASE WHEN fm.target_soc_pct > v.current_soc_pct THEN (fm.target_soc_pct - v.current_soc_pct) ELSE 0 END)) / 100.0, 2) AS estimated_energy_required_kwh,
    v.max_charge_rate_kw AS vehicle_max_charge_rate_kw, fm.route_distance_km,
    ROUND(
        (CASE WHEN v.ownership_type = 'FLEET' THEN 50.0 ELSE 10.0 END)
        + (CASE WHEN fm.target_soc_pct > v.current_soc_pct THEN (fm.target_soc_pct - v.current_soc_pct) * 0.5 ELSE 0 END)
        + (CASE 
            WHEN DATEDIFF(MINUTE, SYSDATETIME(), fm.departure_time) <= 0 THEN 100.0
            WHEN DATEDIFF(MINUTE, SYSDATETIME(), fm.departure_time) <= 60 THEN 80.0
            WHEN DATEDIFF(MINUTE, SYSDATETIME(), fm.departure_time) <= 180 THEN 50.0
            WHEN DATEDIFF(MINUTE, SYSDATETIME(), fm.departure_time) <= 360 THEN 30.0
            ELSE 10.0
           END), 2
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

CREATE OR ALTER VIEW dbo.vw_InvoiceSummary
AS
SELECT 
    inv.invoice_id, inv.session_id, cs.vin, v.license_plate, u.full_name AS driver_name,
    ISNULL(fo.company_name, 'Retail Customer') AS billing_account,
    stat.station_name, cs.energy_delivered_kwh, cs.idle_minutes,
    inv.energy_charge, inv.idle_penalty_charge, inv.tax_amount, inv.total_amount,
    ISNULL(payments.total_paid, 0.00) AS total_paid,
    (inv.total_amount - ISNULL(payments.total_paid, 0.00)) AS balance_due,
    inv.status AS invoice_status, inv.created_at AS invoice_date
FROM dbo.Invoice inv
INNER JOIN dbo.ChargingSession cs ON inv.session_id = cs.session_id
INNER JOIN dbo.ChargerBay cb ON cs.bay_id = cb.bay_id
INNER JOIN dbo.ChargingStation stat ON cb.station_id = stat.station_id
INNER JOIN dbo.Vehicle v ON cs.vin = v.vin
INNER JOIN dbo.AppUser u ON cs.user_id = u.user_id
LEFT JOIN dbo.FleetOrg fo ON v.org_id = fo.org_id
OUTER APPLY (
    SELECT SUM(p.paid_amount) AS total_paid FROM dbo.Payment p WHERE p.invoice_id = inv.invoice_id
) payments;
GO

CREATE OR ALTER VIEW dbo.vw_FleetChargingSummary
AS
SELECT 
    fo.org_id, fo.company_name, fo.tax_id, fo.credit_line_limit,
    fo.current_balance AS credit_utilized, (fo.credit_line_limit - fo.current_balance) AS available_credit,
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
GROUP BY fo.org_id, fo.company_name, fo.tax_id, fo.credit_line_limit, fo.current_balance;
GO

CREATE OR ALTER VIEW dbo.vw_MaintenanceStatus
AS
SELECT 
    ml.log_id, ml.bay_id, cb.bay_number, cs.station_name, cs.city, cb.plug_type, cb.is_operational,
    u.full_name AS technician_name, ml.issue_reported, ml.reported_at, ml.resolved_at, ml.repair_status,
    DATEDIFF(HOUR, ml.reported_at, ISNULL(ml.resolved_at, SYSDATETIME())) AS downtime_hours
FROM dbo.MaintenanceLog ml
INNER JOIN dbo.ChargerBay cb ON ml.bay_id = cb.bay_id
INNER JOIN dbo.ChargingStation cs ON cb.station_id = cs.station_id
INNER JOIN dbo.AppUser u ON ml.technician_id = u.user_id;
GO

PRINT 'Master schema installation completed successfully.';
GO
