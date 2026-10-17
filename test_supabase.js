require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_ANON_KEY;
const supabase = createClient(supabaseUrl, supabaseKey);

async function testSupabase() {
  console.log('Testing Supabase Connection & Schema...');
  
  // 1. Check if the table exists by doing a select
  const { data: selectData, error: selectError } = await supabase.from('substation').select('*');
  
  if (selectError) {
    console.error('❌ Database Test Failed. Make sure you ran the SQL in the Supabase SQL Editor.');
    console.error('Error Details:', selectError.message);
    process.exit(1);
  }
  
  console.log('✅ Connected successfully! Tables exist.');
  
  // 2. Try inserting dummy data
  console.log('Inserting a test Substation...');
  const { data: insertData, error: insertError } = await supabase
    .from('substation')
    .insert([
      { name: 'Central City Grid', max_grid_capacity_kw: 10000.00, region_code: 'US-EAST' }
    ])
    .select();
    
  if (insertError) {
    console.error('❌ Insert Test Failed:', insertError.message);
    process.exit(1);
  }
  
  console.log('✅ Insert Successful! Data:', insertData);
  
  // 3. Try to clean up the test data
  const testId = insertData[0].substation_id;
  const { error: deleteError } = await supabase.from('substation').delete().eq('substation_id', testId);
  
  if (deleteError) {
    console.warn('⚠️ Could not delete test data:', deleteError.message);
  } else {
    console.log('✅ Cleanup successful.');
  }
  
  console.log('🎉 ALL TESTS PASSED! Your Supabase database is ready to go.');
}

testSupabase();
