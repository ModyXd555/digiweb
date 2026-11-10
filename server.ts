import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

export async function supabaseServer() {
  const store = await cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll: () => store.getAll(),
        setAll: (list) => {
          try { list.forEach(({ name, value, options }) => store.set(name, value, options)); } catch {}
        },
      },
    }
  );
}

/** For admin pages: server-side check, runs under the user's own RLS. */
export async function getAdminOrNull() {
  const sb = await supabaseServer();
  const { data: { user } } = await sb.auth.getUser(); // verified with Supabase, not just a cookie
  if (!user) return null;
  const { data } = await sb.from("profiles").select("role,email").eq("id", user.id).single();
  return data?.role === "admin" ? { user, email: data.email as string, sb } : null;
}
