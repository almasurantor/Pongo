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
   NEXT_PUBLIC_SITE_URL=https://your-pongo-domain.example
   ```

   Keep `SUPABASE_SERVICE_ROLE_KEY` server-only. It powers the protected account
   deletion route and must never use a `NEXT_PUBLIC_` prefix.
   Set `NEXT_PUBLIC_SITE_URL` to the final HTTPS production domain so canonical
   and social-sharing metadata resolve to the Pongo URL.

3. Verify the file was created:
   ```bash
   cat .env.local
   ```

## Next Steps

After creating the `.env.local` file:

1. **Set up the database** - Run the SQL schema in Supabase:
   - Go to your Supabase dashboard
   - Navigate to SQL Editor
   - Copy and paste the contents of `supabase/schema.sql`
   - Run the SQL

2. **Install dependencies** (once Node.js is installed):
   ```bash
   npm install
   ```

3. **Run the development server**:
   ```bash
   npm run dev
   ```
