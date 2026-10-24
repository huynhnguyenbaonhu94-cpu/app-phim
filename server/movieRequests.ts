import { desc, eq } from "drizzle-orm";
import { movieRequests } from "../drizzle/schema";
import { getDb } from "./db";

export const MOVIE_REQUEST_STATUSES = ["received", "processing", "updated", "other"] as const;
export type MovieRequestStatus = (typeof MOVIE_REQUEST_STATUSES)[number];

export type CreateMovieRequestInput = {
  userId?: number | null;
  requesterName?: string | null;
  requesterEmail?: string | null;
  title: string;
  link?: string | null;
  priority: string;
  notes?: string | null;
  posterUrl?: string | null;
};

export type UpdateMovieRequestInput = {
  status: MovieRequestStatus;
  adminMessage?: string | null;
};

export async function createMovieRequest(input: CreateMovieRequestInput) {
  const db = await getDb();
  if (!db) throw new Error("Không kết nối được cơ sở dữ liệu");
  const [inserted] = await db.insert(movieRequests).values({
    userId: input.userId ?? null,
    requesterName: input.requesterName?.trim() || null,
    requesterEmail: input.requesterEmail?.trim() || null,
    title: input.title.trim(),
    link: input.link?.trim() || null,
    priority: input.priority,
    notes: input.notes?.trim() || null,
    posterUrl: input.posterUrl?.trim() || null,
    status: "received",
    adminMessage: null,
    statusUpdatedAt: new Date(),
  }).$returningId();
  const row = await getMovieRequestById(inserted.id);
  if (!row) throw new Error("Không lưu được yêu cầu phim.");
  return row;
}

export async function getMovieRequestById(id: number) {
  const db = await getDb();
  if (!db) return null;
  const [row] = await db.select().from(movieRequests).where(eq(movieRequests.id, id)).limit(1);
  return row ?? null;
}

export async function listMovieRequestsForUser(userId: number) {
  const db = await getDb();
  if (!db) return [];
  return db.select().from(movieRequests)
    .where(eq(movieRequests.userId, userId))
    .orderBy(desc(movieRequests.createdAt), desc(movieRequests.id))
    .limit(100);
}

export async function listAllMovieRequests() {
  const db = await getDb();
  if (!db) return [];
  return db.select().from(movieRequests)
    .orderBy(desc(movieRequests.createdAt), desc(movieRequests.id))
    .limit(1000);
}

export async function updateMovieRequest(id: number, input: UpdateMovieRequestInput) {
  const db = await getDb();
  if (!db) throw new Error("Không kết nối được cơ sở dữ liệu");
  await db.update(movieRequests).set({
    status: input.status,
    adminMessage: input.adminMessage?.trim() || null,
    statusUpdatedAt: new Date(),
  }).where(eq(movieRequests.id, id));
  return getMovieRequestById(id);
}

export function movieRequestStatusLabel(status: string) {
  switch (status) {
    case "processing": return "Đang Xử Lý";
    case "updated": return "Đã Cập Nhật";
    case "other": return "Khác";
    default: return "Đã Tiếp Nhận";
  }
}
