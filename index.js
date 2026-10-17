require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { createClient } = require('@supabase/supabase-js');
const swaggerUi = require('swagger-ui-express');
const YAML = require('yamljs');
const path = require('path');

const app = express();
const port = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());

// Initialize Supabase client
const supabaseUrl = process.env.SUPABASE_URL || 'https://your-project.supabase.co';
const supabaseKey = process.env.SUPABASE_ANON_KEY || 'your-anon-key';
const supabase = createClient(supabaseUrl, supabaseKey);

// Swagger API Documentation
const swaggerDocument = YAML.load(path.join(__dirname, 'swagger.yaml'));
app.use('/api-docs', swaggerUi.serve, swaggerUi.setup(swaggerDocument));

// ----------------------------------------------------
// API Endpoints
// ----------------------------------------------------

// Get all substations
app.get('/api/substations', async (req, res) => {
  const { data, error } = await supabase.from('substation').select('*');
  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

// Get all charging stations
app.get('/api/stations', async (req, res) => {
  const { data, error } = await supabase.from('charging_station').select('*');
  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

// Get bays for a specific station
app.get('/api/stations/:id/bays', async (req, res) => {
  const { id } = req.params;
  const { data, error } = await supabase.from('charger_bay').select('*').eq('station_id', id);
  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

// Get all vehicles
app.get('/api/vehicles', async (req, res) => {
  const { data, error } = await supabase.from('vehicle').select('*');
  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

// Get user's reservations
app.get('/api/reservations', async (req, res) => {
  const { data, error } = await supabase.from('reservation').select('*');
  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

// Create a reservation
app.post('/api/reservations', async (req, res) => {
  const { user_id, vehicle_id, bay_id, start_time, end_time } = req.body;
  // In PostgreSQL, tsrange is represented as '[start,end)'
  const time_slot = `[${start_time},${end_time})`;

  const { data, error } = await supabase
    .from('reservation')
    .insert([
      { user_id, vehicle_id, bay_id, time_slot, status: 'confirmed' }
    ])
    .select();

  if (error) return res.status(400).json({ error: error.message });
  res.status(201).json(data[0]);
});

// Get active fleet missions
app.get('/api/missions', async (req, res) => {
  const { data, error } = await supabase.from('fleet_mission').select('*');
  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

// Create a fleet mission
app.post('/api/missions', async (req, res) => {
  const { vehicle_id, fleet_org_id, mission_label, departure_time, target_soc_pct, priority_level } = req.body;

  const { data, error } = await supabase
    .from('fleet_mission')
    .insert([
      { vehicle_id, fleet_org_id, mission_label, departure_time, target_soc_pct, priority_level, status: 'scheduled' }
    ])
    .select();

  if (error) return res.status(400).json({ error: error.message });
  res.status(201).json(data[0]);
});

// Health check endpoint
app.get('/', (req, res) => {
  res.send('GridSync API is running. View docs at /api-docs');
});

// Start server
app.listen(port, () => {
  console.log(`Server running on http://localhost:${port}`);
  console.log(`API Documentation available at http://localhost:${port}/api-docs`);
});
