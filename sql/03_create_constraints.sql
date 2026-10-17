-- ============================================================================
-- SCRIPT: 03_create_constraints.sql
-- SYSTEM: Intelligent EV Charging Station and Fleet/Depot Management System
-- DIALECT: Microsoft SQL Server (T-SQL)
-- DESCRIPTION: Applies Foreign Keys, UNIQUE constraints, and CHECK constraints
--              to guarantee relational and domain integrity across all tables.
-- ============================================================================

USE EVChargingDB;
GO

PRINT 'Applying Foreign Key constraints...';

-- 1. ChargingStation -> Substation
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ChargingStation_Substation')
    ALTER TABLE dbo.ChargingStation
    ADD CONSTRAINT FK_ChargingStation_Substation
    FOREIGN KEY (substation_id) REFERENCES dbo.Substation (substation_id)
    ON DELETE NO ACTION ON UPDATE CASCADE;

-- 2. ChargerBay -> ChargingStation
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ChargerBay_ChargingStation')
    ALTER TABLE dbo.ChargerBay
    ADD CONSTRAINT FK_ChargerBay_ChargingStation
    FOREIGN KEY (station_id) REFERENCES dbo.ChargingStation (station_id)
    ON DELETE CASCADE ON UPDATE CASCADE;

-- 3. TariffPlan -> ChargingStation
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_TariffPlan_ChargingStation')
    ALTER TABLE dbo.TariffPlan
    ADD CONSTRAINT FK_TariffPlan_ChargingStation
    FOREIGN KEY (station_id) REFERENCES dbo.ChargingStation (station_id)
    ON DELETE CASCADE ON UPDATE CASCADE;

-- 4. AppUser -> FleetOrg (Nullable for independent/retail users)
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_AppUser_FleetOrg')
    ALTER TABLE dbo.AppUser
    ADD CONSTRAINT FK_AppUser_FleetOrg
    FOREIGN KEY (org_id) REFERENCES dbo.FleetOrg (org_id)
    ON DELETE SET NULL ON UPDATE CASCADE;

-- 5. Vehicle -> FleetOrg & AppUser
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Vehicle_FleetOrg')
    ALTER TABLE dbo.Vehicle
    ADD CONSTRAINT FK_Vehicle_FleetOrg
    FOREIGN KEY (org_id) REFERENCES dbo.FleetOrg (org_id)
    ON DELETE NO ACTION ON UPDATE CASCADE;

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Vehicle_AppUser')
    ALTER TABLE dbo.Vehicle
    ADD CONSTRAINT FK_Vehicle_AppUser
    FOREIGN KEY (user_id) REFERENCES dbo.AppUser (user_id)
    ON DELETE NO ACTION ON UPDATE NO ACTION;

-- 6. FleetMission -> Vehicle & AppUser (Driver)
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_FleetMission_Vehicle')
    ALTER TABLE dbo.FleetMission
    ADD CONSTRAINT FK_FleetMission_Vehicle
    FOREIGN KEY (vin) REFERENCES dbo.Vehicle (vin)
    ON DELETE CASCADE ON UPDATE CASCADE;

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_FleetMission_AppUser')
    ALTER TABLE dbo.FleetMission
    ADD CONSTRAINT FK_FleetMission_AppUser
    FOREIGN KEY (driver_id) REFERENCES dbo.AppUser (user_id)
    ON DELETE NO ACTION ON UPDATE NO ACTION;

-- 7. Reservation -> ChargerBay, Vehicle, AppUser
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Reservation_ChargerBay')
    ALTER TABLE dbo.Reservation
    ADD CONSTRAINT FK_Reservation_ChargerBay
    FOREIGN KEY (bay_id) REFERENCES dbo.ChargerBay (bay_id)
    ON DELETE NO ACTION ON UPDATE CASCADE;

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Reservation_Vehicle')
    ALTER TABLE dbo.Reservation
    ADD CONSTRAINT FK_Reservation_Vehicle
    FOREIGN KEY (vin) REFERENCES dbo.Vehicle (vin)
    ON DELETE NO ACTION ON UPDATE CASCADE;

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Reservation_AppUser')
    ALTER TABLE dbo.Reservation
    ADD CONSTRAINT FK_Reservation_AppUser
    FOREIGN KEY (user_id) REFERENCES dbo.AppUser (user_id)
    ON DELETE NO ACTION ON UPDATE NO ACTION;

