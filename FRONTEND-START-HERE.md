# GridSync — A new kind of current

A new responsive frontend with an original ivory, forest-green and electric-lime identity, a locally constructed 3D charging depot, pointer parallax, scroll-linked 3D movement, smooth anchor navigation, section reveals, and a motion-safe mode following your operating system preferences.

## Start in one command

From the extracted project folder, run:

```sh
node frontend/serve.cjs
```

Open **http://localhost:5173**. Node.js 18+ is recommended. This static server uses only Node's built-in modules; no frontend installation or build is needed. You can also serve the `frontend` folder using any ordinary static web server. Opening the HTML directly is not the recommended workflow.

The page initially opens a clearly labelled **Demo workspace**. Try the station search, operational-bay filter, bay detail panels, reservations, mission scheduling and grid detail panel. Demo additions are in memory and reset on reload or when selecting the demo workspace again. Demo values are illustrative, not actual telemetry. The 3D depot is illustrative in both modes. Operational means the charger is operational, not that a specific time slot is free.

## Connect the existing backend

In a second terminal, from the project root, follow the original backend setup:

```sh
npm install
```

Copy `.env.example` to `.env`, set your existing Supabase URL and anonymous key, then run:

```sh
npm start
```

Keep that terminal running. In the frontend, select **Demo workspace ↗**, enter `http://localhost:3000` (or your backend's origin), then select **Connect API**. The form checks every existing GET endpoint, including station bays, before replacing demo data. Records are created only by explicitly submitting a reservation or mission in connected mode. Supply real existing user and fleet organization IDs. No Supabase secrets are stored in frontend code.

After connection, use **Refresh data** for updated records. Data is loaded on connection and manual refresh; there is no claim of real-time telemetry. An API failure shows an error and retains the previous workspace. The API origin is remembered in browser local storage; connecting still requires an explicit action on each reload. For a remotely hosted frontend, configure an HTTPS backend with compatible CORS; `localhost` refers to the computer running the browser.

## Integration and original-project limitation

All original files are preserved byte-for-byte, including `index.js`, package files, README, SQL scripts, tests, and Swagger definitions. New files are only `frontend/` and this guide. The existing API health-check at `/` and `/api-docs` are untouched. The frontend runs on a separate port so no Express route or middleware needs changing.

The original archive mixes a Supabase/PostgreSQL Express API with SQL Server/T-SQL database scripts. In particular, the API expects numeric `vehicle_id` and reservation `time_slot`, while the bundled SQL scripts use `vin` and separate start/end fields. This discrepancy predates this frontend. No migration, database schema correction, or backend change has been made. The connected forms follow the payloads implemented in `index.js`; they require an existing Supabase schema compatible with that API. Vehicles without `vehicle_id` are displayed, but excluded from creation forms with a clear explanation if none are compatible. Several display fields accept the alternative names in the bundled SQL files.

### Existing endpoint coverage

| Frontend feature | Existing endpoint |
| --- | --- |
| Network cards and search | GET /api/stations |
| Bay details, capacity and operational counts | GET /api/stations/:id/bays |
| Grid capacity and substation details | GET /api/substations |
| Fleet and charge percentages | GET /api/vehicles |
| Reservation list and creation | GET, POST /api/reservations |
| Mission list and creation | GET, POST /api/missions |

The original backend does not implement authentication, user creation, vehicle creation, reservation cancellation or mission edits. The frontend exposes only supported operations. Backend error messages are shown on failed submissions; records are not silently moved into demo mode.

## Frontend files

- `frontend/index.html`: accessible semantic page and modal workspace.
- `frontend/styles.css`: responsive design, CSS 3D geometry and animations.
- `frontend/app.js`: API adapter, demo data, UI rendering, forms and motion.
- `frontend/serve.cjs`: optional dependency-free local static server.

No CDN, external fonts, downloaded images, WebGL library or image API key is required. API data is HTML-escaped before rendering. Dialogs use native focus management and keyboard dismissal. Motion respects `prefers-reduced-motion`. The page remains scrollable without JavaScript; data tools require JavaScript.

## Validation completed

JavaScript syntax checks passed. Isolated application-logic checks covered initial rendering, station search, HTML escaping, demo reservation creation, overlapping demo booking rejection, all API read routes, API error propagation and connected mission POST payloads. Static-server checks covered public assets and blocked non-public files. All 22 original project files were compared against the uploaded archive and are byte-for-byte identical.

Browser-level visual, keyboard and responsive interaction checks could not be completed in the build environment: no browser was installed, and the browser download failed. The connected API was checked using mocked responses; your real Supabase instance was not exercised because credentials were not supplied.
