import { useEffect, useMemo, useState } from "react";
import { Link } from "wouter";
import { CheckSquare, Edit3, Image as ImageIcon, LogOut, Plus, RefreshCw, Search, Save, ShieldCheck, Smartphone, Square, Trash2, Upload, X } from "lucide-react";
import { AuthDialog } from "@/components/AuthDialog";
import { SelectField } from "@/components/SelectField";
import { PageShell, SectionHeading } from "@/components/CinemaChrome";
import { useAuth } from "@/_core/hooks/useAuth";
import { trpc } from "@/lib/trpc";
import { BadgeChip, NameText, emptyBadge, parseBadges, parseNameStyle, type CinemaBadge, type CinemaNameStyle } from "@/lib/cinemaBadges";
import { toast } from "sonner";

/** Chữ cái đầu của tên, dùng làm ảnh đại diện tạm khi tài khoản chưa có ảnh. */
function accountInitial(name: unknown) {
  const clean = typeof name === "string" ? name.trim() : "";
  return clean.length > 0 ? clean[0].toUpperCase() : "?";
}

function formatDate(value: unknown) {
  if (!value) return "Chưa có";
  const date = new Date(value as string | number | Date);
  return Number.isNaN(date.getTime()) ? "Chưa có" : date.toLocaleString("vi-VN");
}

/** Nhãn và kiểu tên dùng chung với danh sách bình luận, xem `@/lib/cinemaBadges`. */
type BadgeDraft = CinemaBadge;
type NameStyleDraft = CinemaNameStyle;

const BADGE_STYLES: Array<[BadgeDraft["style"], string]> = [
  ["solid", "Đặc"],
  ["gradient", "Chuyển sắc"],
  ["outline", "Viền"],
  ["glow", "Phát sáng"],
  ["shine", "Loé sáng"],
  ["pulse", "Nhấp nháy"],
  ["neon", "Neon"],
  ["gold", "Ánh kim"],
  ["hologram", "Hologram"],
];

const BADGE_FONTS: Array<[BadgeDraft["font"], string]> = [
  ["sans", "Không chân"],
  ["serif", "Có chân"],
  ["mono", "Đều"],
  ["script", "Viết tay"],
];

const BADGE_SIZES: Array<[BadgeDraft["size"], string]> = [
  ["sm", "Nhỏ"],
  ["md", "Vừa"],
  ["lg", "Lớn"],
];

const BADGE_ANIMATIONS: Array<[BadgeDraft["animation"], string]> = [
  ["none", "Không"],
  ["pulse", "Nhịp nhàng"],
  ["shine", "Loé sáng"],
  ["float", "Bồng bềnh"],
];

const NAME_EFFECTS: Array<[NameStyleDraft["effect"], string]> = [
  ["none", "Không"],
  ["glow", "Phát sáng"],
  ["gradient", "Chuyển sắc"],
  ["shine", "Loé sáng"],
  ["rainbow", "Cầu vồng"],
  ["outline", "Viền chữ"],
  ["neon", "Neon"],
  ["gold", "Ánh kim"],
  ["ice", "Băng giá"],
  ["fire", "Lửa"],
  ["shadow", "Bóng đổ"],
  ["underline", "Gạch chân"],
  ["breathe", "Thở nhẹ"],
];

const SUGGESTED_NAMES = ["VIP", "MOD", "Kim cương", "Thành viên vàng", "Tác giả"];

type AccountFilter = "all" | "admin" | "user" | "special" | "ordinary" | "email" | "no-email";

async function runWithConcurrency<T, R>(items: T[], limit: number, worker: (item: T) => Promise<R>): Promise<R[]> {
  const results: R[] = [];
  let cursor = 0;
  async function consume() {
    while (cursor < items.length) {
      const index = cursor++;
      results[index] = await worker(items[index]);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, () => consume()));
  return results;
}

