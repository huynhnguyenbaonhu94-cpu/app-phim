import { and, count, desc, eq, sql } from "drizzle-orm";
import {
  customMovies,
  movieComments,
  movieRequests,
  movieSourceEpisodes,
  r2BackupRuns,
  specialChatAdminReads,
  specialChatMessages,
  tvStreams,
  tvVideoEpisodes,
  tvVideos,
  users,
} from "../drizzle/schema";
import { getDb } from "./db";

function asNumber(value: number | string | bigint | null | undefined): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function asIso(value: Date | string | null | undefined): string | null {
  if (!value) return null;
  const raw = typeof value === "string" ? value.trim() : value;
  const match = typeof raw === "string" ? /^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}(?:\.\d+)?)$/.exec(raw) : null;
  const date = value instanceof Date ? value : new Date(match ? `${match[1]}T${match[2]}Z` : raw);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

export async function getAdminDashboardStats() {
  const db = await getDb();
  if (!db) throw new Error("Database is not available.");

  const [
    userStatsRows,
    movieStatsRows,
    requestRows,
    commentRows,
    chatRows,
    unreadRows,
    tvChannelRows,
    tvVideoRows,
    movieEpisodeRows,
    tvEpisodeRows,
    backupRows,
    recentRequestRows,
  ] = await Promise.all([
    db.select({
      total: count(),
      admins: sql<number>`COALESCE(SUM(CASE WHEN ${users.role} = 'admin' THEN 1 ELSE 0 END), 0)`,
      privileged: sql<number>`COALESCE(SUM(CASE WHEN ${users.hasSpecialPrivileges} = 1 THEN 1 ELSE 0 END), 0)`,
    }).from(users),
    db.select({
      total: count(),
      published: sql<number>`COALESCE(SUM(CASE WHEN ${customMovies.isPublished} = 1 THEN 1 ELSE 0 END), 0)`,
      views: sql<number>`COALESCE(SUM(${customMovies.viewCount}), 0)`,
    }).from(customMovies),
    db.select({ status: movieRequests.status, total: count() }).from(movieRequests).groupBy(movieRequests.status),
    db.select({ total: count() }).from(movieComments),
    db.select({
      conversations: sql<number>`COUNT(DISTINCT ${specialChatMessages.userId})`,
      fromUsers: sql<number>`COALESCE(SUM(CASE WHEN ${specialChatMessages.sender} = 'user' THEN 1 ELSE 0 END), 0)`,
    }).from(specialChatMessages),
    db.select({ total: count() })
      .from(specialChatMessages)
      .leftJoin(specialChatAdminReads, eq(specialChatAdminReads.userId, specialChatMessages.userId))
      .where(and(
        eq(specialChatMessages.sender, "user"),
        sql`${specialChatMessages.id} > COALESCE(${specialChatAdminReads.lastReadMessageId}, 0)`,
      )),
    db.select({
      total: count(),
      active: sql<number>`COALESCE(SUM(CASE WHEN ${tvStreams.isActive} = 1 THEN 1 ELSE 0 END), 0)`,
    }).from(tvStreams),
    db.select({
      total: count(),
      active: sql<number>`COALESCE(SUM(CASE WHEN ${tvVideos.isActive} = 1 THEN 1 ELSE 0 END), 0)`,
    }).from(tvVideos),
    db.select({ total: count() }).from(movieSourceEpisodes),
    db.select({ total: count() }).from(tvVideoEpisodes),
    db.select({ total: count() }).from(r2BackupRuns),
    db.select({ id: movieRequests.id, title: movieRequests.title, status: movieRequests.status, createdAt: movieRequests.createdAt, requesterName: movieRequests.requesterName })
      .from(movieRequests)
      .orderBy(desc(movieRequests.createdAt), desc(movieRequests.id))
      .limit(5),
  ]);

  const requestCount = (status: string) => asNumber(requestRows.find((row) => row.status === status)?.total);
  const usersRow = userStatsRows[0];
  const moviesRow = movieStatsRows[0];
  const chatRow = chatRows[0];
  const channelRow = tvChannelRows[0];
  const tvVideoRow = tvVideoRows[0];

  return {
    generatedAt: new Date().toISOString(),
    counts: {
      users: asNumber(usersRow?.total),
      admins: asNumber(usersRow?.admins),
      privilegedUsers: asNumber(usersRow?.privileged),
      customMovies: asNumber(moviesRow?.total),
      publishedMovies: asNumber(moviesRow?.published),
      totalViews: asNumber(moviesRow?.views),
      requests: requestRows.reduce((total, row) => total + asNumber(row.total), 0),
      requestReceived: requestCount("received"),
      requestProcessing: requestCount("processing"),
      requestUpdated: requestCount("updated"),
      requestOther: requestCount("other"),
      comments: asNumber(commentRows[0]?.total),
      conversations: asNumber(chatRow?.conversations),
      messagesFromUsers: asNumber(chatRow?.fromUsers),
      unreadMessages: asNumber(unreadRows[0]?.total),
      tvChannels: asNumber(channelRow?.total),
      activeTvChannels: asNumber(channelRow?.active),
      tvVideos: asNumber(tvVideoRow?.total),
      activeTvVideos: asNumber(tvVideoRow?.active),
      episodes: asNumber(movieEpisodeRows[0]?.total) + asNumber(tvEpisodeRows[0]?.total),
      backups: asNumber(backupRows[0]?.total),
    },
    recentRequests: recentRequestRows.map((row) => ({
      id: row.id,
      title: row.title,
      status: row.status,
      createdAt: asIso(row.createdAt) || new Date(0).toISOString(),
      requesterName: row.requesterName,
    })),
  };
}
