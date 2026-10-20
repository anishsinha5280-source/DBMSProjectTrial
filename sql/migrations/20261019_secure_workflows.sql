-- Apply AFTER sql/supabase_schema.sql. Back up an existing database first.
-- Atomic migration: no existing customers, vehicles, invoices or payments are deleted.
BEGIN;
REVOKE CREATE ON SCHEMA public FROM PUBLIC,anon,authenticated;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE TABLE IF NOT EXISTS public.gs_migration (version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now());
DO $$ BEGIN
 IF EXISTS (SELECT FROM public.gs_migration WHERE version='20261019') THEN
  RAISE EXCEPTION 'Migration 20261019 is already applied; do not run twice.';
 END IF;
END $$;
ALTER TABLE public.app_user ADD COLUMN auth_user_id uuid UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.app_user ADD COLUMN role text NOT NULL DEFAULT 'customer' CHECK(role IN ('customer','manager'));
ALTER TABLE public.vehicle ALTER COLUMN org_id DROP NOT NULL;
ALTER TABLE public.vehicle ALTER COLUMN vin DROP NOT NULL;
ALTER TABLE public.vehicle ALTER COLUMN battery_capacity_kwh DROP NOT NULL;
ALTER TABLE public.vehicle ALTER COLUMN max_charge_rate_kw DROP NOT NULL;
ALTER TABLE public.vehicle ADD COLUMN make text NOT NULL DEFAULT '', ADD COLUMN model text NOT NULL DEFAULT '',
 ADD COLUMN vehicle_type text NOT NULL DEFAULT 'car', ADD COLUMN connector_types text[] NOT NULL DEFAULT '{}', ADD COLUMN archived_at timestamptz;
ALTER TABLE public.vehicle ADD CONSTRAINT gs_vehicle_numbers CHECK ((battery_capacity_kwh IS NULL OR battery_capacity_kwh>0) AND (max_charge_rate_kw IS NULL OR max_charge_rate_kw>0));
CREATE UNIQUE INDEX gs_vehicle_owner_registration ON public.vehicle(user_id, upper(regexp_replace(license_plate,'[^A-Za-z0-9]','','g'))) WHERE archived_at IS NULL;
ALTER TABLE public.substation ADD COLUMN code text, ADD COLUMN location text NOT NULL DEFAULT '',
 ADD COLUMN operational_status text NOT NULL DEFAULT 'operational' CHECK(operational_status IN ('operational','maintenance','offline')),
 ADD COLUMN base_load_kw numeric(10,2) NOT NULL DEFAULT 0 CHECK(base_load_kw>=0),
 ADD COLUMN capacity_limit_pct numeric(5,2) NOT NULL DEFAULT 90 CHECK(capacity_limit_pct>0 AND capacity_limit_pct<=100),
 ADD COLUMN load_source text NOT NULL DEFAULT 'estimated' CHECK(load_source IN ('estimated','manual','simulated')),
 ADD COLUMN monitored_at timestamptz, ADD COLUMN constraints_note text NOT NULL DEFAULT '';
UPDATE public.substation SET code='GRID-'||substation_id;
ALTER TABLE public.substation ALTER COLUMN code SET NOT NULL;
ALTER TABLE public.substation ADD CONSTRAINT gs_substation_code UNIQUE(code), ADD CONSTRAINT gs_capacity CHECK(max_grid_capacity_kw>0 AND base_load_kw<=max_grid_capacity_kw);
ALTER TABLE public.charging_station ADD COLUMN timezone text NOT NULL DEFAULT 'Asia/Kolkata';
ALTER TABLE public.tariff_plan ADD COLUMN currency text NOT NULL DEFAULT 'INR' CHECK(currency ~ '^[A-Z]{3}$'),
 ADD COLUMN tax_pct numeric(6,3) NOT NULL DEFAULT 0 CHECK(tax_pct>=0 AND tax_pct<=100),
 ADD COLUMN service_fee numeric(10,2) NOT NULL DEFAULT 0 CHECK(service_fee>=0),
 ADD COLUMN discount_amount numeric(10,2) NOT NULL DEFAULT 0 CHECK(discount_amount>=0),
 ADD COLUMN active boolean NOT NULL DEFAULT true;
ALTER TABLE public.tariff_plan ADD CONSTRAINT gs_tariff_hours CHECK(start_hour>=0 AND start_hour<24 AND end_hour>start_hour AND end_hour<=24 AND base_rate_per_kwh>=0 AND idle_fee_per_min>=0);
ALTER TABLE public.charging_session ALTER COLUMN start_time DROP NOT NULL;
ALTER TABLE public.charging_session ALTER COLUMN start_time DROP DEFAULT;
ALTER TABLE public.charging_session ADD COLUMN scheduled_at timestamptz, ADD COLUMN initial_meter_kwh numeric(14,3),
 ADD COLUMN final_meter_kwh numeric(14,3), ADD COLUMN meter_source text NOT NULL DEFAULT 'legacy_unverified',
 ADD COLUMN simulation_elapsed_seconds integer NOT NULL DEFAULT 0 CHECK(simulation_elapsed_seconds>=0),
 ADD COLUMN tariff_snapshot jsonb, ADD COLUMN failure_reason text, ADD COLUMN cancellation_reason text,
 ADD COLUMN meter_updated_at timestamptz;
