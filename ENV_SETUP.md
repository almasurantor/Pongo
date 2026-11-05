# Environment Variables Setup

Create a local `.env.local` file with your own Supabase project values. Do not commit
real environment values to GitHub.

## Steps

1. In your terminal, navigate to the project directory:
   ```bash
   cd "/Users/almasur/Music/untitled folder/Pongo"
   ```

2. Copy the template:
   ```bash
   cp env.local.template .env.local
   ```

   Then fill in your Supabase project values:

   ```
   NEXT_PUBLIC_SUPABASE_URL=https://your-project-ref.supabase.co
   NEXT_PUBLIC_SUPABASE_ANON_KEY=your-supabase-anon-key
   SUPABASE_SERVICE_ROLE_KEY=your-server-only-service-role-key
   NEXT_PUBLIC_SITE_URL=https://playpongo.vercel.app
   ```

   Keep `SUPABASE_SERVICE_ROLE_KEY` server-only. It powers the protected account
   deletion route and must never use a `NEXT_PUBLIC_` prefix.
   Set `NEXT_PUBLIC_SITE_URL` to `https://playpongo.vercel.app` in Vercel so canonical
   and social-sharing metadata resolve to the Pongo URL.

3. Verify the file was created:
   ```bash
   test -f .env.local && echo ".env.local is present"
   ```

## Next Steps

After creating the `.env.local` file:

1. **Set up the database** with the Supabase CLI. The first migration contains
   the complete baseline; do not create a second schema outside the migration chain:
   ```bash
   npx supabase start
   npx supabase db reset
   npm run test:db:local
   ```
   For production, link the intended project, review the migration plan and
   reconcile its migration history before running `supabase db push`.

2. **Install dependencies** (once Node.js is installed):
   ```bash
   npm install
   ```

3. **Run the development server**:
   ```bash
   npm run dev
   ```