-- 8. ChargingSession -> ChargerBay, Vehicle, AppUser, Reservation
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ChargingSession_ChargerBay')
    ALTER TABLE dbo.ChargingSession
    ADD CONSTRAINT FK_ChargingSession_ChargerBay
    FOREIGN KEY (bay_id) REFERENCES dbo.ChargerBay (bay_id)
    ON DELETE NO ACTION ON UPDATE CASCADE;

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ChargingSession_Vehicle')
    ALTER TABLE dbo.ChargingSession
    ADD CONSTRAINT FK_ChargingSession_Vehicle
    FOREIGN KEY (vin) REFERENCES dbo.Vehicle (vin)
    ON DELETE NO ACTION ON UPDATE CASCADE;

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ChargingSession_AppUser')
    ALTER TABLE dbo.ChargingSession
    ADD CONSTRAINT FK_ChargingSession_AppUser
    FOREIGN KEY (user_id) REFERENCES dbo.AppUser (user_id)
    ON DELETE NO ACTION ON UPDATE NO ACTION;

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ChargingSession_Reservation')
    ALTER TABLE dbo.ChargingSession
    ADD CONSTRAINT FK_ChargingSession_Reservation
    FOREIGN KEY (reservation_id) REFERENCES dbo.Reservation (reservation_id)
    ON DELETE NO ACTION ON UPDATE NO ACTION;

-- 9. MaintenanceLog -> ChargerBay, AppUser (Technician)
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_MaintenanceLog_ChargerBay')
    ALTER TABLE dbo.MaintenanceLog
    ADD CONSTRAINT FK_MaintenanceLog_ChargerBay
    FOREIGN KEY (bay_id) REFERENCES dbo.ChargerBay (bay_id)
    ON DELETE CASCADE ON UPDATE CASCADE;

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_MaintenanceLog_AppUser')
    ALTER TABLE dbo.MaintenanceLog
    ADD CONSTRAINT FK_MaintenanceLog_AppUser
    FOREIGN KEY (technician_id) REFERENCES dbo.AppUser (user_id)
    ON DELETE NO ACTION ON UPDATE NO ACTION;

-- 10. Invoice -> ChargingSession (1-to-1)
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Invoice_ChargingSession')
    ALTER TABLE dbo.Invoice
    ADD CONSTRAINT FK_Invoice_ChargingSession
    FOREIGN KEY (session_id) REFERENCES dbo.ChargingSession (session_id)
    ON DELETE NO ACTION ON UPDATE CASCADE;

-- 11. Payment -> Invoice
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Payment_Invoice')
    ALTER TABLE dbo.Payment
    ADD CONSTRAINT FK_Payment_Invoice
    FOREIGN KEY (invoice_id) REFERENCES dbo.Invoice (invoice_id)
    ON DELETE CASCADE ON UPDATE CASCADE;

PRINT 'Foreign Key constraints applied successfully.';
GO

PRINT 'Applying UNIQUE constraints...';

-- ChargerBay: Unique bay number per station
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_ChargerBay_Station_Bay')
    ALTER TABLE dbo.ChargerBay
    ADD CONSTRAINT UQ_ChargerBay_Station_Bay UNIQUE (station_id, bay_number);

-- FleetOrg: Tax ID must be unique
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_FleetOrg_TaxId')
    ALTER TABLE dbo.FleetOrg
    ADD CONSTRAINT UQ_FleetOrg_TaxId UNIQUE (tax_id);

-- AppUser: Email must be unique
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_AppUser_Email')
    ALTER TABLE dbo.AppUser
    ADD CONSTRAINT UQ_AppUser_Email UNIQUE (email);

-- Vehicle: License plate must be unique
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_Vehicle_LicensePlate')
    ALTER TABLE dbo.Vehicle
    ADD CONSTRAINT UQ_Vehicle_LicensePlate UNIQUE (license_plate);

