-- Apply after 20261019_secure_workflows.sql. Fake authorization precedes confirmation.
BEGIN;
DO $$ BEGIN
 IF EXISTS(SELECT FROM public.gs_migration WHERE version='20261020') THEN RAISE EXCEPTION 'Reservation checkout migration is already applied'; END IF;
END $$;
CREATE TABLE public.reservation_checkout (
 checkout_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 user_id integer NOT NULL REFERENCES public.app_user(user_id),
 vehicle_id integer NOT NULL REFERENCES public.vehicle(vehicle_id),
 bay_id integer NOT NULL REFERENCES public.charger_bay(bay_id),
 start_time timestamptz NOT NULL, end_time timestamptz NOT NULL CHECK(end_time>start_time),
 idempotency_key uuid NOT NULL UNIQUE,
 amount numeric(12,2) NOT NULL CHECK(amount>=0),currency text NOT NULL,
 quote jsonb NOT NULL,status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','authorized','failed')),
 reservation_id integer UNIQUE REFERENCES public.reservation(reservation_id),
 transaction_ref text NOT NULL UNIQUE DEFAULT ('SIM-RES-'||gen_random_uuid()::text),
 payment_method text NOT NULL DEFAULT 'test',failure_reason text,
 created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL DEFAULT (now()+interval '15 minutes'),authorized_at timestamptz
);
ALTER TABLE public.reservation_checkout ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.reservation_checkout FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.reservation_checkout TO authenticated;
CREATE POLICY gs_read ON public.reservation_checkout FOR SELECT TO authenticated USING(user_id=public.gs_uid() OR public.gs_manager());
CREATE TRIGGER trg_updated_at BEFORE UPDATE ON public.reservation_checkout FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER FUNCTION public.gs_mutate(text,integer,jsonb) RENAME TO gs_mutate_core;
REVOKE ALL ON FUNCTION public.gs_mutate_core(text,integer,jsonb) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.gs_reservation_checkout(action text,entity integer,payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE uid integer; mgr boolean; v vehicle; b charger_bay; st charging_station; sub substation; t tariff_plan; c reservation_checkout;
 start_at timestamptz; end_at timestamptz; key uuid; energy numeric; energy_charge numeric; discount numeric; net numeric; tax numeric; result jsonb; method text;
BEGIN
 uid=gs_uid();mgr=gs_manager();IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
 IF NOT(SELECT test_payments_enabled FROM gs_settings WHERE id) THEN RAISE EXCEPTION 'Enable test payments to use the simulated reservation checkout'; END IF;
 PERFORM pg_advisory_xact_lock(7042,1);
 IF action='begin' THEN
  key=(payload->>'idempotency_key')::uuid;IF key IS NULL THEN RAISE EXCEPTION 'Reservation checkout idempotency key is required'; END IF;
  start_at=(payload->>'start_time')::timestamptz;end_at=(payload->>'end_time')::timestamptz;
  SELECT * INTO c FROM reservation_checkout WHERE idempotency_key=key;
  IF FOUND THEN
   IF c.user_id<>uid AND NOT mgr THEN RAISE EXCEPTION 'Checkout not found' USING ERRCODE='42501'; END IF;
   IF c.vehicle_id IS DISTINCT FROM (payload->>'vehicle_id')::integer OR c.bay_id IS DISTINCT FROM (payload->>'bay_id')::integer OR c.start_time IS DISTINCT FROM start_at OR c.end_time IS DISTINCT FROM end_at THEN RAISE EXCEPTION 'Idempotency key belongs to different reservation details'; END IF;
   RETURN to_jsonb(c);
  END IF;
  SELECT * INTO v FROM vehicle WHERE vehicle_id=(payload->>'vehicle_id')::integer;
  IF NOT FOUND OR v.archived_at IS NOT NULL OR(v.user_id<>uid AND NOT mgr) THEN RAISE EXCEPTION 'Vehicle not found' USING ERRCODE='42501'; END IF;
  SELECT * INTO b FROM charger_bay WHERE bay_id=(payload->>'bay_id')::integer;
  IF NOT FOUND OR NOT b.is_operational OR NOT b.plug_type=ANY(v.connector_types) THEN RAISE EXCEPTION 'Connector unavailable or incompatible'; END IF;
  SELECT * INTO st FROM charging_station WHERE station_id=b.station_id;SELECT * INTO sub FROM substation WHERE substation_id=st.substation_id;
  IF st.status<>'ACTIVE' OR sub.operational_status<>'operational' THEN RAISE EXCEPTION 'Station or substation is unavailable'; END IF;
  IF start_at IS NULL OR end_at IS NULL OR start_at<=now() OR end_at<=start_at OR end_at-start_at>interval '24 hours' THEN RAISE EXCEPTION 'Choose a future reservation lasting up to 24 hours'; END IF;
  IF EXISTS(SELECT FROM reservation WHERE status='confirmed' AND (bay_id=b.bay_id OR vehicle_id=v.vehicle_id) AND time_slot && tstzrange(start_at,end_at,'[)')) THEN RAISE EXCEPTION 'Vehicle or bay already has an overlapping reservation'; END IF;
  IF v.max_charge_rate_kw IS NULL THEN RAISE EXCEPTION 'Set vehicle maximum charging power before reserving'; END IF;
  SELECT * INTO t FROM tariff_plan WHERE station_id=st.station_id AND active AND start_hour<=extract(hour FROM start_at AT TIME ZONE st.timezone) AND end_hour>extract(hour FROM start_at AT TIME ZONE st.timezone) ORDER BY tariff_id LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'Configure a tariff for the selected reservation time'; END IF;
  energy=round(least(least(v.max_charge_rate_kw,b.max_kw_output)*extract(epoch FROM end_at-start_at)/3600,coalesce(v.battery_capacity_kwh,99999999)),3);
  energy_charge=round(energy*t.base_rate_per_kwh,2);discount=least(t.discount_amount,energy_charge+t.service_fee);net=energy_charge+t.service_fee-discount;tax=round(net*t.tax_pct/100,2);
  INSERT INTO reservation_checkout(user_id,vehicle_id,bay_id,start_time,end_time,idempotency_key,amount,currency,quote)
   VALUES(v.user_id,v.vehicle_id,b.bay_id,start_at,end_at,key,net+tax,t.currency,jsonb_build_object('purpose','simulated_authorization','estimated_kwh',energy,'energy_charge',energy_charge,'service_fee',t.service_fee,'discount_amount',discount,'tax_amount',tax,'tariff',to_jsonb(t))) RETURNING * INTO c;
 ELSIF action='settle' THEN
  SELECT * INTO c FROM reservation_checkout WHERE checkout_id=entity FOR UPDATE;
  IF NOT FOUND OR(c.user_id<>uid AND NOT mgr) THEN RAISE EXCEPTION 'Checkout not found' USING ERRCODE='42501'; END IF;
  IF c.status='authorized' AND payload->>'outcome'='paid' THEN RETURN to_jsonb(c); END IF;
  IF c.status='failed' AND payload->>'outcome'='failed' THEN RETURN to_jsonb(c); END IF;
  IF c.status<>'pending' THEN RAISE EXCEPTION 'Checkout already finalized'; END IF;
  IF c.expires_at<=now() THEN RAISE EXCEPTION 'Checkout expired. Choose your reservation again.'; END IF;
  method=coalesce(payload->>'test_method','upi');IF method NOT IN ('upi','card','netbanking') THEN RAISE EXCEPTION 'Invalid test method'; END IF;
  IF payload->>'outcome'='paid' THEN
   result=gs_mutate_core('reservation.create',NULL,jsonb_build_object('vehicle_id',c.vehicle_id,'bay_id',c.bay_id,'start_time',c.start_time,'end_time',c.end_time));
   UPDATE reservation_checkout SET status='authorized',authorized_at=now(),reservation_id=(result->>'reservation_id')::integer,payment_method='test_'||method WHERE checkout_id=entity RETURNING * INTO c;
  ELSIF payload->>'outcome'='failed' THEN
   UPDATE reservation_checkout SET status='failed',failure_reason='Simulated reservation payment declined',payment_method='test_'||method WHERE checkout_id=entity RETURNING * INTO c;
  ELSE RAISE EXCEPTION 'Select paid or failed as the simulated outcome'; END IF;
 ELSE RAISE EXCEPTION 'Unknown reservation checkout action'; END IF;
 INSERT INTO gs_audit(actor,action,entity_id) VALUES(auth.uid(),'reservation.checkout.'||action,c.checkout_id);
 RETURN to_jsonb(c);
END $$;
CREATE FUNCTION public.gs_mutate(action text,entity integer DEFAULT NULL,payload jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF action='reservation.create' THEN RETURN gs_reservation_checkout('begin',NULL,payload);
 ELSIF action='reservation.checkout' THEN RETURN gs_reservation_checkout('settle',entity,payload);
 ELSE RETURN gs_mutate_core(action,entity,payload); END IF;
END $$;
REVOKE ALL ON FUNCTION public.gs_reservation_checkout(text,integer,jsonb),public.gs_mutate(text,integer,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.gs_mutate(text,integer,jsonb) TO authenticated;
INSERT INTO public.gs_migration(version) VALUES('20261020');
NOTIFY pgrst,'reload schema';
COMMIT;