UPDATE public.charging_session SET status=CASE upper(status) WHEN 'STARTED' THEN 'active' WHEN 'CHARGING' THEN 'active' ELSE lower(status) END;
ALTER TABLE public.charging_session ADD CONSTRAINT gs_session_status CHECK(status IN ('scheduled','queued','active','completed','cancelled','failed'));
CREATE UNIQUE INDEX gs_active_bay ON public.charging_session(bay_id) WHERE status='active';
CREATE UNIQUE INDEX gs_active_vehicle ON public.charging_session(vehicle_id) WHERE status='active';
CREATE UNIQUE INDEX gs_session_reservation ON public.charging_session(reservation_id) WHERE reservation_id IS NOT NULL;
CREATE UNIQUE INDEX gs_invoice_session ON public.invoice(session_id);
ALTER TABLE public.invoice ADD COLUMN invoice_number text, ADD COLUMN currency text NOT NULL DEFAULT 'INR',
 ADD COLUMN service_fee numeric(10,2) NOT NULL DEFAULT 0, ADD COLUMN discount_amount numeric(10,2) NOT NULL DEFAULT 0,
 ADD COLUMN snapshot jsonb, ADD COLUMN paid_at timestamptz;
UPDATE public.invoice SET invoice_number='GS-LEGACY-'||lpad(invoice_id::text,7,'0');
ALTER TABLE public.invoice ALTER COLUMN invoice_number SET NOT NULL;
ALTER TABLE public.invoice ADD CONSTRAINT gs_invoice_number UNIQUE(invoice_number);
ALTER TABLE public.invoice DROP COLUMN total_amount;
ALTER TABLE public.invoice ADD COLUMN total_amount numeric(12,2) GENERATED ALWAYS AS (energy_charge+idle_penalty_charge+service_fee-discount_amount+tax_amount) STORED;
ALTER TABLE public.payment ADD COLUMN status text NOT NULL DEFAULT 'paid' CHECK(status IN ('pending','paid','failed','refunded')),
 ADD COLUMN is_test boolean NOT NULL DEFAULT false, ADD COLUMN currency text NOT NULL DEFAULT 'INR',
 ADD COLUMN idempotency_key uuid UNIQUE, ADD COLUMN failure_reason text, ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now(), ADD COLUMN refunded_at timestamptz;
ALTER TABLE public.payment ALTER COLUMN settled_at DROP NOT NULL;
ALTER TABLE public.payment ALTER COLUMN settled_at DROP DEFAULT;
CREATE UNIQUE INDEX gs_payment_transaction ON public.payment(transaction_ref);
CREATE UNIQUE INDEX gs_payment_pending_or_paid ON public.payment(invoice_id) WHERE status IN ('pending','paid');
CREATE TABLE public.gs_settings (id boolean PRIMARY KEY DEFAULT true CHECK(id), test_payments_enabled boolean NOT NULL DEFAULT false);
INSERT INTO public.gs_settings DEFAULT VALUES;
CREATE TABLE public.gs_audit (audit_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, actor uuid, action text NOT NULL, entity_id bigint, created_at timestamptz NOT NULL DEFAULT now());

-- Profile role is NEVER copied from user-editable authentication metadata.
CREATE OR REPLACE FUNCTION public.gs_new_auth_user() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 INSERT INTO app_user(auth_user_id,full_name,email,phone,user_role,role)
 VALUES(NEW.id,left(coalesce(NEW.raw_user_meta_data->>'full_name','Customer'),100),NEW.email,'','PERSONAL','customer');
 RETURN NEW;
END $$;
CREATE TRIGGER gs_auth_profile AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.gs_new_auth_user();
-- Existing Auth identities get NEW isolated profiles. Never claim legacy data by matching email.
INSERT INTO public.app_user(auth_user_id,full_name,email,phone,user_role,role)
 SELECT a.id,left(coalesce(a.raw_user_meta_data->>'full_name','Customer'),100),coalesce(a.email,''),'','PERSONAL','customer'
 FROM auth.users a WHERE NOT EXISTS(SELECT FROM public.app_user u WHERE u.auth_user_id=a.id);
CREATE OR REPLACE FUNCTION public.gs_uid() RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$ SELECT user_id FROM app_user WHERE auth_user_id=auth.uid() $$;
CREATE OR REPLACE FUNCTION public.gs_manager() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$ SELECT coalesce((SELECT role='manager' FROM app_user WHERE auth_user_id=auth.uid()),false) $$;

-- Lock down both the API and direct Supabase access. All writes use validated RPCs.
DO $$ DECLARE t text; p record; BEGIN
 FOREACH t IN ARRAY ARRAY['substation','charging_station','charger_bay','tariff_plan','fleet_org','app_user','vehicle','fleet_mission','reservation','charging_session','maintenance_log','invoice','payment','gs_settings','gs_audit','gs_migration'] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
  FOR p IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename=t LOOP EXECUTE format('DROP POLICY %I ON public.%I',p.policyname,t); END LOOP;
  EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC,anon,authenticated',t);
 END LOOP;
