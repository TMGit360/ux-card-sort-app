# UX Card Sort Tool

A browser-based card sorting platform for UX research. Researchers create studies, share a participant link, and collect + analyze how users naturally group concepts — a standard method for designing information architecture and navigation systems.

## Live Demo

Deploy your own instance by following the [setup instructions](#setup) below.

---

## Features

### For Researchers (Admin)
- Create and manage card sorting studies with custom cards and categories
- Toggle participant permissions: allow/disallow creating new categories
- Randomize card order per participant to reduce bias
- View a real-time participant directory with submission history
- Export participant data as CSV

### Analysis & Visualization
- **Sankey diagrams** — visualize card-to-category flow and category merge mappings
- **Bar charts** — cards sorted per category
- **Placement matrix** — heat map of how often each card landed in each category
- **Similarity matrix** — co-occurrence patterns showing which cards are grouped together
- **Dendrogram** — hierarchical clustering via Best Matching Method (BMM)
- PDF report export of all charts and data

### For Participants
- Simple name entry gate
- Drag-and-drop card sorting interface
- Optional category creation
- Works on desktop and tablet

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | HTML5, CSS3, Vanilla JavaScript (ES6+) |
| Database | [Supabase](https://supabase.com) (PostgreSQL + PostgREST) |
| Auth | Supabase Auth (email/password) |
| Charts | Google Charts API |
| PDF Export | jsPDF + html2canvas |
| Hosting | [Vercel](https://vercel.com) (static site) |

No build step required — this is a static application that runs directly in the browser.

---

## Project Structure

```
ux-card-sort-app/
├── index.html            # Landing page / participant entry point
├── sort.html             # Participant card sorting interface
├── admin.html            # Researcher dashboard and analysis
├── common-scripts.js     # Shared utility functions
└── supabase-config.js    # Supabase connection (not committed in production forks)
```

---

## Setup

### 1. Supabase

1. Create a new project at [supabase.com](https://supabase.com).
2. Open the **SQL Editor** and run the schema migration script (kept outside the repository) to create all tables, views, functions, and RLS policies.
3. In **Authentication > Providers**, confirm Email is enabled.
4. In **Project Settings > API**, copy your **Project URL** and **anon public key**.
5. Paste them into `supabase-config.js`:

```js
window.CARD_SORT_SUPABASE_CONFIG = {
  supabaseUrl: 'YOUR_PROJECT_URL',
  supabaseAnonKey: 'YOUR_ANON_KEY'
};
```

### 2. Local Development

Since this is a static app, serve it with any simple HTTP server:

```bash
# Python
python -m http.server 8000

# Node
npx serve .
```

Then open:
- `http://localhost:8000/admin.html` — researcher dashboard
- `http://localhost:8000/index.html` — participant landing page

### 3. Deploy to Vercel

1. Push the repository to GitHub.
2. Import the repository in [Vercel](https://vercel.com).
3. Deploy as a static site (no build command needed).

---

## Usage

### Creating a Study

1. Open `admin.html` and create an admin account.
2. Sign in and click **Create New Study**.
3. Enter a study ID, name, key, and your list of cards.
4. Optionally add starting categories and configure participant permissions.
5. Copy the generated **participant link** and share it with your participants.

### Adding Co-Researchers

Additional admins can join an existing study:
1. Create their own admin account and sign in.
2. Choose **Join Existing Study**.
3. Enter the matching study ID and study key.

### Analyzing Results

Once participants submit their sorts, open the **Analysis** tab in the admin dashboard to view all visualizations and export data.

---

## Database

The schema uses **Row-Level Security (RLS)** — admins can only read and write data for studies they own or have joined. Key tables:

| Table | Purpose |
|---|---|
| `studies` | Study metadata and public tokens |
| `study_admins` | Maps admins to studies (multi-admin support) |
| `sort_templates` | Cards and categories per study |
| `participants` | Participant records per study |
| `submissions` | Card sort results (JSON) per participant |

---

## License

MIT
