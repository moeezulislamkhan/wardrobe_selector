import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const bucketName = "wardrobe-images";
const pageSize = 100;

function respond(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return respond(405, { error: "Method not allowed." });
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return respond(401, { error: "Sign in before deleting your account." });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return respond(500, { error: "Account deletion is not configured." });
  }

  const callerClient = createClient(supabaseUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: authorization } },
  });
  const { data: userData, error: userError } = await callerClient.auth.getUser();
  if (userError || !userData.user) {
    return respond(401, { error: "Your session is invalid. Sign in again." });
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  try {
    const objectPaths = await listObjectPaths(adminClient, userData.user.id);
    for (let offset = 0; offset < objectPaths.length; offset += pageSize) {
      const { error } = await adminClient.storage
        .from(bucketName)
        .remove(objectPaths.slice(offset, offset + pageSize));
      if (error) throw error;
    }

    const { error: deleteError } = await adminClient.auth.admin.deleteUser(
      userData.user.id,
    );
    if (deleteError) throw deleteError;

    return respond(200, { deleted: true });
  } catch {
    return respond(500, {
      error: "Account deletion could not be completed. Please retry.",
    });
  }
});

async function listObjectPaths(
  adminClient: ReturnType<typeof createClient>,
  folder: string,
): Promise<string[]> {
  const paths: string[] = [];
  let offset = 0;
  while (true) {
    const { data, error } = await adminClient.storage
      .from(bucketName)
      .list(folder, { limit: pageSize, offset });
    if (error) throw error;
    if (data.length === 0) break;

    for (const entry of data) {
      const path = `${folder}/${entry.name}`;
      if (entry.id === null) {
        paths.push(...await listObjectPaths(adminClient, path));
      } else {
        paths.push(path);
      }
    }
    offset += data.length;
    if (data.length < pageSize) break;
  }
  return paths;
}
