import { redirect } from "next/navigation";
import { getAdminOrNull } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function AdminHome() {
  const admin = await getAdminOrNull();
  if (!admin) redirect("/login");           // not signed in, or not an admin
  const { count: pending } = await admin.sb
    .from("orders").select("*", { count: "exact", head: true }).eq("payment_status", "under_review");
  return (
    <main className="mx-auto max-w-6xl px-5 py-10">
      <h1 className="font-display text-3xl font-semibold">Admin</h1>
      <p className="mt-2 text-white/60">Signed in as {admin.email}</p>
      <p className="mt-8 text-lg">{pending ?? 0} payments waiting for review</p>
    </main>
  );
}