/** Chuyển ảnh người dùng chọn thành data URL nhỏ gọn để lưu thẳng vào hồ sơ. */
async function fileToAvatarDataUrl(file: File, size = 256): Promise<string> {
  const raw = await new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result || ""));
    reader.onerror = () => reject(new Error("Không đọc được tệp ảnh."));
    reader.readAsDataURL(file);
  });
  const image = await new Promise<HTMLImageElement>((resolve, reject) => {
    const element = new Image();
    element.onload = () => resolve(element);
    element.onerror = () => reject(new Error("Ảnh không hợp lệ."));
    element.src = raw;
  });
  // Cắt vuông giữa ảnh rồi thu nhỏ, nhờ vậy ảnh đại diện luôn gọn và không méo.
  const side = Math.min(image.width, image.height);
  const canvas = document.createElement("canvas");
  canvas.width = size;
  canvas.height = size;
  const context = canvas.getContext("2d");
  if (!context) return raw;
  context.drawImage(image, (image.width - side) / 2, (image.height - side) / 2, side, side, 0, 0, size, size);
  return canvas.toDataURL("image/png");
}

/** Xem trước một nhãn; nhãn chưa điền thì hiện khung gợi ý thay vì khoảng trắng. */
function BadgePreview({ badge }: { badge: BadgeDraft }) {
  const ready = badge.type === "image" ? badge.imageUrl.length > 0 : badge.text.trim().length > 0;
  if (ready) return <BadgeChip badge={badge} />;
  return <span className="cin-badge cin-badge--placeholder">{badge.type === "image" ? <><ImageIcon size={12} /> ảnh/GIF</> : "Nhãn"}</span>;
}