-- Invoice: Session ID is 1-to-1 with Invoice
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_Invoice_SessionId')
    ALTER TABLE dbo.Invoice
    ADD CONSTRAINT UQ_Invoice_SessionId UNIQUE (session_id);

-- Payment: Transaction reference must be unique
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_Payment_TransactionRef')
    ALTER TABLE dbo.Payment
    ADD CONSTRAINT UQ_Payment_TransactionRef UNIQUE (transaction_ref);

PRINT 'UNIQUE constraints applied successfully.';
GO

PRINT 'Applying CHECK constraints...';

-- 1. Substation
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Substation_MaxCapacity')
    ALTER TABLE dbo.Substation
    ADD CONSTRAINT CK_Substation_MaxCapacity CHECK (max_grid_capacity_kw > 0.00);

-- 2. ChargingStation
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_ChargingStation_Status')
    ALTER TABLE dbo.ChargingStation
    ADD CONSTRAINT CK_ChargingStation_Status CHECK (status IN ('ACTIVE', 'INACTIVE', 'MAINTENANCE', 'OFFLINE'));

-- 3. ChargerBay
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_ChargerBay_PlugType')
    ALTER TABLE dbo.ChargerBay
    ADD CONSTRAINT CK_ChargerBay_PlugType CHECK (plug_type IN ('CCS2', 'TYPE2', 'NACS'));

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_ChargerBay_MaxKw')
    ALTER TABLE dbo.ChargerBay
    ADD CONSTRAINT CK_ChargerBay_MaxKw CHECK (max_kw_output > 0.00);

-- 4. TariffPlan
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_TariffPlan_StartHour')
    ALTER TABLE dbo.TariffPlan
    ADD CONSTRAINT CK_TariffPlan_StartHour CHECK (start_hour BETWEEN 0 AND 23);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_TariffPlan_EndHour')
    ALTER TABLE dbo.TariffPlan
    ADD CONSTRAINT CK_TariffPlan_EndHour CHECK (end_hour BETWEEN 0 AND 23);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_TariffPlan_BaseRate')
    ALTER TABLE dbo.TariffPlan
    ADD CONSTRAINT CK_TariffPlan_BaseRate CHECK (base_rate_per_kwh >= 0.0000);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_TariffPlan_IdleFee')
    ALTER TABLE dbo.TariffPlan
    ADD CONSTRAINT CK_TariffPlan_IdleFee CHECK (idle_fee_per_min >= 0.0000);

-- 5. FleetOrg
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_FleetOrg_CreditLimit')
    ALTER TABLE dbo.FleetOrg
    ADD CONSTRAINT CK_FleetOrg_CreditLimit CHECK (credit_line_limit >= 0.00);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_FleetOrg_CurrentBalance')
    ALTER TABLE dbo.FleetOrg
    ADD CONSTRAINT CK_FleetOrg_CurrentBalance CHECK (current_balance >= 0.00);

-- 6. AppUser
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_AppUser_UserRole')
    ALTER TABLE dbo.AppUser
    ADD CONSTRAINT CK_AppUser_UserRole CHECK (user_role IN ('DRIVER', 'DEPOT_MANAGER', 'TECHNICIAN', 'ADMIN'));

-- 7. Vehicle
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Vehicle_BatteryCapacity')
    ALTER TABLE dbo.Vehicle
    ADD CONSTRAINT CK_Vehicle_BatteryCapacity CHECK (battery_capacity_kwh > 0.00);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Vehicle_MaxChargeRate')
    ALTER TABLE dbo.Vehicle
    ADD CONSTRAINT CK_Vehicle_MaxChargeRate CHECK (max_charge_rate_kw > 0.00);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Vehicle_CurrentSoc')
    ALTER TABLE dbo.Vehicle
    ADD CONSTRAINT CK_Vehicle_CurrentSoc CHECK (current_soc_pct >= 0.00 AND current_soc_pct <= 100.00);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Vehicle_OwnershipType')
    ALTER TABLE dbo.Vehicle
    ADD CONSTRAINT CK_Vehicle_OwnershipType CHECK (ownership_type IN ('FLEET', 'PRIVATE', 'LEASED'));

