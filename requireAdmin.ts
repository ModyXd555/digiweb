import { createClient } from "@supabase/supabase-js";

/** Call at the top of EVERY admin API route / server action. Never trust the UI. */
export async function requireAdmin(req: Request) {
  const token = req.headers.get("authorization")?.replace("Bearer ", "");
  if (!token) throw new Response("Unauthorized", { status: 401 });

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL!;
  const svc = createClient(url, process.env.SUPABASE_SERVICE_ROLE_KEY!, {
    auth: { persistSession: false },
  });
  const { data: { user }, error } = await svc.auth.getUser(token);
  if (error || !user) throw new Response("Unauthorized", { status: 401 });

  const { data: profile } = await svc
    .from("profiles").select("role").eq("id", user.id).single();
  if (profile?.role !== "admin") throw new Response("Forbidden", { status: 403 });

  return { user, db: svc };
}