END $$;
GRANT SELECT ON public.substation,public.charging_station,public.charger_bay,public.tariff_plan,public.fleet_org,public.app_user,public.vehicle,public.fleet_mission,public.reservation,public.charging_session,public.invoice,public.payment,public.gs_audit TO authenticated;
CREATE POLICY gs_read ON public.substation FOR SELECT TO authenticated USING(true);
CREATE POLICY gs_read ON public.charging_station FOR SELECT TO authenticated USING(true);
CREATE POLICY gs_read ON public.charger_bay FOR SELECT TO authenticated USING(true);
CREATE POLICY gs_read ON public.tariff_plan FOR SELECT TO authenticated USING(true);
CREATE POLICY gs_read ON public.app_user FOR SELECT TO authenticated USING(auth_user_id=auth.uid() OR gs_manager());
CREATE POLICY gs_read ON public.vehicle FOR SELECT TO authenticated USING(user_id=gs_uid() OR gs_manager());
CREATE POLICY gs_read ON public.reservation FOR SELECT TO authenticated USING(user_id=gs_uid() OR gs_manager());
CREATE POLICY gs_read ON public.charging_session FOR SELECT TO authenticated USING(user_id=gs_uid() OR gs_manager());
CREATE POLICY gs_read ON public.fleet_org FOR SELECT TO authenticated USING(gs_manager());
CREATE POLICY gs_read ON public.fleet_mission FOR SELECT TO authenticated USING(gs_manager());
CREATE POLICY gs_read ON public.gs_audit FOR SELECT TO authenticated USING(gs_manager());
CREATE POLICY gs_read ON public.invoice FOR SELECT TO authenticated USING(EXISTS(SELECT FROM charging_session s WHERE s.session_id=invoice.session_id AND (s.user_id=gs_uid() OR gs_manager())));
CREATE POLICY gs_read ON public.payment FOR SELECT TO authenticated USING(EXISTS(SELECT FROM invoice i JOIN charging_session s ON s.session_id=i.session_id WHERE i.invoice_id=payment.invoice_id AND (s.user_id=gs_uid() OR gs_manager())));
REVOKE ALL ON public.v_station_availability,public.v_active_sessions,public.v_fleet_dashboard FROM PUBLIC,anon,authenticated;
-- A narrowly scoped computed load includes all users without exposing their records.
CREATE OR REPLACE FUNCTION public.gs_grid_load() RETURNS TABLE(substation_id integer,allocated_load_kw numeric,active_sessions bigint,simulated_sessions bigint) LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT sub.substation_id,coalesce(sum(s.allocated_kw),0),count(s.session_id),count(s.session_id) FILTER(WHERE s.meter_source='simulated')
 FROM substation sub LEFT JOIN charging_station st ON st.substation_id=sub.substation_id LEFT JOIN charger_bay b ON b.station_id=st.station_id
 LEFT JOIN charging_session s ON s.bay_id=b.bay_id AND s.status='active' WHERE auth.uid() IS NOT NULL GROUP BY sub.substation_id
$$;

-- Internal invoice calculation. Only the mutation RPC may invoke this function.
CREATE OR REPLACE FUNCTION public.gs_bill(sid integer) RETURNS public.invoice LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE s charging_session; i invoice; v vehicle; u app_user; b charger_bay; st charging_station; sub substation;
 energy numeric; idle numeric; fee numeric; discount numeric; tax numeric; net numeric;
BEGIN
 SELECT * INTO s FROM charging_session WHERE session_id=sid FOR UPDATE;
 SELECT * INTO i FROM invoice WHERE session_id=sid;
 IF FOUND THEN RETURN i; END IF;
 IF s.status NOT IN ('completed','failed') OR s.tariff_snapshot IS NULL THEN RAISE EXCEPTION 'Session is not eligible for an invoice'; END IF;
 energy=round(s.energy_delivered_kwh*(s.tariff_snapshot->>'base_rate_per_kwh')::numeric,2);
 idle=round(s.idle_minutes*(s.tariff_snapshot->>'idle_fee_per_min')::numeric,2);
 fee=(s.tariff_snapshot->>'service_fee')::numeric;
 discount=least((s.tariff_snapshot->>'discount_amount')::numeric,energy+idle+fee);
 net=energy+idle+fee-discount; tax=round(net*(s.tariff_snapshot->>'tax_pct')::numeric/100,2);
 SELECT * INTO v FROM vehicle WHERE vehicle_id=s.vehicle_id; SELECT * INTO u FROM app_user WHERE user_id=s.user_id;
 SELECT * INTO b FROM charger_bay WHERE bay_id=s.bay_id; SELECT * INTO st FROM charging_station WHERE station_id=b.station_id; SELECT * INTO sub FROM substation WHERE substation_id=st.substation_id;
 INSERT INTO invoice(session_id,invoice_number,currency,energy_charge,idle_penalty_charge,service_fee,discount_amount,tax_amount,status,snapshot)
 VALUES(sid,'GS-'||to_char(now(),'YYYY')||'-'||lpad(sid::text,8,'0'),s.tariff_snapshot->>'currency',energy,idle,fee,discount,tax,'pending',
 jsonb_build_object('customer',jsonb_build_object('name',u.full_name,'email',u.email,'phone',u.phone),'vehicle',jsonb_build_object('registration',v.license_plate,'make',v.make,'model',v.model),
 'station',st.station_name,'address',st.street_address||', '||st.city,'connector',b.plug_type||' / Bay '||b.bay_number,'substation',sub.name,'session',to_jsonb(s),'tariff',s.tariff_snapshot)) RETURNING * INTO i;
 RETURN i;
END $$;

