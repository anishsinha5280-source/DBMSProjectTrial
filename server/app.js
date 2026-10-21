'use strict';
const express = require('express');
const path = require('node:path');
const { createClient } = require('@supabase/supabase-js');
const { invoicePdf } = require('./invoice-pdf');
const { validateMutation } = require('./validation');
const COOKIE = { access: 'gs_access', refresh: 'gs_refresh' };
const authOptions = { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false };
function createApp({ env = process.env, clientFactory = createClient } = {}) {
  const app = express();
  app.disable('x-powered-by');
  app.use(express.json({ limit: '32kb' }));
  app.use((req, res, next) => {
    res.set('X-Content-Type-Options', 'nosniff');
    res.set('Referrer-Policy', 'same-origin');
    res.set('X-Frame-Options', 'DENY');
    if (req.path.startsWith('/api/')) res.set('Cache-Control', 'private, no-store');
    // Same-origin app: JSON + a custom header blocks cross-site form and fetch CSRF.
    if (req.path.startsWith('/api/') && !['GET', 'HEAD', 'OPTIONS'].includes(req.method)) {
      if (req.get('X-GridSync-Request') !== '1' || !req.is('application/json')) return res.status(403).json({ error: 'Use the GridSync application to submit this request.' });
      const origin = req.get('origin');
      const allowed = [env.APP_ORIGIN, ...(env.ALLOWED_ORIGINS || '').split(','), `http://${req.get('host')}`, `https://${req.get('host')}`].filter(Boolean);
      if (origin && !allowed.includes(origin)) return res.status(403).json({ error: 'Request origin is not allowed.' });
    }
    next();
  });
  const client = token => clientFactory(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, { auth: authOptions, ...(token ? { global: { headers: { Authorization: `Bearer ${token}` } } } : {}) });
  const configured = () => Boolean(env.SUPABASE_URL && env.SUPABASE_ANON_KEY);
  const cookieOptions = { httpOnly: true, secure: env.NODE_ENV === 'production' || Boolean(env.VERCEL), sameSite: 'lax', path: '/' };
  const setSession = (res, session) => {
    res.cookie(COOKIE.access, session.access_token, { ...cookieOptions, maxAge: (session.expires_in || 3600) * 1000 });
    res.cookie(COOKIE.refresh, session.refresh_token, { ...cookieOptions, maxAge: 30 * 86400000 });
  };
  const clearSession = res => Object.values(COOKIE).forEach(k => res.clearCookie(k, cookieOptions));
  const cookies = req => Object.fromEntries((req.get('cookie') || '').split(';').map(p => { const at = p.indexOf('='); return at < 0 ? ['', ''] : [p.slice(0, at).trim(), decodeURIComponent(p.slice(at + 1))]; }));
  const fail = (res, error, fallback = 400) => res.status(error.code === '42501' ? 403 : ['23505','23P01'].includes(error.code) ? 409 : fallback).json({ error: ['23505','23P01'].includes(error.code) ? 'This record or time slot already exists. Refresh and choose another.' : error.message || 'Unable to complete the request.' });
  app.get('/api/health', (req, res) => res.json({ status: configured() ? 'ok' : 'setup_required', configured: configured(), payment_mode: env.ENABLE_TEST_PAYMENTS === 'true' ? 'test' : 'disabled', metering: 'simulated_or_manual' }));
  app.use('/api', (req, res, next) => configured() ? next() : res.status(503).json({ error: 'Set SUPABASE_URL and SUPABASE_ANON_KEY, then apply the database migration.' }));
  app.post('/api/auth/register', async (req, res) => {
    const { email, password, full_name } = req.body;
    if (typeof email !== 'string' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || typeof password !== 'string' || password.length < 12 || password.length > 128 || typeof full_name !== 'string' || full_name.trim().length < 2 || full_name.length > 100) return res.status(400).json({ error: 'Enter your name, a valid email and a password of 12–128 characters.' });
    const { data, error } = await client().auth.signUp({ email: email.trim(), password, options: { data: { full_name: full_name.trim() }, ...(env.APP_ORIGIN ? { emailRedirectTo: `${env.APP_ORIGIN}/login` } : {}) } });
    if (error) return fail(res, error);
    if (data.session) setSession(res, data.session);
    res.status(201).json({ signed_in: Boolean(data.session), message: data.session ? 'Account created.' : 'Check your email to confirm your account, then sign in.' });
  });
  app.post('/api/auth/login', async (req, res) => {
    if (typeof req.body.email !== 'string' || typeof req.body.password !== 'string' || req.body.password.length > 128) return res.status(400).json({ error: 'Email and password are required.' });
    const { data, error } = await client().auth.signInWithPassword({ email: req.body.email.trim(), password: req.body.password });
    if (error) return res.status(error.status === 429 ? 429 : 401).json({ error: error.status === 429 ? 'Too many attempts. Please try again later.' : 'Unable to sign in. Check your credentials and email confirmation.' });
    setSession(res, data.session);
    res.json({ signed_in: true });
  });
  app.post('/api/auth/refresh', async (req, res) => {
    const refresh_token = cookies(req)[COOKIE.refresh];
    if (!refresh_token) return res.status(401).json({ error: 'Please sign in.' });
    const { data, error } = await client().auth.refreshSession({ refresh_token });
    if (error || !data.session) { clearSession(res); return res.status(401).json({ error: 'Your session expired. Please sign in again.' }); }
    setSession(res, data.session); res.json({ refreshed: true });
  });
  app.post('/api/auth/logout', async (req, res) => {
    const c = cookies(req); const auth = client();
    if (c[COOKIE.access] && c[COOKIE.refresh]) {
      const { error } = await auth.auth.setSession({ access_token: c[COOKIE.access], refresh_token: c[COOKIE.refresh] });
      if (!error) await auth.auth.signOut({ scope: 'local' });
    }
    clearSession(res); res.json({ signed_out: true });
  });
  app.use('/api', async (req, res, next) => {
    const token = cookies(req)[COOKIE.access];
    if (!token) return res.status(401).json({ error: 'Please sign in.' });
    req.db = client(token); const { data, error } = await req.db.auth.getUser(token);
    if (error || !data.user) return res.status(401).json({ error: 'Your session expired. Please sign in again.' });
    const profile = await req.db.from('app_user').select('*').eq('auth_user_id', data.user.id).single();
    if (profile.error || !profile.data) return res.status(403).json({ error: 'Account profile is unavailable. Apply the GridSync migration or contact the administrator.' });
    req.profile = profile.data; next();
  });
  const manager = (req, res, next) => req.profile.role === 'manager' ? next() : res.status(403).json({ error: 'Manager access required.' });
  const read = async (req, res, table, order) => { const query = req.db.from(table).select('*'); const result = await (order ? query.order(order, { ascending: false }) : query); if (result.error) return fail(res, result.error, 500); res.json(result.data); };
  const mutation = action => async (req, res) => {
    try { validateMutation(action, req.body); } catch (e) { return res.status(400).json({ error: e.message }); }
    if ((action.startsWith('payment.') || ['reservation.create','reservation.checkout'].includes(action)) && env.ENABLE_TEST_PAYMENTS !== 'true') return res.status(409).json({ error: 'Test payments are disabled. Enable test payments to use simulated checkout; no production gateway is configured.' });
    const entity = req.params.id ? Number(req.params.id) : null;
    if (entity !== null && (!Number.isSafeInteger(entity) || entity < 1)) return res.status(400).json({ error: 'Invalid record ID.' });
    const { data, error } = await req.db.rpc('gs_mutate', { action, entity, payload: req.body });
    if (error) return fail(res, error);
    res.status(action.endsWith('.create') || action === 'payment.begin' ? 201 : 200).json(data);
  };
  app.get('/api/me', (req, res) => res.json(req.profile));
  app.patch('/api/me', mutation('profile.save'));
  for (const [url, table, order] of [['vehicles','vehicle','vehicle_id'],['reservations','reservation','reservation_id'],['sessions','charging_session','session_id'],['invoices','invoice','invoice_id'],['payments','payment','payment_id'],['stations','charging_station'],['bays','charger_bay'],['tariffs','tariff_plan'],['substations','substation']]) app.get(`/api/${url}`, (req,res)=>read(req,res,table,order));
  app.get('/api/stations/:id/bays', async (req,res)=>{const {data,error}=await req.db.from('charger_bay').select('*').eq('station_id',req.params.id);if(error)return fail(res,error);res.json(data);});
  app.get('/api/grid-load', async(req,res)=>{const {data,error}=await req.db.rpc('gs_grid_load');if(error)return fail(res,error);res.json(data);});
  for (const [url, table] of [['customers','app_user'],['missions','fleet_mission'],['organizations','fleet_org']]) app.get(`/api/${url}`,manager,(req,res)=>read(req,res,table));
  app.post('/api/vehicles',mutation('vehicle.save'));app.patch('/api/vehicles/:id',mutation('vehicle.save'));app.delete('/api/vehicles/:id',mutation('vehicle.archive'));
  app.post('/api/reservations',mutation('reservation.create'));app.post('/api/reservations/:id/cancel',mutation('reservation.cancel'));
  app.get('/api/reservation-checkouts',(req,res)=>read(req,res,'reservation_checkout','checkout_id'));
  app.post('/api/reservation-checkouts/:id/settle',mutation('reservation.checkout'));
  app.post('/api/sessions',mutation('session.create'));app.post('/api/sessions/:id/cancel',mutation('session.cancel'));
  for (const op of ['start','meter','complete','fail']) app.post(`/api/sessions/:id/${op}`,manager,mutation(`session.${op}`));
  for (const [url,action] of [['substations','substation.save'],['stations','station.save'],['bays','bay.save'],['tariffs','tariff.save']]) { app.post(`/api/${url}`,manager,mutation(action));app.patch(`/api/${url}/:id`,manager,mutation(action)); }
  app.post('/api/missions',manager,mutation('mission.create'));
  app.post('/api/invoices/:id/pay',mutation('payment.begin'));app.post('/api/payments/:id/settle',mutation('payment.settle'));app.post('/api/payments/:id/refund',manager,mutation('payment.refund'));
  app.get('/api/invoices/:id/pdf',async(req,res)=>{
    const {data:inv,error}=await req.db.from('invoice').select('*').eq('invoice_id',req.params.id).maybeSingle();
    if(error)return fail(res,error);if(!inv)return res.status(404).json({error:'Invoice not found.'});
    const payments=await req.db.from('payment').select('*').eq('invoice_id',inv.invoice_id).order('created_at',{ascending:false});if(payments.error)return fail(res,payments.error);
    if(!inv.snapshot)return res.status(409).json({error:'This legacy invoice has no verified billing snapshot. Ask a manager to reconcile it.'});
    const bytes=await invoicePdf(inv,payments.data,env.INVOICE_ISSUER || 'GridSync',env.INVOICE_ISSUER_ADDRESS || '');
    res.set('Content-Type','application/pdf');res.set('Content-Disposition',`attachment; filename="${inv.invoice_number.replace(/[^A-Za-z0-9-]/g,'')}.pdf"`);res.send(Buffer.from(bytes));
  });
  app.use('/api',(req,res)=>res.status(404).json({error:'API route not found.'}));
  app.use('/api-docs', require('swagger-ui-express').serve, require('swagger-ui-express').setup(require('yamljs').load(path.join(__dirname, '..', 'swagger.yaml'))));
  app.use(express.static(path.join(__dirname,'..','frontend'),{index:'index.html',dotfiles:'deny'}));
  app.get(['/login','/manager','/customer'],(req,res)=>res.sendFile(path.join(__dirname,'..','frontend',req.path==='/login'?'login.html':'dashboard.html')));
  app.use((err,req,res,next)=>{console.error('GridSync request failed:',err.message);if(!res.headersSent)res.status(err.status===400?400:500).json({error:err.status===400?'Malformed request body.':'The service could not complete this request. Please retry.'});});
  return app;
}
module.exports={createApp};
