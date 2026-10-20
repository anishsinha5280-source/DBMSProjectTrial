'use strict';
// Read-only browser samples. No backend session or privileges are granted.
(()=>{
 const key='gridsync-demo-role',requested=new URLSearchParams(location.search).get('demo');
 if(['manager','customer'].includes(requested))sessionStorage.setItem(key,requested);
 const role=sessionStorage.getItem(key),ago=h=>new Date(Date.now()+h*3600000).toISOString();
 const customers=[{user_id:1,full_name:'Demo Customer',email:'customer@example.test',phone:'',role:'customer'},{user_id:2,full_name:'Demo Fleet Driver',email:'driver@example.test',phone:'',role:'customer'},{user_id:900,full_name:'Demo Administrator',email:'admin@example.test',phone:'',role:'manager'}];
 const vehicles=[{vehicle_id:1,user_id:1,license_plate:'KA-01-DE-1001',make:'Tata',model:'Nexon EV',vehicle_type:'car',battery_capacity_kwh:40.5,max_charge_rate_kw:50,connector_types:['CCS2','Type2'],org_id:1},{vehicle_id:2,user_id:2,license_plate:'KA-01-DE-2002',make:'Hyundai',model:'IONIQ 5',vehicle_type:'car',battery_capacity_kwh:72.6,max_charge_rate_kw:150,connector_types:['CCS2'],org_id:1}];
 const stations=[{station_id:1,substation_id:1,station_name:'The Green Quarter',street_address:'100 Feet Road, Indiranagar',city:'Bengaluru',status:'ACTIVE',timezone:'Asia/Kolkata'}];
 const bays=[{bay_id:1,station_id:1,bay_number:1,plug_type:'CCS2',max_kw_output:120,is_operational:true},{bay_id:2,station_id:1,bay_number:2,plug_type:'Type2',max_kw_output:22,is_operational:true}];
 const tariff={tariff_id:1,station_id:1,plan_name:'Sample day tariff',start_hour:0,end_hour:24,base_rate_per_kwh:10,idle_fee_per_min:1,currency:'INR',tax_pct:10,service_fee:5,discount_amount:2,active:true};
 const session={session_id:101,user_id:1,vehicle_id:1,bay_id:1,status:'completed',meter_source:'simulated',start_time:ago(-3),end_time:ago(-2),created_at:ago(-3),updated_at:ago(-2),initial_meter_kwh:100,final_meter_kwh:110,energy_delivered_kwh:10,allocated_kw:50,simulation_elapsed_seconds:3600,idle_minutes:0,tariff_snapshot:tariff};
 const data={vehicles,stations,bays,tariffs:[tariff],customers,substations:[{substation_id:1,name:'East Bengaluru Grid',code:'DEMO-EAST',location:'Bengaluru',region_code:'IN-KA-E',max_grid_capacity_kw:600,base_load_kw:80,capacity_limit_pct:90,operational_status:'operational',load_source:'simulated',monitored_at:ago(-1)}],sessions:[session,{...session,session_id:102,user_id:2,vehicle_id:2,status:'queued',start_time:null,end_time:null,energy_delivered_kwh:0,allocated_kw:0,tariff_snapshot:null}],reservations:[{reservation_id:401,user_id:1,vehicle_id:1,bay_id:2,time_slot:`[${ago(2)},${ago(3)})`,status:'confirmed'}],organizations:[{org_id:1,company_name:'Demo Mobility Fleet'}],missions:[{mission_id:301,vehicle_id:2,fleet_org_id:1,mission_label:'Sample morning dispatch',departure_time:ago(4),target_soc_pct:85,priority_level:1,status:'scheduled'}],'grid-load':[{substation_id:1,allocated_load_kw:0,active_sessions:0,simulated_sessions:0}],invoices:[{invoice_id:201,session_id:101,invoice_number:'DEMO-GS-000201',currency:'INR',energy_charge:100,idle_penalty_charge:0,service_fee:5,discount_amount:2,tax_amount:10.3,total_amount:113.3,status:'paid',created_at:ago(-2),paid_at:ago(-1.9),snapshot:{customer:{name:'Demo Customer',email:'customer@example.test'},vehicle:{registration:vehicles[0].license_plate,make:'Tata',model:'Nexon EV'},station:stations[0].station_name,address:stations[0].street_address,connector:'CCS2 / Bay 1',session,tariff}}],payments:[{payment_id:501,invoice_id:201,payment_method:'test',paid_amount:113.3,currency:'INR',transaction_ref:'SIM-DEMO-000501',status:'paid',is_test:true,created_at:ago(-1.9),settled_at:ago(-1.9)}]};
 window.GridSyncDemo={active:['manager','customer'].includes(role),role,async request(route,method='GET'){
  if(route==='/auth/logout'){sessionStorage.removeItem(key);return {signed_out:true};}
  if(method!=='GET')throw Error('Read-only demo: exit the demo and sign in with a real account to save changes.');
  if(route==='/me')return structuredClone(customers.find(u=>u.role===role));
  if(route==='/health')return {status:'demo',payment_mode:'test'};
  const resource=route.slice(1);if(role!=='manager'&&['customers','organizations','missions'].includes(resource))throw Error('Admin demo required.');
  let rows=data[resource];if(!rows)throw Error('This operation is unavailable in the read-only demo.');
  if(role==='customer'&&['vehicles','sessions','reservations'].includes(resource))rows=rows.filter(r=>r.user_id===1);
  return structuredClone(rows);
 }};
})();
