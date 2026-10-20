'use strict';
const { PDFDocument, rgb }=require('pdf-lib');
const fontkit=require('@pdf-lib/fontkit');
const fs=require('node:fs');
const path=require('node:path');
async function invoicePdf(invoice,payments,issuer,address){
 const doc=await PDFDocument.create();doc.registerFontkit(fontkit);
 const font=await doc.embedFont(fs.readFileSync(path.join(__dirname,'fonts','DejaVuSans.ttf')),{subset:true});
 const ink=rgb(.09,.15,.13),muted=rgb(.38,.44,.39),lime=rgb(.82,.95,.34),paper=rgb(.96,.96,.92);
 const W=595,H=842,M=44;let page,y;
 function newPage(){page=doc.addPage([W,H]);page.drawRectangle({x:0,y:0,width:W,height:H,color:paper});y=H-M;}
 function line(text,size=10,color=ink){
  const words=String(text??'').replace(/[\r\n]+/g,' ').split(' ');let row='';
  const write=t=>{if(y<65)newPage();page.drawText(t,{x:M,y,size,font,color});y-=size+7;};
  for(const word of words){if(font.widthOfTextAtSize(row+word,size)>W-2*M&&row){write(row);row='';}if(font.widthOfTextAtSize(word,size)>W-2*M){for(const c of word){if(font.widthOfTextAtSize(row+c,size)>W-2*M){write(row);row='';}row+=c;}row+=' ';}else row+=word+' ';}if(row)write(row.trim());
 }
 function gap(n=12){y-=n;}
 function pair(label,value){line(label.toUpperCase(),8,muted);line(value,10);gap(4);}
 const snap=invoice.snapshot,s=snap.session,t=snap.tariff;
 const money=n=>`${invoice.currency} ${Number(n).toFixed(2)}`;
 const date=v=>v?new Date(v).toISOString().replace('T',' ').slice(0,19)+' UTC':'Not recorded';
 newPage();page.drawRectangle({x:0,y:H-12,width:W,height:12,color:lime});
 line(issuer,25);if(address)line(address,9,muted);gap();line('CHARGING INVOICE',9,muted);line(invoice.invoice_number,19);gap();
 pair('Issued / payment status',`${date(invoice.created_at)} / ${invoice.status}`);
 const paid=payments.find(p=>p.status==='paid')||payments.find(p=>p.status==='refunded');
 if(paid?.is_test)line('TEST PAYMENT - no money was collected.',11,muted);
 if(s.meter_source==='simulated')line('SIMULATED CHARGING - synthetic meter readings and duration.',9,muted);
 else line(`Meter source: ${s.meter_source}. Not verified charger telemetry.`,9,muted);
 gap();pair('Customer',`${snap.customer.name} | ${snap.customer.email}`);
 pair('Vehicle',`${snap.vehicle.registration} | ${snap.vehicle.make} ${snap.vehicle.model}`);
 pair('Location',`${snap.station} | ${snap.address}`);pair('Connector / electrical supply',`${snap.connector} | ${snap.substation}`);
 pair('Session',`#${s.session_id} | ${date(s.start_time)} to ${date(s.end_time)}`);
 pair('Energy / meter readings',`${s.energy_delivered_kwh} kWh | ${s.initial_meter_kwh} to ${s.final_meter_kwh} kWh`);
 pair('Tariff',`${t.plan_name} | ${invoice.currency} ${Number(t.base_rate_per_kwh).toFixed(4)} / kWh | locked at session start`);
 pair('Idle tariff / duration',`${invoice.currency} ${Number(t.idle_fee_per_min).toFixed(4)} per minute | ${s.idle_minutes} idle minutes`);
 gap(3);
 const rows=[['Energy',invoice.energy_charge],['Idle charges',invoice.idle_penalty_charge],['Service fee',invoice.service_fee],['Discount',-Number(invoice.discount_amount)],[`Tax (${t.tax_pct}%)`,invoice.tax_amount],['TOTAL PAYABLE',invoice.total_amount]];
 for(const [label,value] of rows){if(y<90)newPage();if(label==='TOTAL PAYABLE'){gap(8);page.drawRectangle({x:M-8,y:y-8,width:W-2*M+16,height:29,color:lime});}page.drawText(label,{x:M,y,size:11,font,color:ink});const amount=money(value);page.drawText(amount,{x:W-M-font.widthOfTextAtSize(amount,11),y,size:11,font,color:ink});y-=26;}
 gap();if(paid){pair('Transaction reference',paid.transaction_ref);pair('Payment date / method',`${date(paid.settled_at)} / ${paid.payment_method}${paid.is_test?' (simulated)':''}`);if(paid.refunded_at)pair('Refunded',date(paid.refunded_at));}
 if(!address)line('Issuer billing details have not been configured. This is an operational invoice, not a configured tax-compliant invoice.',8,muted);
 doc.getPages().forEach((p,i)=>p.drawText(`GridSync | ${invoice.invoice_number} | Page ${i+1} of ${doc.getPageCount()}`,{x:M,y:30,size:8,font,color:muted}));
 doc.setTitle(invoice.invoice_number);doc.setAuthor(issuer);return doc.save();
}
module.exports={invoicePdf};
