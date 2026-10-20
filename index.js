require('dotenv').config();
const { createApp } = require('./server/app');
const app = createApp();
if (require.main === module) app.listen(process.env.PORT || 3000, () => console.log(`GridSync: http://localhost:${process.env.PORT || 3000}`));
module.exports = app;
