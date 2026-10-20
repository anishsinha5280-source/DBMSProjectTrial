// Rebuild the browser sandbox from the project's authoritative example SQL.
const {PGlite}=require('@electric-sql/pglite');const {btree_gist}=require('@electric-sql/pglite/contrib/btree_gist');
const fs=require('node:fs'),path=require('node:path');const root=path.join(__dirname,'..');
async function build(){
 const db=new PGlite({extensions:{btree_gist}});
 try{
  await db.exec(fs.readFileSync(path.join(root,'sql/supabase_schema.sql'),'utf8'));
  const generated_at=new Date().toISOString(),stamp=generated_at,ago=h=>new Date(Date.parse(stamp)+h*3600000).toISOString();
  const tableNames={substations:'substation',stations:'charging_station',bays:'charger_bay',vehicles:'vehicle',customers:'app_user',organizations:'fleet_org',missions:'fleet_mission',reservations:'reservation'};
  const seed={generated_at,demo_account_ids:{manager:1,customer:6},source:'sql/supabase_schema.sql',source_note:'Original SQL example rows plus explicitly simulated demo tariffs, connector specifications, session and billing examples.'};
  for(const [name,table]of Object.entries(tableNames))seed[name]=(await db.query(`SELECT * FROM ${table}`)).rows;
  seed.substations.forEach(s=>Object.assign(s,{code:'GRID-'+String(s.substation_id).padStart(2,'0'),location:s.region_code,base_load_kw:0,capacity_limit_pct:90,operational_status:'operational',load_source:'simulated',monitored_at:stamp,constraints_note:'Demo allocation over the original example grid capacity.'}));
  seed.stations.forEach(s=>s.timezone='Asia/Kolkata');
  seed.customers.forEach(u=>{u.role=['ADMIN','FLEET_MANAGER'].includes(u.user_role)?'manager':'customer';u.source_email=u.email;});
  seed.vehicles.forEach(v=>Object.assign(v,{make:'Demo EV',model:(v.ownership_type==='FLEET'?'Fleet vehicle ':'Personal vehicle ')+v.vehicle_id,vehicle_type:Number(v.battery_capacity_kwh)>=300?'truck':'car',connector_types:v.vehicle_id===6?['CCS2','CHAdeMO']:['CCS2','Type2'],archived_at:null,demo_specs:true}));
  seed.reservations.forEach(r=>{const parts=r.time_slot.replace(/^[[(]|[)\]]$/g,'').split(',').map(s=>new Date(s.replaceAll('"','')).toISOString());r.time_slot=`[${parts[0]},${parts[1]})`;});
  seed.tariffs=seed.stations.map(s=>({tariff_id:s.station_id,station_id:s.station_id,plan_name:'Demo all-day tariff / '+s.station_name,start_hour:0,end_hour:24,base_rate_per_kwh:10,idle_fee_per_min:1,currency:'INR',tax_pct:10,service_fee:5,discount_amount:2,active:true,demo_pricing:true}));
  seed.sessions=[];seed.invoices=[];seed.payments=[];
  for(const [index,reservation]of seed.reservations.filter(r=>r.status==='completed').entries()){
   const vehicle=seed.vehicles.find(v=>v.vehicle_id===reservation.vehicle_id),bay=seed.bays.find(b=>b.bay_id===reservation.bay_id),station=seed.stations.find(s=>s.station_id===bay.station_id),customer=seed.customers.find(u=>u.user_id===reservation.user_id),t=seed.tariffs.find(t=>t.station_id===station.station_id),times=reservation.time_slot.slice(1,-1).split(','),energy=index?20:10;
   const session={session_id:101+index,user_id:vehicle.user_id,vehicle_id:vehicle.vehicle_id,bay_id:bay.bay_id,reservation_id:reservation.reservation_id,status:'completed',meter_source:'simulated',start_time:times[0],end_time:times[1],scheduled_at:times[0],created_at:times[0],updated_at:times[1],initial_meter_kwh:100,final_meter_kwh:100+energy,energy_delivered_kwh:energy,allocated_kw:Number(vehicle.max_charge_rate_kw),simulation_elapsed_seconds:(Date.parse(times[1])-Date.parse(times[0]))/1000,idle_minutes:0,tariff_snapshot:t};
   seed.sessions.push(session);const amount=energy*10,net=amount+5-2,tax=Math.round(net*10)/100;
   seed.invoices.push({invoice_id:201+index,session_id:session.session_id,invoice_number:'DEMO-GS-'+String(session.session_id).padStart(8,'0'),currency:'INR',energy_charge:amount,idle_penalty_charge:0,service_fee:5,discount_amount:2,tax_amount:tax,total_amount:Math.round((net+tax)*100)/100,status:index?'pending':'paid',created_at:times[1],paid_at:index?null:times[1],snapshot:{customer:{name:customer.full_name,email:customer.email,phone:customer.phone},vehicle:{registration:vehicle.license_plate,make:vehicle.make,model:vehicle.model},station:station.station_name,address:station.street_address+', '+station.city,substation:seed.substations.find(s=>s.substation_id===station.substation_id).name,connector:bay.plug_type+' / Bay '+bay.bay_number,session,tariff:t}});
   if(!index)seed.payments.push({payment_id:501,invoice_id:201,payment_method:'test',paid_amount:seed.invoices[0].total_amount,currency:'INR',transaction_ref:'SIM-DEMO-SEED-000501',status:'paid',is_test:true,created_at:times[1],settled_at:times[1]});
  }
  for(const [session_id,vehicle_id,bay_id,status]of [[103,6,6,'queued'],[104,10,11,'active'],[105,1,2,'queued']]){
   const v=seed.vehicles.find(v=>v.vehicle_id===vehicle_id),b=seed.bays.find(b=>b.bay_id===bay_id),t=seed.tariffs.find(t=>t.station_id===b.station_id),active=status==='active';
   seed.sessions.push({session_id,user_id:v.user_id,vehicle_id,bay_id,status,meter_source:'simulated',start_time:active?ago(-.25):null,end_time:null,scheduled_at:ago(-.25),created_at:ago(-.25),updated_at:stamp,reservation_id:null,allocated_kw:active?Math.min(Number(v.max_charge_rate_kw),Number(b.max_kw_output)):0,energy_delivered_kwh:active?2:0,simulation_elapsed_seconds:active?900:0,initial_meter_kwh:active?100:null,final_meter_kwh:active?102:null,idle_minutes:0,tariff_snapshot:active?t:null});
  }
  fs.writeFileSync(path.join(root,'frontend/demo-seed.js'),'// Generated from sql/supabase_schema.sql by scripts/build-demo-seed.cjs.\nwindow.GridSyncDemoSeed='+JSON.stringify(seed,null,2)+';\n');
  console.log(Object.fromEntries(Object.entries(seed).filter(([,v])=>Array.isArray(v)).map(([k,v])=>[k,v.length])));
 }finally{await db.close();}
}
build().catch(e=>{console.error(e);process.exitCode=1;});
