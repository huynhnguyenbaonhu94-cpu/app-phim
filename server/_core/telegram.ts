import { TRPCError } from "@trpc/server";
import { ENV } from "./env";

export type MovieRequestNotification = {
  title: string;
  link?: string;
  priority: string;
  notes?: string;
  imageBase64?: string;
  imageMimeType?: string;
};

function requiredConfig(): { token: string; chatId: string } {
  const token = ENV.telegramBotToken.trim();
  const chatId = ENV.telegramChatId.trim();
  if (!token || !chatId) {
    throw new TRPCError({
      code: "INTERNAL_SERVER_ERROR",
      message: "Telegram chưa được cấu hình trên máy chủ.",
    });
  }
  return { token, chatId };
}

function apiURL(token: string, method: string): string {
  return `https://api.telegram.org/bot${encodeURIComponent(token)}/${method}`;
}

function notificationText(input: MovieRequestNotification): string {
  return [
    "🎬 YÊU CẦU PHIM MỚI",
    "",
    `Tên phim: ${input.title.trim()}`,
    `Mức độ ưu tiên: ${input.priority}`,
    input.link?.trim() ? `Link TMDB/IMDB: ${input.link.trim()}` : "Link TMDB/IMDB: Không có",
    input.notes?.trim() ? `Ghi chú: ${input.notes.trim()}` : "Ghi chú: Không có",
  ].join("\n");
}

async function assertTelegramResponse(response: Response): Promise<void> {
  if (!response.ok) {
    const detail = await response.text().catch(() => "");
    console.warn(`[Telegram] request failed (${response.status}) ${detail}`);
    throw new TRPCError({
      code: "BAD_GATEWAY",
      message: "Không thể gửi yêu cầu đến Telegram. Vui lòng thử lại sau.",
    });
  }
  const payload = await response.json().catch(() => null) as { ok?: boolean } | null;
  if (!payload?.ok) {
    throw new TRPCError({
      code: "BAD_GATEWAY",
      message: "Telegram không nhận được yêu cầu phim.",
    });
  }
}

export async function sendMovieRequestToTelegram(input: MovieRequestNotification): Promise<void> {
  const { token, chatId } = requiredConfig();
  const text = notificationText(input);
  const image = input.imageBase64?.trim();

  if (!image) {
    const response = await fetch(apiURL(token, "sendMessage"), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ chat_id: chatId, text }),
    });
    await assertTelegramResponse(response);
    return;
  }

  let bytes: Buffer;
  try {
    bytes = Buffer.from(image, "base64");
  } catch {
    throw new TRPCError({ code: "BAD_REQUEST", message: "Hình ảnh không hợp lệ." });
  }
  if (!bytes.length || bytes.length > 8 * 1024 * 1024) {
    throw new TRPCError({ code: "BAD_REQUEST", message: "Hình ảnh phải nhỏ hơn 8 MB." });
  }

  const form = new FormData();
  form.append("chat_id", chatId);
  form.append("caption", text);
  const imageBytes = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
  form.append("photo", new Blob([imageBytes], { type: input.imageMimeType || "image/jpeg" }), "movie-request.jpg");
  const response = await fetch(apiURL(token, "sendPhoto"), { method: "POST", body: form });
  await assertTelegramResponse(response);
}