-- 8. FleetMission
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_FleetMission_TargetSoc')
    ALTER TABLE dbo.FleetMission
    ADD CONSTRAINT CK_FleetMission_TargetSoc CHECK (target_soc_pct >= 0.00 AND target_soc_pct <= 100.00);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_FleetMission_RouteDistance')
    ALTER TABLE dbo.FleetMission
    ADD CONSTRAINT CK_FleetMission_RouteDistance CHECK (route_distance_km >= 0.00);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_FleetMission_Status')
    ALTER TABLE dbo.FleetMission
    ADD CONSTRAINT CK_FleetMission_Status CHECK (mission_status IN ('SCHEDULED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'));

-- 9. Reservation
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Reservation_TimeInterval')
    ALTER TABLE dbo.Reservation
    ADD CONSTRAINT CK_Reservation_TimeInterval CHECK (start_time < end_time);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Reservation_Status')
    ALTER TABLE dbo.Reservation
    ADD CONSTRAINT CK_Reservation_Status CHECK (reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE', 'COMPLETED', 'CANCELLED', 'NO_SHOW'));

-- 10. ChargingSession
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_ChargingSession_TimeInterval')
    ALTER TABLE dbo.ChargingSession
    ADD CONSTRAINT CK_ChargingSession_TimeInterval CHECK (end_time IS NULL OR start_time <= end_time);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_ChargingSession_AllocatedKw')
    ALTER TABLE dbo.ChargingSession
    ADD CONSTRAINT CK_ChargingSession_AllocatedKw CHECK (allocated_kw > 0.00);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_ChargingSession_EnergyDelivered')
    ALTER TABLE dbo.ChargingSession
    ADD CONSTRAINT CK_ChargingSession_EnergyDelivered CHECK (energy_delivered_kwh >= 0.000);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_ChargingSession_IdleMinutes')
    ALTER TABLE dbo.ChargingSession
    ADD CONSTRAINT CK_ChargingSession_IdleMinutes CHECK (idle_minutes >= 0);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_ChargingSession_Status')
    ALTER TABLE dbo.ChargingSession
    ADD CONSTRAINT CK_ChargingSession_Status CHECK (status IN ('STARTED', 'CHARGING', 'COMPLETED', 'CANCELLED', 'FAULT'));

-- 11. MaintenanceLog
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_MaintenanceLog_TimeInterval')
    ALTER TABLE dbo.MaintenanceLog
    ADD CONSTRAINT CK_MaintenanceLog_TimeInterval CHECK (resolved_at IS NULL OR reported_at <= resolved_at);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_MaintenanceLog_RepairStatus')
    ALTER TABLE dbo.MaintenanceLog
    ADD CONSTRAINT CK_MaintenanceLog_RepairStatus CHECK (repair_status IN ('OPEN', 'IN_PROGRESS', 'RESOLVED', 'CANCELLED'));

-- 12. Invoice
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Invoice_EnergyCharge')
    ALTER TABLE dbo.Invoice
    ADD CONSTRAINT CK_Invoice_EnergyCharge CHECK (energy_charge >= 0.00);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Invoice_IdlePenalty')
    ALTER TABLE dbo.Invoice
    ADD CONSTRAINT CK_Invoice_IdlePenalty CHECK (idle_penalty_charge >= 0.00);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Invoice_TaxAmount')
    ALTER TABLE dbo.Invoice
    ADD CONSTRAINT CK_Invoice_TaxAmount CHECK (tax_amount >= 0.00);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Invoice_Status')
    ALTER TABLE dbo.Invoice
    ADD CONSTRAINT CK_Invoice_Status CHECK (status IN ('PENDING', 'PAID', 'PARTIALLY_PAID', 'CANCELLED', 'OVERDUE'));

-- 13. Payment
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Payment_PaidAmount')
    ALTER TABLE dbo.Payment
    ADD CONSTRAINT CK_Payment_PaidAmount CHECK (paid_amount > 0.00);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Payment_PaymentMethod')
    ALTER TABLE dbo.Payment
    ADD CONSTRAINT CK_Payment_PaymentMethod CHECK (payment_method IN ('UPI', 'CARD', 'NET_BANKING', 'WALLET', 'CREDIT_LINE'));

PRINT 'CHECK constraints applied successfully.';
GO
