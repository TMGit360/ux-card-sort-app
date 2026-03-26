# Card Sort Tool: Vercel + Supabase deployment notes

## 1. Supabase
1. Create a new Supabase project.
2. Open the SQL Editor.
3. Run `supabase-schema.sql`.
4. In Authentication > Providers, keep Email enabled.
5. Decide whether email confirmation is required. For easier testing, you can temporarily disable confirmation.
6. In Project Settings > API, copy:
   - Project URL
   - anon public key
7. Paste those into `supabase-config.js`.

## 2. Local testing
Because this is a static app, use a simple local server instead of opening files directly.
Examples:
- `python -m http.server 8000`
- `npx serve .`

Then visit:
- `http://localhost:8000/admin.html`
- `http://localhost:8000/index.html?token=...`

## 3. Admin flow
1. Open `admin.html`.
2. Create an admin account with email + password.
3. Sign in.
4. Create a new study with:
   - study_id
   - study_name
   - study_key
   - cards
   - optional starting categories
5. Copy the participant link.
6. Share that link with participants.

## 4. Additional admins
An additional admin should:
1. create their own admin account
2. sign in
3. choose `Join existing study`
4. enter the matching `study_id` and `study_key`

## 5. Vercel
1. Put the project files in a GitHub repository.
2. Import the repository into Vercel.
3. Deploy as a static site.
4. If you prefer not to store `supabase-config.js` in Git, you can generate it during deployment, but for a simple static app it is acceptable to keep the Supabase URL and anon key in the client because the anon key is intended to be public.

## 6. Important note about admin sign-in
This implementation uses Supabase Auth email/password in the backend. If you need a non-email username system, that would require a custom auth layer or an Edge Function-based adapter.