export default function AdminAccounts() {
  const { user, loading } = useAuth();
  const [authOpen, setAuthOpen] = useState(false);
  const [selectedUserId, setSelectedUserId] = useState<number | null>(null);
  const [editingUserId, setEditingUserId] = useState<number | null>(null);
  const [form, setForm] = useState({ name: "", email: "", password: "", role: "user" as "user" | "admin" });
  const [badges, setBadges] = useState<BadgeDraft[]>([]);
  const [nameStyle, setNameStyle] = useState<NameStyleDraft>({ color: "", effect: "none" });
  const [avatarDraft, setAvatarDraft] = useState("");
  const [avatarNote, setAvatarNote] = useState("");
  const [styleNote, setStyleNote] = useState("");
  const [searchTerm, setSearchTerm] = useState("");
  const [accountFilter, setAccountFilter] = useState<AccountFilter>("all");
  const [selectedIds, setSelectedIds] = useState<Set<number>>(() => new Set());
  const [bulkPending, setBulkPending] = useState(false);
  const accounts = trpc.adminAccounts.list.useQuery(undefined, { enabled: user?.role === "admin", refetchInterval: 10_000, retry: false });
  const devices = trpc.adminAccounts.devices.useQuery({ userId: selectedUserId || 0 }, { enabled: user?.role === "admin" && selectedUserId !== null, refetchInterval: 10_000, retry: false });
  const logoutAll = trpc.adminAccounts.logoutAll.useMutation({ onSuccess: () => { toast.success("Đã đăng xuất tất cả thiết bị."); void accounts.refetch(); if (selectedUserId) void devices.refetch(); }, onError: error => toast.error("Không thể đăng xuất thiết bị", { description: error.message }) });
  const setSpecialPrivileges = trpc.adminAccounts.setSpecialPrivileges.useMutation({ onSuccess: () => { void accounts.refetch(); }, onError: error => toast.error("Không thể cập nhật đặc quyền", { description: error.message }) });
  const updateAccount = trpc.adminAccounts.update.useMutation({ onSuccess: async () => { setEditingUserId(null); setForm({ name: "", email: "", password: "", role: "user" }); toast.success("Đã cập nhật tài khoản."); await accounts.refetch(); }, onError: error => toast.error("Không thể cập nhật tài khoản", { description: error.message }) });
  const saveBadges = trpc.adminAccounts.setBadges.useMutation({ onSuccess: async () => { setStyleNote("Đã lưu nhãn hiển thị."); toast.success("Đã lưu nhãn hiển thị."); await accounts.refetch(); }, onError: error => toast.error("Không thể lưu nhãn", { description: error.message }) });
  const saveNameStyle = trpc.adminAccounts.setNameStyle.useMutation({ onSuccess: async () => { setStyleNote("Đã lưu kiểu tên người dùng."); toast.success("Đã lưu kiểu tên người dùng."); await accounts.refetch(); }, onError: error => toast.error("Không thể lưu kiểu tên", { description: error.message }) });
  const setAvatar = trpc.adminAccounts.setAvatar.useMutation({ onSuccess: async () => { setAvatarNote("Đã cập nhật ảnh đại diện."); toast.success("Đã cập nhật ảnh đại diện."); await accounts.refetch(); }, onError: error => toast.error("Không thể cập nhật ảnh đại diện", { description: error.message }) });
  const clearAvatar = trpc.adminAccounts.clearAvatar.useMutation({ onSuccess: async () => { setAvatarDraft(""); setAvatarNote("Đã xoá ảnh đại diện."); toast.success("Đã xoá ảnh đại diện."); await accounts.refetch(); }, onError: error => toast.error("Không thể xoá ảnh đại diện", { description: error.message }) });
  const uploadImage = trpc.customMovies.uploadImage.useMutation();

  const visibleAccounts = useMemo(() => {
    const query = searchTerm.trim().toLocaleLowerCase("vi-VN");
    return (accounts.data ?? []).filter(account => {
      const matchesSearch = !query || [account.name, account.email, String(account.id)].some(value => String(value || "").toLocaleLowerCase("vi-VN").includes(query));
      const matchesFilter = accountFilter === "all"
        || (accountFilter === "admin" && account.role === "admin")
        || (accountFilter === "user" && account.role !== "admin")
        || (accountFilter === "special" && account.hasSpecialPrivileges)
        || (accountFilter === "ordinary" && !account.hasSpecialPrivileges)
        || (accountFilter === "email" && Boolean(account.email?.trim()))
        || (accountFilter === "no-email" && !account.email?.trim());
      return matchesSearch && matchesFilter;
    });
  }, [accounts.data, accountFilter, searchTerm]);
  const selectedAccounts = useMemo(() => (accounts.data ?? []).filter(account => selectedIds.has(account.id)), [accounts.data, selectedIds]);
  const allVisibleSelected = visibleAccounts.length > 0 && visibleAccounts.every(account => selectedIds.has(account.id));

  useEffect(() => {
    const ids = new Set((accounts.data ?? []).map(account => account.id));
    setSelectedIds(current => {
      const next = new Set(Array.from(current).filter(id => ids.has(id)));
      return next.size === current.size ? current : next;
    });
  }, [accounts.data]);
  useEffect(() => {
    if (accounts.error) toast.error("Không thể tải danh sách tài khoản", { description: "Hãy thử tải lại sau ít giây." });
  }, [accounts.error]);

  function toggleSelected(id: number) {
    setSelectedIds(current => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  }

  function toggleVisibleSelection() {
    setSelectedIds(current => {
      const next = new Set(current);
      if (allVisibleSelected) visibleAccounts.forEach(account => next.delete(account.id));
      else visibleAccounts.forEach(account => next.add(account.id));
      return next;
    });
  }

  async function applyBulkPrivileges(enabled: boolean) {
    if (selectedAccounts.length === 0 || bulkPending) return;
    const label = enabled ? "cấp đặc quyền" : "bỏ đặc quyền";
    if (!window.confirm(`Xác nhận ${label} cho ${selectedAccounts.length} tài khoản đã chọn?`)) return;
    setBulkPending(true);
    const results = await runWithConcurrency(selectedAccounts, 4, async account => {
      try {
        await setSpecialPrivileges.mutateAsync({ userId: account.id, enabled });
        return { id: account.id, ok: true };
      } catch (error) {
        return { id: account.id, ok: false, error };
      }
    });
    const failed = results.filter(result => !result.ok);
    const succeededIds = results.filter(result => result.ok).map(result => result.id);
    setSelectedIds(current => new Set(Array.from(current).filter(id => !succeededIds.includes(id))));
    setBulkPending(false);
    await accounts.refetch();
    if (failed.length === 0) toast.success(`Đã ${label} cho ${results.length} tài khoản.`);
    else toast.error(`Đã cập nhật ${results.length - failed.length}/${results.length} tài khoản`, { description: `${failed.length} tài khoản lỗi; các mục lỗi vẫn được giữ lại để thử lại.` });
  }

  if (loading) return <PageShell><main className="content-wrap inner-page"><p>Đang kiểm tra quyền truy cập…</p></main></PageShell>;
  if (!user) return <PageShell><main className="content-wrap inner-page"><div className="empty-state"><ShieldCheck size={30} /><h3>Cần đăng nhập admin</h3><p>Đăng nhập tài khoản quản trị viên để quản lý tài khoản app.</p><button className="button button-primary" onClick={() => setAuthOpen(true)}>Đăng nhập</button></div><AuthDialog open={authOpen} onClose={() => setAuthOpen(false)} /></main></PageShell>;
  if (user.role !== "admin") return <PageShell><main className="content-wrap inner-page"><div className="empty-state"><ShieldCheck size={30} /><h3>Không có quyền truy cập</h3><p>Khu vực này chỉ dành cho quản trị viên.</p></div></main></PageShell>;

  function beginEdit(account: NonNullable<typeof accounts.data>[number]) {
    const profile = account as typeof account & { badge?: string | null; badges?: string | null; nameStyle?: string | null; avatar?: string | null };
    setEditingUserId(account.id);
    setForm({ name: account.name || "", email: account.email || "", password: "", role: account.role === "admin" ? "admin" : "user" });
    const existing = parseBadges(profile.badges);
    // Tài khoản cũ chỉ có một nhãn chữ: đưa luôn vào trình soạn để admin thấy và sửa tiếp.
    setBadges(existing.length > 0 ? existing : profile.badge ? [{ ...emptyBadge(0), id: "b1", text: profile.badge }] : []);
    setNameStyle(parseNameStyle(profile.nameStyle));
    setAvatarDraft(profile.avatar || "");
    setAvatarNote("");
    setStyleNote("");
  }

  function updateBadge(index: number, patch: Partial<BadgeDraft>) {
    setBadges((current) => current.map((badge, position) => (position === index ? { ...badge, ...patch } : badge)));
  }

  async function pickAvatar(file: File, userId: number) {
    setAvatarNote("Đang xử lý ảnh…");
    try {
      const dataUrl = await fileToAvatarDataUrl(file);
      setAvatarDraft(dataUrl);
      await setAvatar.mutateAsync({ userId, avatar: dataUrl });
    } catch (error) {
      toast.error("Không xử lý được ảnh", { description: error instanceof Error ? error.message : "Vui lòng thử lại." });
    }
  }

  async function uploadBadgeImage(index: number, file: File) {
    try {
      const base64 = await new Promise<string>((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(String(reader.result || "").split(",")[1] || "");
        reader.onerror = () => reject(new Error("Không đọc được tệp."));
        reader.readAsDataURL(file);
      });
      const result = await uploadImage.mutateAsync({ base64, filename: file.name, mimeType: file.type });
      updateBadge(index, { imageUrl: result.url });
    } catch (error) {
      toast.error("Không tải được ảnh nhãn", { description: error instanceof Error ? error.message : "Vui lòng thử lại." });
    }
  }

  return <PageShell><main className="content-wrap inner-page admin-accounts-page">
    <div className="page-topline"><Link href="/" className="back-link">← Trang chủ</Link><span className="result-note"><Link href="/admin/movie-requests" className="text-link">Yêu cầu phim</Link> · <Link href="/admin/movies" className="text-link">Quản lý phim</Link> · <Link href="/admin/special-chat" className="text-link">Chat đặc quyền</Link> · <Link href="/admin/r2-settings" className="text-link">R2 backup</Link> · Admin · cập nhật mỗi 10 giây</span></div>
    <SectionHeading eyebrow="CINEMORA ADMIN" title="Quản lý tất cả tài khoản app" action={<button className="admin-tv-refresh" onClick={() => accounts.refetch()} disabled={accounts.isFetching}><RefreshCw size={15} /></button>} />
    <p className="admin-accounts-note">Dữ liệu tài khoản, số thiết bị, yêu thích và lịch sử được lấy trực tiếp từ database. Website vẫn giữ thư viện local riêng.</p>
    <section className="admin-account-toolbar" aria-label="Tìm kiếm và lọc tài khoản">
      <label className="admin-account-search"><Search size={15} /><input value={searchTerm} onChange={event => setSearchTerm(event.target.value)} placeholder="Tìm theo tên, email hoặc ID…" aria-label="Tìm tài khoản" />{searchTerm && <button type="button" onClick={() => setSearchTerm("")} aria-label="Xoá tìm kiếm"><X size={14} /></button>}</label>
      <div className="admin-account-filters" role="tablist" aria-label="Bộ lọc tài khoản">
        {([["all", "Tất cả"], ["admin", "Admin"], ["user", "User"], ["special", "Đặc quyền"], ["ordinary", "Chưa đặc quyền"], ["email", "Có email"], ["no-email", "Thiếu email"]] as Array<[AccountFilter, string]>).map(([value, label]) => <button type="button" key={value} className={accountFilter === value ? "is-active" : ""} onClick={() => setAccountFilter(value)}>{label}</button>)}
      </div>
      <div className="admin-account-selection-bar"><label className="admin-select-current"><input type="checkbox" checked={allVisibleSelected} onChange={toggleVisibleSelection} disabled={visibleAccounts.length === 0} />{allVisibleSelected ? <CheckSquare size={15} /> : <Square size={15} />} Chọn kết quả hiện tại <span>({visibleAccounts.length})</span></label><span className="admin-selection-count">Đã chọn <b>{selectedAccounts.length}</b></span><div className="admin-bulk-actions"><button type="button" className="button button-primary" disabled={selectedAccounts.length === 0 || bulkPending} onClick={() => void applyBulkPrivileges(true)}><ShieldCheck size={14} /> Cấp đặc quyền</button><button type="button" className="button button-danger" disabled={selectedAccounts.length === 0 || bulkPending} onClick={() => void applyBulkPrivileges(false)}><ShieldCheck size={14} /> Bỏ đặc quyền</button></div></div>
    </section>
    <section className="admin-account-list">
      {accounts.isLoading ? <p>Đang tải danh sách tài khoản…</p> : accounts.error ? <div className="admin-inline-state"><p>Không thể tải danh sách tài khoản.</p><button type="button" className="button button-ghost" onClick={() => void accounts.refetch()}>Thử lại</button></div> : (accounts.data ?? []).length === 0 ? <p>Chưa có tài khoản nào.</p> : visibleAccounts.length === 0 ? <div className="admin-inline-state"><p>Không có tài khoản khớp bộ lọc hiện tại.</p><button type="button" className="button button-ghost" onClick={() => { setSearchTerm(""); setAccountFilter("all"); }}>Xoá bộ lọc</button></div> : visibleAccounts.map((account) => {
        const profile = account as typeof account & { avatar?: string | null; badge?: string | null; badges?: string | null; nameStyle?: string | null };
        const accountBadges = parseBadges(profile.badges);
        const accountNameStyle = parseNameStyle(profile.nameStyle);
        const legacyBadges = accountBadges.length === 0 && profile.badge ? [{ ...emptyBadge(0), id: "legacy", text: profile.badge }] : accountBadges;
        return <article className={`admin-account-card${selectedUserId === account.id ? " is-selected" : ""}`} key={account.id}>
        <div className="admin-account-main">
          <label className="admin-account-check"><input type="checkbox" checked={selectedIds.has(account.id)} onChange={() => toggleSelected(account.id)} aria-label={`Chọn ${account.name || account.email || `tài khoản #${account.id}`}`} />{selectedIds.has(account.id) ? <CheckSquare size={16} /> : <Square size={16} />}</label><div className="admin-account-avatar">{profile.avatar ? <img src={profile.avatar} alt="" /> : <span>{accountInitial(account.name)}</span>}</div>
          <div className="admin-account-copy"><strong><NameText name={account.name || "Chưa đặt tên"} style={accountNameStyle} />{legacyBadges.map((badge) => <BadgePreview key={badge.id} badge={badge} />)}</strong><span>{account.email || "Không có email"} · ID #{account.id} · {account.role}{account.hasSpecialPrivileges ? " · Đặc quyền" : ""}</span><small>Đăng ký: {formatDate(account.createdAt)} · Đăng nhập gần nhất: {formatDate(account.lastSignedIn)}</small></div>
          <div className="admin-account-stats"><b>{account.activeDeviceCount}/5</b><span>thiết bị</span><b>{account.favoriteCount}</b><span>yêu thích</span><b>{account.historyCount}</b><span>lịch sử</span></div>
          <button className="button button-ghost" onClick={() => setSelectedUserId(selectedUserId === account.id ? null : account.id)}><Smartphone size={14} /> Thiết bị</button>
          <button className={`button ${account.hasSpecialPrivileges ? "button-danger" : "button-primary"}`} disabled={setSpecialPrivileges.isPending} onClick={() => setSpecialPrivileges.mutate({ userId: account.id, enabled: !account.hasSpecialPrivileges })}><ShieldCheck size={14} /> {account.hasSpecialPrivileges ? "Bỏ đặc quyền" : "Cấp đặc quyền"}</button>
          <button className="button button-ghost" onClick={() => editingUserId === account.id ? setEditingUserId(null) : beginEdit(account)}><Edit3 size={14} /> Sửa</button>
          <button className="button button-danger" disabled={logoutAll.isPending} onClick={() => { if (window.confirm(`Đăng xuất tất cả thiết bị của ${account.email || account.name}?`)) logoutAll.mutate({ userId: account.id }); }}><LogOut size={14} /> Logout all</button>
        </div>
        {editingUserId === account.id && <div className="admin-account-edit">
          <div className="admin-edit-head">
            <div className="admin-edit-identity">
              <span className="admin-edit-avatar">{profile.avatar ? <img src={profile.avatar} alt="" /> : <span>{accountInitial(account.name)}</span>}</span>
              <div>
                <strong><NameText name={account.name || "Chưa đặt tên"} style={accountNameStyle} />{legacyBadges.map(badge => <BadgePreview key={badge.id} badge={badge} />)}</strong>
                <span>{account.email || "Không có email"} · ID #{account.id} · {account.role}</span>
              </div>
            </div>
            <button type="button" className="admin-tv-refresh" onClick={() => setEditingUserId(null)} title="Đóng bảng chỉnh sửa"><X size={14} /></button>
          </div>

          <div className="admin-edit-columns">
            <div className="admin-edit-column">
              <form className="admin-edit-card" onSubmit={(event) => { event.preventDefault(); updateAccount.mutate({ id: account.id, name: form.name.trim(), email: form.email.trim(), role: form.role, ...(form.password ? { password: form.password } : {}) }); }}>
                <div className="admin-edit-card-head"><span className="admin-edit-step">01</span><div><strong>Thông tin tài khoản</strong><small>Tên hiển thị, email, mật khẩu và quyền truy cập.</small></div></div>
                <div className="admin-edit-fields">
                  <label className="is-wide">Tên hiển thị<input value={form.name} onChange={event => setForm({ ...form, name: event.target.value })} required minLength={2} /></label>
                  <label className="is-wide">Email<input type="email" value={form.email} onChange={event => setForm({ ...form, email: event.target.value })} required /></label>
                  <label>Mật khẩu mới<small>Để trống nếu không đổi.</small><input type="password" value={form.password} onChange={event => setForm({ ...form, password: event.target.value })} placeholder="Ít nhất 8 ký tự" minLength={8} /></label>
                  <label>Quyền<small>admin xem được trang quản trị.</small><SelectField value={form.role} ariaLabel="Quyền" options={[{ value: "user", label: "user" }, { value: "admin", label: "admin" }]} onChange={(next) => setForm({ ...form, role: next as "user" | "admin" })} /></label>
                </div>
                <div className="admin-edit-foot">
                  <button className="button button-primary" disabled={updateAccount.isPending}><Save size={14} /> {updateAccount.isPending ? "Đang lưu…" : "Lưu thông tin"}</button>
                </div>
              </form>

              <div className="admin-edit-card">
                <div className="admin-edit-card-head"><span className="admin-edit-step">02</span><div><strong>Ảnh đại diện</strong><small>Xem, thay hoặc xoá ảnh đại diện của tài khoản này.</small></div></div>
                <div className="admin-avatar-row">
                  <button type="button" className="admin-avatar-frame" onClick={() => avatarDraft && window.open(avatarDraft, "_blank")} title={avatarDraft ? "Bấm để xem ảnh lớn" : "Chưa có ảnh"}>
                    {avatarDraft ? <img src={avatarDraft} alt="Ảnh đại diện" /> : <ShieldCheck size={26} />}
                  </button>
                  <div className="admin-avatar-actions">
                    <span className="button button-ghost"><Upload size={14} /> Tải ảnh lên<input type="file" accept="image/*" hidden onChange={event => { const file = event.target.files?.[0]; if (file) void pickAvatar(file, account.id); }} /></span>
                    <label className="admin-avatar-link">Hoặc dán link ảnh<input value={avatarDraft.startsWith("data:") ? "" : avatarDraft} onChange={event => setAvatarDraft(event.target.value)} placeholder="https://.../avatar.png" /><button type="button" className="button button-ghost" disabled={!avatarDraft.trim() || setAvatar.isPending} onClick={() => setAvatar.mutate({ userId: account.id, avatar: avatarDraft.trim() })}>Lưu link</button></label>
                    <button type="button" className="button button-danger" disabled={!profile.avatar || clearAvatar.isPending} onClick={() => { if (window.confirm("Xoá ảnh đại diện của tài khoản này?")) clearAvatar.mutate({ userId: account.id }); }}><Trash2 size={14} /> Xoá ảnh đại diện</button>
                    {avatarNote && <span className="admin-style-note">{avatarNote}</span>}
                  </div>
                </div>
              </div>
            </div>

            <div className="admin-edit-column">
              <div className="admin-edit-card">
                <div className="admin-edit-card-head"><span className="admin-edit-step">03</span><div><strong>Nhãn hiển thị (badge)</strong><small>Thêm nhiều nhãn cho một tài khoản: chữ có màu, hiệu ứng hoặc ảnh, GIF nhỏ.</small></div></div>
                <div className="admin-style-heading">
                  <span className="admin-style-count">{badges.length}/6 nhãn</span>
                  <button type="button" className="button button-ghost" disabled={badges.length >= 6} onClick={() => setBadges([...badges, emptyBadge(badges.length)])}><Plus size={14} /> Thêm nhãn</button>
                </div>
                {badges.length === 0 ? <p className="admin-style-empty">Tài khoản này chưa có nhãn nào.</p> : <div className="admin-badge-list">
                  {badges.map((badge, index) => <div className="admin-badge-card" key={badge.id}>
                    <div className="admin-badge-card-top">
                      <div className="admin-badge-tabs">
                        <button type="button" className={badge.type === "text" ? "is-active" : ""} onClick={() => updateBadge(index, { type: "text" })}>Chữ</button>
                        <button type="button" className={badge.type === "image" ? "is-active" : ""} onClick={() => updateBadge(index, { type: "image" })}>Ảnh / GIF</button>
                      </div>
                      <button type="button" className="admin-badge-remove" onClick={() => setBadges(badges.filter((_, position) => position !== index))}><Trash2 size={14} /> Xoá nhãn</button>
                    </div>
                    {badge.type === "text" ? <div className="admin-badge-grid">
                      <label>Nội dung nhãn<input value={badge.text} maxLength={24} onChange={event => updateBadge(index, { text: event.target.value })} placeholder="VIP, MOD, Kim cương…" /></label>
                      <label>Màu chữ<input type="color" value={badge.color || "#d2f36b"} onChange={event => updateBadge(index, { color: event.target.value })} /></label>
                      <label>Màu nền<input type="color" value={badge.background || "#243018"} onChange={event => updateBadge(index, { background: event.target.value })} /></label>
                      <label>Kiểu<SelectField value={badge.style} options={BADGE_STYLES.map(([value, label]) => ({ value, label }))} onChange={(next) => updateBadge(index, { style: next as BadgeDraft["style"] })} /></label>
                      <label>Font chữ<SelectField value={badge.font} options={BADGE_FONTS.map(([value, label]) => ({ value, label }))} onChange={(next) => updateBadge(index, { font: next as BadgeDraft["font"] })} /></label>
                      <label>Kích thước<SelectField value={badge.size} options={BADGE_SIZES.map(([value, label]) => ({ value, label }))} onChange={(next) => updateBadge(index, { size: next as BadgeDraft["size"] })} /></label>
                      <label>Hiệu ứng chuyển động<SelectField value={badge.animation} options={BADGE_ANIMATIONS.map(([value, label]) => ({ value, label }))} onChange={(next) => updateBadge(index, { animation: next as BadgeDraft["animation"] })} /></label>
                      <div className="admin-badge-suggest"><span>Gợi ý nhanh</span><div>{SUGGESTED_NAMES.map(name => <button type="button" key={name} onClick={() => updateBadge(index, { text: name })}>{name}</button>)}</div></div>
                    </div> : <div className="admin-badge-grid">
                      <label className="is-wide">Link ảnh hoặc GIF<input value={badge.imageUrl} onChange={event => updateBadge(index, { imageUrl: event.target.value })} placeholder="https://.../nhan.gif hoặc /uploads/movie-images/....png" /></label>
                      <label className="is-action">Tải ảnh từ máy<small>PNG, WebP, JPG. GIF nên dán link để giữ chuyển động.</small><span className="button button-ghost"><Upload size={14} /> Chọn tệp<input type="file" accept="image/*" hidden onChange={event => { const file = event.target.files?.[0]; if (file) void uploadBadgeImage(index, file); }} /></span></label>
                      <div className="admin-badge-suggest is-wide"><span>Gợi ý kích thước</span><p>Ảnh/GIF cao <b>18px</b> khi hiện trên app (nên làm ảnh cao 54–72px để nét trên màn hình Retina), rộng tối đa 64px, nền trong suốt, dung lượng dưới 300KB.</p></div>
                    </div>}
                    <div className="admin-badge-preview"><span>Xem trước</span><div><NameText name={form.name || account.name || "Tên người dùng"} style={nameStyle} /><BadgePreview badge={badge} /></div></div>
                  </div>)}
                </div>}
                <div className="admin-edit-foot">
                  <button type="button" className="button button-primary" disabled={saveBadges.isPending} onClick={() => { setStyleNote(""); saveBadges.mutate({ userId: account.id, badges: badges.map(badge => ({ ...badge, id: badge.id || "" })) }); }}><Save size={14} /> {saveBadges.isPending ? "Đang lưu…" : "Lưu nhãn hiển thị"}</button>
                </div>
              </div>

              <div className="admin-edit-card">
                <div className="admin-edit-card-head"><span className="admin-edit-step">04</span><div><strong>Làm nổi bật tên người dùng</strong><small>Đổi màu và hiệu ứng cho tên người này khi bình luận.</small></div></div>
                <div className="admin-name-style">
                  <label>Màu tên<input type="color" value={nameStyle.color || "#ffffff"} onChange={event => setNameStyle({ ...nameStyle, color: event.target.value })} /></label>
                  <label>Hiệu ứng<SelectField value={nameStyle.effect} options={NAME_EFFECTS.map(([value, label]) => ({ value, label }))} onChange={(next) => setNameStyle({ ...nameStyle, effect: next as NameStyleDraft["effect"] })} /></label>
                  <div className="admin-badge-preview"><span>Xem trước</span><div><NameText name={form.name || account.name || "Tên người dùng"} style={nameStyle} /></div></div>
                  <button type="button" className="button button-ghost" onClick={() => setNameStyle({ color: "", effect: "none" })}>Đặt lại mặc định</button>
                </div>
                <div className="admin-edit-foot">
                  <button type="button" className="button button-primary" disabled={saveNameStyle.isPending} onClick={() => { setStyleNote(""); saveNameStyle.mutate({ userId: account.id, nameStyle }); }}><Save size={14} /> {saveNameStyle.isPending ? "Đang lưu…" : "Lưu kiểu tên"}</button>
                </div>
              </div>
            </div>
          </div>

          {styleNote && <p className="admin-style-note">{styleNote}</p>}
        </div>}
        {selectedUserId === account.id && <div className="admin-account-devices">{devices.isLoading ? <span>Đang tải thiết bị…</span> : (devices.data ?? []).length ? devices.data?.map(device => <div className="admin-account-device" key={device.id}><span className={`device-status-dot${device.isOnline ? " online" : ""}`} /><strong>{device.deviceName}</strong><span>{device.ipAddress} · {device.location} · {device.isOnline ? "Online" : "Offline"}</span><small>Hoạt động: {formatDate(device.lastSeenAt)} · Tạo: {formatDate(device.createdAt)}</small></div>) : <span>Không có phiên đang hoạt động.</span>}</div>}
      </article>;
      })}
    </section>
  </main></PageShell>;
}
