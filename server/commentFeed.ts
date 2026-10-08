/**
 * Kênh thông báo thay đổi bình luận theo từng phim.
 *
 * Mỗi phim có một số `revision` tăng dần. Khi có bình luận mới, xoá hay ghim, số này
 * tăng và mọi yêu cầu đang chờ được trả về ngay. Nhờ vậy app và website nhận được
 * bình luận mới gần như tức thì mà không cần websocket — chỉ dùng HTTP thường nên
 * chạy được cả trên hosting cPanel.
 */

type Waiter = {
  resolve: (result: { revision: number; changed: boolean }) => void;
  timer: ReturnType<typeof setTimeout>;
};

const MAX_TRACKED_SLUGS = 500;

const revisions = new Map<string, number>();
const waiters = new Map<string, Set<Waiter>>();

export function commentRevision(slug: string): number {
  return revisions.get(slug) ?? 0;
}

/** Báo cho mọi người đang xem phim này biết danh sách bình luận vừa thay đổi. */
export function publishComments(slug: string): void {
  const next = commentRevision(slug) + 1;
  revisions.set(slug, next);
  if (revisions.size > MAX_TRACKED_SLUGS) {
    // Bỏ những phim lâu không ai xem để bộ nhớ không phình theo thời gian.
    for (const key of Array.from(revisions.keys())) {
      if (revisions.size <= MAX_TRACKED_SLUGS) break;
      if (!waiters.has(key)) revisions.delete(key);
    }
  }
  const pending = waiters.get(slug);
  if (!pending) return;
  for (const waiter of Array.from(pending)) {
    clearTimeout(waiter.timer);
    pending.delete(waiter);
    waiter.resolve({ revision: next, changed: true });
  }
  if (pending.size === 0) waiters.delete(slug);
}

/**
 * Chờ tối đa `timeoutMs` cho tới khi phim có thay đổi mới hơn `since`.
 * Trả về ngay nếu đã có thay đổi từ trước.
 */
export function waitForComments(
  slug: string,
  since: number,
  timeoutMs = 25_000,
): Promise<{ revision: number; changed: boolean }> {
  const current = commentRevision(slug);
  if (current > since) return Promise.resolve({ revision: current, changed: true });
  return new Promise((resolve) => {
    const pending = waiters.get(slug) ?? new Set<Waiter>();
    waiters.set(slug, pending);
    const waiter: Waiter = {
      resolve,
      timer: setTimeout(() => {
        pending.delete(waiter);
        if (pending.size === 0) waiters.delete(slug);
        resolve({ revision: commentRevision(slug), changed: false });
      }, Math.max(1_000, Math.min(timeoutMs, 60_000))),
    };
    waiter.timer.unref?.();
    pending.add(waiter);
  });
}
