# Supabase setup

Supabase is optional. Guest mode remains available when Supabase is not
configured. The checked-in migration adds owner-scoped outfit-plan history to
an existing Supabase schema. The profile, wardrobe, outfit, preference, and
private `wardrobe-images` base schema must already be present.

## 1. Create a project and apply the migration

1. Create a Supabase project and keep its database password private.
2. Install the [Supabase CLI](https://supabase.com/docs/guides/cli). From the
   repository root, initialize CLI configuration if this project has not
   already been initialized, then sign in:

   ```shell
   supabase init
   supabase login
   ```

3. This checkout includes the additive plan-history migration only. It expects
   `outfit_plans`, `outfits`, `outfit_items`, and the
   `outfit_items.wardrobe_item_snapshot` column to exist already. It does not
   initialize a blank Supabase project. For a project with its base schema and
   migration history configured, link the project and apply the unapplied
   migration:

   ```shell
   supabase link --project-ref YOUR_PROJECT_REF
   supabase db push
   ```

   The included `20261128120000_outfit_plan_history.sql` migration adds plan
   statuses and immutable, owner-scoped date-history snapshots. On an existing
   project whose schema was applied manually, paste this migration into the SQL
   Editor instead; reconcile CLI migration history before switching back to
   `supabase db push`.

   If earlier migrations have already been applied, run only unapplied
   migrations in order. Alternatively, paste the required migration into the
   Supabase SQL Editor. Choose one method; the CLI does not automatically
   record migrations run manually in the SQL Editor. Reconcile migration history
   before switching methods. If a run fails because a relation or policy
   already exists, stop and inspect the database before retrying; do not drop
   existing tables, rows, or policies to make the migration pass.

4. In Supabase Authentication settings, configure the site URL and redirect
   allowlist for the app. The default password-reset redirect is
   `wardrobe://auth-callback`; allowlist it, or use the platform-specific
   redirect URI and configure `SUPABASE_AUTH_REDIRECT_URL` to match.

## 2. Configure Flutter with client-safe values

Find the project URL and **publishable key** in the Supabase project API
settings. The older `anon` key is also a client key and is supported, but use
the publishable key for new setups. Both values are intentionally present in
client builds; database and Storage access must be protected by RLS.

Pass these values when running the app:

```shell
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

In PowerShell, use one line or backticks for line continuation:

```powershell
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

For release builds, pass the values from the build pipeline's protected
configuration rather than hard-coding them in source files. A publishable key
is not a password, but don't commit local environment files or credentials.
**Never use** `service_role`, `sb_secret_`, database passwords, or other
privileged secrets in Flutter, `--dart-define`, web assets, or source control.

## 3. Schema and ownership contract

Every application table has UUID identity, timestamps, indexes as appropriate,
and row-level security enabled. The authenticated owner is enforced through
`auth.uid()`. `outfit_items`, `outfit_plans`, and `outfit_plan_history` also use
composite foreign keys so linked records must belong to the same owner.

| Table | Purpose |
| --- | --- |
| `profiles` | Auth-user profile (`id` is the auth user UUID) |
| `wardrobe_items` | Title, category/subcategory, colors, style tags, occasion, season, optional brand/notes, favorite/archive flags, and optional Storage object path |
| `outfits` | Named outfit metadata |
| `outfit_items` | Ordered links between outfits and wardrobe items |
| `outfit_plans` | Schedule an outfit for a timestamp |
| `outfit_plan_history` | Owner-scoped status events with immutable item snapshots |
| `user_preferences` | Per-user style preferences |

Wardrobe sync upserts using `(user_id, local_id)`. Image object names use
`<authenticated-user-uuid>/<encoded-local-id>/photo.<jpg|png|webp>` in the
private `wardrobe-images` bucket. Images are limited to 10 MiB and JPEG, PNG,
or WebP. The Flutter editor currently stores compressed JPEGs no larger than
3 MiB. Use authenticated Storage APIs or signed URLs to display them; public
URLs are not available for a private bucket. Local item and photo data are
saved before any network request; failed uploads remain queued for retry.
Deleting a cloud item removes its Storage image only when no outfit link refers
to it. Outfit-item snapshots include the item metadata and image path as it was
when the link was created; deleting the item nulls the live foreign-key field
without deleting the historical link or snapshot.

## 4. Verification checklist

### Schema and policy inventory

Run this in the Supabase SQL Editor to confirm all seven tables have RLS enabled
and policies:

```sql
select
  n.nspname as schema_name,
  c.relname as table_name,
  c.relrowsecurity as rls_enabled,
  count(p.policyname) as policy_count
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
left join pg_policies p
  on p.schemaname = n.nspname and p.tablename = c.relname
where n.nspname = 'public'
  and c.relname in (
    'profiles',
    'wardrobe_items',
    'outfits',
    'outfit_items',
    'outfit_plans',
    'outfit_plan_history',
    'user_preferences'
  )
group by n.nspname, c.relname, c.relrowsecurity
order by c.relname;
```

Expect seven rows, `rls_enabled = true`, and at least one owner policy per
table. `outfit_plan_history` should have the
`outfit_plan_history_owner_access` policy.
An existing `wardrobe_items` table may retain its separate owner-scoped
select/insert/update/delete policies in addition to the consolidated policy.
Verify that every policy on that table is owner-scoped.

Confirm that the bucket is private and has the expected constraints:

```sql
select id, name, public, file_size_limit, allowed_mime_types
from storage.buckets
where id = 'wardrobe-images';
```

Expect `public = false`, a `file_size_limit` of `10485760`, and only the three
image content types listed above. Inspect Storage policies:

```sql
select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'storage'
  and tablename = 'objects'
  and policyname like 'wardrobe_images_owner_%'
order by policyname;
```

Expect select, insert, update, and delete policies, each scoped to the first
object-path folder matching `auth.uid()`.

Confirm the additive wardrobe fields are present and non-null defaults are set:

```sql
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'wardrobe_items'
  and column_name in (
    'title',
    'subcategory',
    'primary_color',
    'secondary_color',
    'style_tags',
    'occasion',
    'season',
    'notes',
    'is_favorite',
    'is_archived',
    'updated_at'
  )
order by column_name;
```

Confirm outfit links have snapshots and a nullable live item reference:

```sql
select
  column_name,
  is_nullable,
  data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'outfit_items'
  and column_name in ('wardrobe_item_id', 'wardrobe_item_snapshot')
order by column_name;
```

Expect `wardrobe_item_id` to be nullable and `wardrobe_item_snapshot` to be
`jsonb`. To verify the delete behavior with a disposable test item, link the
item to an outfit, delete it through the app, and confirm the `outfit_items`
row remains with a null `wardrobe_item_id` and a non-null snapshot:

```sql
select id, wardrobe_item_id, wardrobe_item_snapshot
from public.outfit_items
where wardrobe_item_snapshot is not null;
```

Verify date-history rows contain snapshots and valid statuses:

```sql
select id, plan_id, planned_for, status, item_snapshot, recorded_at
from public.outfit_plan_history
order by planned_for desc, recorded_at desc
limit 20;
```

Expect statuses to be `planned`, `worn`, `skipped`, or `modified`, and
`item_snapshot` to be a JSON array. History is removed only when its associated
plan is explicitly deleted; wardrobe-item edits or deletions do not rewrite it.

### Authenticated owner-isolation checks

Use two test accounts, A and B, signed in through the app or Supabase client.
Do not run owner-isolation tests as the SQL Editor's elevated database role:

- With A signed in, create and read A's profile/preferences, wardrobe item,
  outfit, outfit-item link, outfit plan, and plan-history events. Confirm the upsert
  `(user_id, local_id)` works.
- With B signed in, verify queries for A's rows and plan-history events return
  no rows, and attempts
  to update/delete A's rows or insert rows with A's `user_id` are denied or
  affect zero rows.
- Verify B cannot link B's outfit to A's wardrobe item (and vice versa).
- Upload an image under A's UUID folder; verify A can read/update/delete it.
  Verify B cannot read it or write to A's folder. Verify a write under B's own
  UUID folder succeeds.
- Confirm unauthenticated requests cannot read or write application rows or
  objects.

Remove test accounts and data when checks are complete.