-- Serialized critical sections protect capacity, booking, metering and settlement races.
CREATE OR REPLACE FUNCTION public.gs_mutate(action text, entity integer DEFAULT NULL, payload jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE uid integer; mgr boolean; v vehicle; b charger_bay; st charging_station; sub substation; s charging_session; r reservation; inv invoice; pay payment; tariff tariff_plan;
 result jsonb; sid integer; load numeric; reading numeric; elapsed integer; energy numeric; kw numeric; begin_at timestamptz; finish_at timestamptz; key uuid; owner_id integer;
BEGIN
 uid=gs_uid(); mgr=gs_manager(); IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(7042,1);
 IF action IN ('substation.save','station.save','bay.save','tariff.save','mission.create','session.start','session.meter','session.complete','session.fail','payment.refund') AND NOT mgr THEN RAISE EXCEPTION 'Manager access required' USING ERRCODE='42501'; END IF;
 IF action='profile.save' THEN
  IF length(trim(payload->>'full_name')) NOT BETWEEN 2 AND 100 OR length(coalesce(payload->>'phone',''))>25 THEN RAISE EXCEPTION 'Enter a name (2-100 characters) and a phone up to 25 characters'; END IF;
  UPDATE app_user SET full_name=trim(payload->>'full_name'),phone=coalesce(payload->>'phone','') WHERE user_id=uid RETURNING to_jsonb(app_user.*) INTO result;
 ELSIF action='vehicle.save' THEN
  IF entity IS NOT NULL THEN SELECT * INTO v FROM vehicle WHERE vehicle_id=entity FOR UPDATE; IF NOT FOUND OR (v.user_id<>uid AND NOT mgr) THEN RAISE EXCEPTION 'Vehicle not found' USING ERRCODE='42501'; END IF;
   IF v.archived_at IS NOT NULL THEN RAISE EXCEPTION 'Vehicle is archived'; END IF;
   IF EXISTS(SELECT FROM charging_session WHERE vehicle_id=entity AND status IN ('active','queued','scheduled')) OR EXISTS(SELECT FROM reservation WHERE vehicle_id=entity AND status='confirmed' AND upper(time_slot)>now()) THEN RAISE EXCEPTION 'Finish or cancel outstanding sessions and reservations before editing'; END IF;
  END IF;
  IF coalesce(payload->>'license_plate','') !~ '^[A-Za-z0-9][A-Za-z0-9 -]{2,19}$' OR length(trim(coalesce(payload->>'make','')))<1 OR length(trim(coalesce(payload->>'model','')))<1 THEN RAISE EXCEPTION 'Registration (3-20 letters/digits/spaces/hyphens), make and model are required'; END IF;
  IF jsonb_typeof(payload->'connector_types') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Select supported connectors'; END IF;
  IF jsonb_array_length(payload->'connector_types')=0 OR EXISTS(SELECT FROM jsonb_array_elements_text(payload->'connector_types') x WHERE x NOT IN ('CCS2','Type2','CHAdeMO','NACS')) THEN RAISE EXCEPTION 'Unsupported connector selection'; END IF;
  IF entity IS NULL THEN INSERT INTO vehicle(user_id,vin,license_plate,battery_capacity_kwh,max_charge_rate_kw,current_soc_pct,ownership_type) VALUES(uid,null,upper(trim(payload->>'license_plate')),null,null,0,'PERSONAL') RETURNING vehicle_id INTO entity; END IF;
  UPDATE vehicle SET license_plate=upper(trim(payload->>'license_plate')),make=left(payload->>'make',80),model=left(payload->>'model',80),vehicle_type=left(coalesce(payload->>'vehicle_type','car'),30),
   connector_types=ARRAY(SELECT jsonb_array_elements_text(payload->'connector_types')),battery_capacity_kwh=nullif(payload->>'battery_capacity_kwh','')::numeric,max_charge_rate_kw=nullif(payload->>'max_charge_rate_kw','')::numeric WHERE vehicle_id=entity RETURNING to_jsonb(vehicle.*) INTO result;
 ELSIF action='vehicle.archive' THEN
  SELECT * INTO v FROM vehicle WHERE vehicle_id=entity FOR UPDATE; IF NOT FOUND OR (v.user_id<>uid AND NOT mgr) THEN RAISE EXCEPTION 'Vehicle not found' USING ERRCODE='42501'; END IF;
  IF EXISTS(SELECT FROM reservation WHERE vehicle_id=entity AND status='confirmed' AND upper(time_slot)>now()) OR EXISTS(SELECT FROM charging_session WHERE vehicle_id=entity AND status IN ('active','queued','scheduled')) OR EXISTS(SELECT FROM fleet_mission WHERE vehicle_id=entity AND status='scheduled') THEN RAISE EXCEPTION 'Cancel open bookings, sessions and missions before removing this vehicle'; END IF;
  UPDATE vehicle SET archived_at=now() WHERE vehicle_id=entity RETURNING to_jsonb(vehicle.*) INTO result;
 ELSIF action='substation.save' THEN
  IF length(trim(coalesce(payload->>'name','')))<2 OR coalesce(payload->>'code','') !~ '^[A-Za-z0-9_-]{2,30}$' THEN RAISE EXCEPTION 'Substation name and a valid code are required'; END IF;
  IF entity IS NOT NULL THEN SELECT * INTO sub FROM substation WHERE substation_id=entity FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'Substation not found'; END IF; END IF;
  SELECT coalesce(sum(cs.allocated_kw),0) INTO load FROM charging_session cs JOIN charger_bay cb ON cb.bay_id=cs.bay_id JOIN charging_station c ON c.station_id=cb.station_id WHERE c.substation_id=entity AND cs.status='active';
  IF load+coalesce((payload->>'base_load_kw')::numeric,0)>(payload->>'max_grid_capacity_kw')::numeric*(payload->>'capacity_limit_pct')::numeric/100 THEN RAISE EXCEPTION 'Capacity limit is below the current allocated load'; END IF;
  IF load>0 AND payload->>'operational_status'<>'operational' THEN RAISE EXCEPTION 'Stop active sessions before taking the substation offline'; END IF;
  IF entity IS NULL THEN INSERT INTO substation(name,code,region_code,max_grid_capacity_kw) VALUES(payload->>'name',upper(payload->>'code'),coalesce(payload->>'region_code',''),(payload->>'max_grid_capacity_kw')::numeric) RETURNING substation_id INTO entity; END IF;
  UPDATE substation SET name=payload->>'name',code=upper(payload->>'code'),location=coalesce(payload->>'location',''),region_code=coalesce(payload->>'region_code',''),max_grid_capacity_kw=(payload->>'max_grid_capacity_kw')::numeric,
   base_load_kw=(payload->>'base_load_kw')::numeric,capacity_limit_pct=(payload->>'capacity_limit_pct')::numeric,operational_status=payload->>'operational_status',load_source=payload->>'load_source',monitored_at=now(),constraints_note=coalesce(payload->>'constraints_note','') WHERE substation_id=entity RETURNING to_jsonb(substation.*) INTO result;
 ELSIF action='station.save' THEN
  IF length(trim(coalesce(payload->>'station_name','')))<2 THEN RAISE EXCEPTION 'Station name is required'; END IF;
  IF NOT EXISTS(SELECT FROM substation WHERE substation_id=(payload->>'substation_id')::integer) THEN RAISE EXCEPTION 'Choose a registered substation'; END IF;
  IF NOT EXISTS(SELECT FROM pg_timezone_names WHERE name=payload->>'timezone') THEN RAISE EXCEPTION 'Choose a valid IANA timezone'; END IF;
  IF payload->>'status' NOT IN ('ACTIVE','MAINTENANCE','OFFLINE') THEN RAISE EXCEPTION 'Invalid station status'; END IF;
  IF entity IS NOT NULL AND EXISTS(SELECT FROM charging_session cs JOIN charger_bay cb ON cb.bay_id=cs.bay_id WHERE cb.station_id=entity AND cs.status IN ('active','queued','scheduled')) THEN RAISE EXCEPTION 'Resolve open sessions before changing a station assignment'; END IF;
  IF entity IS NULL THEN INSERT INTO charging_station(substation_id,station_name,street_address,city) VALUES((payload->>'substation_id')::integer,payload->>'station_name',payload->>'street_address',payload->>'city') RETURNING station_id INTO entity; END IF;
  UPDATE charging_station SET substation_id=(payload->>'substation_id')::integer,station_name=payload->>'station_name',street_address=payload->>'street_address',city=payload->>'city',status=payload->>'status',timezone=payload->>'timezone' WHERE station_id=entity RETURNING to_jsonb(charging_station.*) INTO result;
 ELSIF action='bay.save' THEN
  IF (payload->>'max_kw_output')::numeric<=0 OR (payload->>'bay_number')::integer<1 OR payload->>'plug_type' NOT IN ('CCS2','Type2','CHAdeMO','NACS') THEN RAISE EXCEPTION 'Choose a valid connector, bay number and positive power'; END IF;
  IF entity IS NOT NULL AND (EXISTS(SELECT FROM charging_session WHERE bay_id=entity AND status IN ('active','queued','scheduled')) OR EXISTS(SELECT FROM reservation WHERE bay_id=entity AND status='confirmed' AND upper(time_slot)>now())) THEN RAISE EXCEPTION 'Resolve open bookings and sessions before editing a connector'; END IF;
  IF EXISTS(SELECT FROM charger_bay WHERE station_id=(payload->>'station_id')::integer AND bay_number=(payload->>'bay_number')::integer AND bay_id<>coalesce(entity,0)) THEN RAISE EXCEPTION 'Bay number already exists at this station'; END IF;
  IF entity IS NULL THEN INSERT INTO charger_bay(station_id,bay_number,plug_type,max_kw_output) VALUES((payload->>'station_id')::integer,(payload->>'bay_number')::integer,payload->>'plug_type',(payload->>'max_kw_output')::numeric) RETURNING bay_id INTO entity; END IF;
  UPDATE charger_bay SET station_id=(payload->>'station_id')::integer,bay_number=(payload->>'bay_number')::integer,plug_type=payload->>'plug_type',max_kw_output=(payload->>'max_kw_output')::numeric,is_operational=(payload->>'is_operational')::boolean WHERE bay_id=entity RETURNING to_jsonb(charger_bay.*) INTO result;
 ELSIF action='tariff.save' THEN
  IF length(trim(coalesce(payload->>'plan_name','')))<2 THEN RAISE EXCEPTION 'Tariff name is required'; END IF;
  IF EXISTS(SELECT FROM tariff_plan WHERE station_id=(payload->>'station_id')::integer AND active AND tariff_id<>coalesce(entity,0) AND start_hour<(payload->>'end_hour')::integer AND end_hour>(payload->>'start_hour')::integer) AND coalesce((payload->>'active')::boolean,true) THEN RAISE EXCEPTION 'An active tariff already covers these hours'; END IF;
  IF entity IS NULL THEN INSERT INTO tariff_plan(station_id,plan_name,start_hour,end_hour,base_rate_per_kwh) VALUES((payload->>'station_id')::integer,payload->>'plan_name',(payload->>'start_hour')::integer,(payload->>'end_hour')::integer,(payload->>'base_rate_per_kwh')::numeric) RETURNING tariff_id INTO entity; END IF;
  UPDATE tariff_plan SET station_id=(payload->>'station_id')::integer,plan_name=payload->>'plan_name',start_hour=(payload->>'start_hour')::integer,end_hour=(payload->>'end_hour')::integer,base_rate_per_kwh=(payload->>'base_rate_per_kwh')::numeric,idle_fee_per_min=(payload->>'idle_fee_per_min')::numeric,currency=upper(payload->>'currency'),tax_pct=(payload->>'tax_pct')::numeric,service_fee=(payload->>'service_fee')::numeric,discount_amount=(payload->>'discount_amount')::numeric,active=(payload->>'active')::boolean WHERE tariff_id=entity RETURNING to_jsonb(tariff_plan.*) INTO result;
 ELSIF action IN ('reservation.create','session.create') THEN
  SELECT * INTO v FROM vehicle WHERE vehicle_id=(payload->>'vehicle_id')::integer FOR UPDATE;
  IF NOT FOUND OR v.archived_at IS NOT NULL OR (v.user_id<>uid AND NOT mgr) THEN RAISE EXCEPTION 'Vehicle not found' USING ERRCODE='42501'; END IF;
  SELECT * INTO b FROM charger_bay WHERE bay_id=(payload->>'bay_id')::integer; IF NOT FOUND OR NOT b.is_operational THEN RAISE EXCEPTION 'Connector is unavailable'; END IF;
  SELECT * INTO st FROM charging_station WHERE station_id=b.station_id; SELECT * INTO sub FROM substation WHERE substation_id=st.substation_id;
  IF st.status<>'ACTIVE' OR sub.operational_status<>'operational' THEN RAISE EXCEPTION 'Station or substation is unavailable'; END IF;
  IF NOT b.plug_type=ANY(v.connector_types) THEN RAISE EXCEPTION 'Vehicle does not support this connector. Update verified vehicle specifications first.'; END IF;
  IF action='reservation.create' THEN
   begin_at=(payload->>'start_time')::timestamptz; finish_at=(payload->>'end_time')::timestamptz;
   IF begin_at IS NULL OR finish_at IS NULL OR begin_at<now() OR finish_at<=begin_at OR finish_at-begin_at>interval '24 hours' THEN RAISE EXCEPTION 'Choose a future interval of no more than 24 hours'; END IF;
   IF EXISTS(SELECT FROM reservation WHERE vehicle_id=v.vehicle_id AND status='confirmed' AND time_slot && tstzrange(begin_at,finish_at,'[)')) THEN RAISE EXCEPTION 'Vehicle already has an overlapping reservation'; END IF;
   INSERT INTO reservation(bay_id,vehicle_id,user_id,time_slot) VALUES(b.bay_id,v.vehicle_id,v.user_id,tstzrange(begin_at,finish_at,'[)')) RETURNING to_jsonb(reservation.*) INTO result;
  ELSE
   IF v.max_charge_rate_kw IS NULL THEN RAISE EXCEPTION 'Set the vehicle maximum charging power before requesting a session'; END IF;
   IF payload->>'meter_source' NOT IN ('simulated','manual') OR payload->>'meter_source' IS NULL THEN RAISE EXCEPTION 'Select simulated or manually recorded metering'; END IF;
   sid=nullif(payload->>'reservation_id','')::integer;
   IF sid IS NOT NULL THEN SELECT * INTO r FROM reservation WHERE reservation_id=sid FOR UPDATE; IF NOT FOUND OR r.user_id<>v.user_id OR r.vehicle_id<>v.vehicle_id OR r.bay_id<>b.bay_id OR r.status<>'confirmed' OR upper(r.time_slot)<=now() THEN RAISE EXCEPTION 'Reservation does not match this vehicle, owner and bay, or has expired'; END IF; END IF;
   begin_at=coalesce(nullif(payload->>'scheduled_at','')::timestamptz,CASE WHEN sid IS NOT NULL THEN lower(r.time_slot) ELSE now() END);
   INSERT INTO charging_session(bay_id,vehicle_id,user_id,reservation_id,allocated_kw,status,scheduled_at,meter_source) VALUES(b.bay_id,v.vehicle_id,v.user_id,sid,0,CASE WHEN begin_at>now() THEN 'scheduled' ELSE 'queued' END,begin_at,payload->>'meter_source') RETURNING to_jsonb(charging_session.*) INTO result;
  END IF;
 ELSIF action='reservation.cancel' THEN
  SELECT * INTO r FROM reservation WHERE reservation_id=entity FOR UPDATE; IF NOT FOUND OR (r.user_id<>uid AND NOT mgr) THEN RAISE EXCEPTION 'Reservation not found' USING ERRCODE='42501'; END IF;
  IF r.status<>'confirmed' OR EXISTS(SELECT FROM charging_session WHERE reservation_id=entity AND status='active') THEN RAISE EXCEPTION 'Only confirmed reservations without active charging can be cancelled'; END IF;
  UPDATE charging_session SET status='cancelled',cancellation_reason='Reservation cancelled' WHERE reservation_id=entity AND status IN ('queued','scheduled');
  UPDATE reservation SET status='cancelled' WHERE reservation_id=entity RETURNING to_jsonb(reservation.*) INTO result;
 ELSIF action LIKE 'session.%' THEN
  SELECT * INTO s FROM charging_session WHERE session_id=entity FOR UPDATE;
  IF NOT FOUND OR (s.user_id<>uid AND NOT mgr) THEN RAISE EXCEPTION 'Session not found' USING ERRCODE='42501'; END IF;
  SELECT * INTO b FROM charger_bay WHERE bay_id=s.bay_id; SELECT * INTO st FROM charging_station WHERE station_id=b.station_id; SELECT * INTO sub FROM substation WHERE substation_id=st.substation_id;
  SELECT * INTO v FROM vehicle WHERE vehicle_id=s.vehicle_id;
  IF action='session.start' THEN
   IF s.status NOT IN ('queued','scheduled') OR s.scheduled_at>now() THEN RAISE EXCEPTION 'Session is not ready to start'; END IF;
   IF NOT b.is_operational OR st.status<>'ACTIVE' OR sub.operational_status<>'operational' OR v.archived_at IS NOT NULL OR NOT b.plug_type=ANY(v.connector_types) THEN RAISE EXCEPTION 'Station, vehicle or connector is unavailable or incompatible'; END IF;
   IF EXISTS(SELECT FROM reservation WHERE bay_id=b.bay_id AND status='confirmed' AND time_slot @> now() AND reservation_id<>coalesce(s.reservation_id,0)) THEN RAISE EXCEPTION 'Bay is reserved for another session'; END IF;
   IF s.reservation_id IS NOT NULL AND NOT EXISTS(SELECT FROM reservation WHERE reservation_id=s.reservation_id AND status='confirmed' AND time_slot @> now()) THEN RAISE EXCEPTION 'Start within the confirmed reservation window'; END IF;
   SELECT coalesce(sum(cs.allocated_kw),0) INTO load FROM charging_session cs JOIN charger_bay cb ON cb.bay_id=cs.bay_id JOIN charging_station c ON c.station_id=cb.station_id WHERE c.substation_id=sub.substation_id AND cs.status='active';
   kw=least(b.max_kw_output,v.max_charge_rate_kw,sub.max_grid_capacity_kw*sub.capacity_limit_pct/100-sub.base_load_kw-load);
   IF kw<0.1 OR v.max_charge_rate_kw IS NULL THEN RAISE EXCEPTION 'Insufficient grid capacity; keep this session queued'; END IF;
   SELECT * INTO tariff FROM tariff_plan WHERE station_id=st.station_id AND active AND start_hour<=extract(hour FROM now() AT TIME ZONE st.timezone) AND end_hour>extract(hour FROM now() AT TIME ZONE st.timezone) ORDER BY tariff_id LIMIT 1;
   IF NOT FOUND THEN RAISE EXCEPTION 'Configure an applicable tariff before starting'; END IF;
   reading=(payload->>'initial_meter_kwh')::numeric; IF reading IS NULL OR reading<0 THEN RAISE EXCEPTION 'Enter a non-negative initial meter reading'; END IF;
   reading=round(reading,3);
   UPDATE charging_session SET status='active',start_time=now(),allocated_kw=trunc(kw,2),initial_meter_kwh=reading,final_meter_kwh=reading,tariff_snapshot=to_jsonb(tariff),meter_updated_at=now() WHERE session_id=entity RETURNING * INTO s;
  ELSIF action='session.meter' THEN
   IF s.status<>'active' THEN RAISE EXCEPTION 'Only active sessions accept readings'; END IF;
   reading=(payload->>'final_meter_kwh')::numeric; elapsed=CASE WHEN s.meter_source='simulated' THEN (payload->>'simulation_elapsed_seconds')::integer ELSE floor(extract(epoch FROM now()-s.start_time))::integer END;
   IF reading IS NULL OR s.initial_meter_kwh IS NULL OR reading<s.final_meter_kwh OR elapsed IS NULL OR elapsed<s.simulation_elapsed_seconds OR elapsed<0 OR elapsed>604800 THEN RAISE EXCEPTION 'Meter and elapsed time must be non-negative and monotonic (maximum 7 days)'; END IF;
   reading=round(reading,3); energy=reading-s.initial_meter_kwh;
   IF energy>s.allocated_kw*elapsed/3600+0.001 THEN RAISE EXCEPTION 'Energy exceeds allocated power over the recorded duration'; END IF;
   IF v.battery_capacity_kwh IS NOT NULL AND energy>v.battery_capacity_kwh THEN RAISE EXCEPTION 'Energy exceeds the registered battery capacity'; END IF;
   UPDATE charging_session SET final_meter_kwh=reading,energy_delivered_kwh=energy,simulation_elapsed_seconds=CASE WHEN meter_source='simulated' THEN elapsed ELSE 0 END,meter_updated_at=now() WHERE session_id=entity RETURNING * INTO s;
  ELSIF action IN ('session.complete','session.fail') THEN
   IF s.status<>'active' THEN RAISE EXCEPTION 'Only active sessions can be completed or failed'; END IF;
   IF s.tariff_snapshot IS NULL OR s.initial_meter_kwh IS NULL THEN RAISE EXCEPTION 'Legacy session requires audited migration before billing'; END IF;
   IF action='session.fail' AND length(trim(coalesce(payload->>'reason','')))<3 THEN RAISE EXCEPTION 'Provide a failure reason'; END IF;
   elapsed=CASE WHEN s.meter_source='simulated' THEN s.simulation_elapsed_seconds ELSE floor(extract(epoch FROM now()-s.start_time))::integer END;
   IF coalesce((payload->>'idle_minutes')::integer,0)<0 OR coalesce((payload->>'idle_minutes')::integer,0)>elapsed/60 THEN RAISE EXCEPTION 'Idle minutes cannot exceed the recorded duration'; END IF;
   IF s.energy_delivered_kwh>s.allocated_kw*(elapsed-coalesce((payload->>'idle_minutes')::integer,0)*60)/3600+0.001 THEN RAISE EXCEPTION 'Idle duration leaves insufficient charging time for the recorded energy'; END IF;
   UPDATE charging_session SET status=CASE WHEN action='session.fail' THEN 'failed' ELSE 'completed' END,end_time=CASE WHEN meter_source='simulated' THEN start_time+make_interval(secs=>simulation_elapsed_seconds) ELSE now() END,idle_minutes=coalesce((payload->>'idle_minutes')::integer,0),failure_reason=CASE WHEN action='session.fail' THEN left(payload->>'reason',1000) ELSE NULL END WHERE session_id=entity RETURNING * INTO s;
   IF action='session.complete' OR s.energy_delivered_kwh>0 THEN inv=gs_bill(entity); END IF;
   UPDATE reservation SET status='completed' WHERE reservation_id=s.reservation_id;
  ELSIF action='session.cancel' THEN
   IF s.status NOT IN ('scheduled','queued') THEN RAISE EXCEPTION 'Only queued or scheduled sessions can be cancelled'; END IF;
   IF length(trim(coalesce(payload->>'reason','')))<3 THEN RAISE EXCEPTION 'Provide a cancellation reason'; END IF;
   UPDATE charging_session SET status='cancelled',cancellation_reason=left(payload->>'reason',1000) WHERE session_id=entity RETURNING * INTO s;
   UPDATE reservation SET status='cancelled' WHERE reservation_id=s.reservation_id;
  ELSE RAISE EXCEPTION 'Unknown session action'; END IF;
  result=to_jsonb(s);
 ELSIF action LIKE 'payment.%' THEN
  IF NOT (SELECT test_payments_enabled FROM gs_settings WHERE id) THEN RAISE EXCEPTION 'Test payments are disabled. No production gateway is configured.'; END IF;
  IF action='payment.begin' THEN
   SELECT * INTO inv FROM invoice WHERE invoice_id=entity FOR UPDATE;
  ELSE
   SELECT * INTO pay FROM payment WHERE payment_id=entity FOR UPDATE; IF NOT FOUND OR NOT pay.is_test THEN RAISE EXCEPTION 'Test transaction not found'; END IF;
   SELECT * INTO inv FROM invoice WHERE invoice_id=pay.invoice_id FOR UPDATE;
  END IF;
  IF inv.invoice_id IS NULL THEN RAISE EXCEPTION 'Invoice not found'; END IF;
  SELECT * INTO s FROM charging_session WHERE session_id=inv.session_id;
  IF s.user_id<>uid AND NOT mgr THEN RAISE EXCEPTION 'Invoice not found' USING ERRCODE='42501'; END IF;
  IF action='payment.begin' THEN
   key=(payload->>'idempotency_key')::uuid; IF key IS NULL THEN RAISE EXCEPTION 'Idempotency key required'; END IF;
   SELECT * INTO pay FROM payment WHERE idempotency_key=key;
   IF FOUND THEN IF pay.invoice_id<>inv.invoice_id THEN RAISE EXCEPTION 'Idempotency key belongs to another invoice'; END IF; RETURN to_jsonb(pay); END IF;
   IF lower(inv.status) IN ('paid','refunded') THEN RAISE EXCEPTION 'Invoice is already paid or refunded'; END IF;
   SELECT * INTO pay FROM payment WHERE invoice_id=inv.invoice_id AND status='pending'; IF FOUND THEN RETURN to_jsonb(pay); END IF;
   INSERT INTO payment(invoice_id,payment_method,paid_amount,transaction_ref,status,is_test,currency,idempotency_key,settled_at)
    VALUES(inv.invoice_id,'test',inv.total_amount,'SIM-'||gen_random_uuid()::text,'pending',true,inv.currency,key,null) RETURNING * INTO pay;
  ELSIF action='payment.settle' THEN
   IF payload->>'outcome' NOT IN ('paid','failed') OR payload->>'outcome' IS NULL THEN RAISE EXCEPTION 'Choose a test outcome'; END IF;
   IF pay.status=payload->>'outcome' THEN RETURN to_jsonb(pay); END IF;
   IF pay.status<>'pending' THEN RAISE EXCEPTION 'This transaction is already finalized'; END IF;
   UPDATE payment SET status=payload->>'outcome',settled_at=CASE WHEN payload->>'outcome'='paid' THEN now() ELSE null END,failure_reason=CASE WHEN payload->>'outcome'='failed' THEN 'Simulated payment decline' ELSE null END,updated_at=now() WHERE payment_id=entity RETURNING * INTO pay;
   UPDATE invoice SET status=CASE WHEN pay.status='paid' THEN 'paid' ELSE 'pending' END,paid_at=pay.settled_at WHERE invoice_id=inv.invoice_id;
  ELSIF action='payment.refund' THEN
   IF pay.status='refunded' THEN RETURN to_jsonb(pay); END IF;
   IF pay.status<>'paid' THEN RAISE EXCEPTION 'Only paid test transactions can be refunded'; END IF;
   UPDATE payment SET status='refunded',refunded_at=now(),updated_at=now() WHERE payment_id=entity RETURNING * INTO pay;
   UPDATE invoice SET status='refunded' WHERE invoice_id=inv.invoice_id;
  ELSE RAISE EXCEPTION 'Unknown payment action'; END IF;
  result=to_jsonb(pay);
 ELSIF action='mission.create' THEN
  SELECT * INTO v FROM vehicle WHERE vehicle_id=(payload->>'vehicle_id')::integer AND archived_at IS NULL;
  IF NOT FOUND OR v.org_id IS NULL OR v.org_id IS DISTINCT FROM (payload->>'fleet_org_id')::integer THEN RAISE EXCEPTION 'Vehicle must belong to the selected fleet organization'; END IF;
  IF (payload->>'departure_time')::timestamptz<=now() OR (payload->>'target_soc_pct')::numeric NOT BETWEEN 1 AND 100 OR (payload->>'priority_level')::integer<1 THEN RAISE EXCEPTION 'Enter a future departure, charge target 1-100 and positive priority'; END IF;
  INSERT INTO fleet_mission(vehicle_id,fleet_org_id,mission_label,departure_time,target_soc_pct,priority_level) VALUES(v.vehicle_id,v.org_id,left(payload->>'mission_label',150),(payload->>'departure_time')::timestamptz,(payload->>'target_soc_pct')::numeric,(payload->>'priority_level')::integer) RETURNING to_jsonb(fleet_mission.*) INTO result;
 ELSE RAISE EXCEPTION 'Unknown operation'; END IF;
 IF result IS NULL THEN RAISE EXCEPTION 'Record not found'; END IF;
 INSERT INTO gs_audit(actor,action,entity_id) VALUES(auth.uid(),action,entity);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.gs_bill(integer),public.gs_new_auth_user(),public.gs_mutate(text,integer,jsonb),public.gs_uid(),public.gs_manager(),public.gs_grid_load() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.gs_mutate(text,integer,jsonb),public.gs_uid(),public.gs_manager(),public.gs_grid_load() TO authenticated;
INSERT INTO public.gs_migration(version) VALUES('20261019');
COMMIT;
