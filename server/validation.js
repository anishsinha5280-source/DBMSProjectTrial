'use strict';
const required={
 'profile.save':['full_name'], 'vehicle.save':['license_plate','make','model','connector_types'],
 'substation.save':['name','code','max_grid_capacity_kw','capacity_limit_pct','base_load_kw','operational_status','load_source'],
 'station.save':['substation_id','station_name','street_address','city','status','timezone'],
 'bay.save':['station_id','bay_number','plug_type','max_kw_output','is_operational'],
 'tariff.save':['station_id','plan_name','start_hour','end_hour','base_rate_per_kwh','idle_fee_per_min','currency','tax_pct','service_fee','discount_amount','active'],
 'reservation.create':['vehicle_id','bay_id','start_time','end_time'], 'session.create':['vehicle_id','bay_id','meter_source'],
 'session.start':['initial_meter_kwh'], 'session.meter':['final_meter_kwh'], 'session.cancel':['reason'],'session.fail':['reason'],
 'payment.begin':['idempotency_key'],'payment.settle':['outcome'],'mission.create':['vehicle_id','fleet_org_id','mission_label','departure_time','target_soc_pct','priority_level']
};
function validateMutation(action,p){
 if(!p||typeof p!=='object'||Array.isArray(p))throw Error('Expected an object.');
 for(const k of required[action]||[])if(p[k]===undefined||p[k]===null||p[k]==='')throw Error(`${k.replaceAll('_',' ')} is required.`);
 for(const [k,v] of Object.entries(p)){
  if(typeof v==='string'&&v.length>2000)throw Error(`${k} is too long.`);
  if(k.endsWith('_id')&&v!==null&&v!==''&&(!Number.isSafeInteger(Number(v))||Number(v)<1))throw Error(`${k} must be a positive integer.`);
  if(['start_time','end_time','scheduled_at','departure_time'].includes(k)&&v&&Number.isNaN(Date.parse(v)))throw Error(`${k} must be a valid date.`);
  if(/(_kw|_kwh|_pct|_seconds|_minutes|_hour)$/.test(k)&&v!==null&&v!==''&&(!Number.isFinite(Number(v))||Number(v)<0))throw Error(`${k} must be a non-negative number.`);
 }
 if(action==='payment.begin'&&!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(p.idempotency_key))throw Error('Invalid payment idempotency key.');
 if(action==='session.create'&&!['simulated','manual'].includes(p.meter_source))throw Error('Choose a supported meter source.');
}
module.exports={validateMutation};
