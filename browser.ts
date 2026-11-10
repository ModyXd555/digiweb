import { createBrowserClient } from "@supabase/ssr";

// Publishable key only. The secret key must never be imported in client code.
export const supabaseBrowser = () =>
  createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!
  );
