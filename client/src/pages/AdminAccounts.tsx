import { useState } from "react";
import { Link } from "wouter";
import { Edit3, LogOut, RefreshCw, Save, ShieldCheck, Smartphone, X } from "lucide-react";
import { AuthDialog } from "@/components/AuthDialog";
import { PageShell, SectionHeading } from "@/components/CinemaChrome";
import { useAuth } from "@/_core/hooks/useAuth";
import { trpc } from "@/lib/trpc";

function formatDate(value: unknown) {
  if (!value) return "Chưa có";
  const date = new Date(value as string | number | Date);
  return Number.isNaN(date.getTime()) ? "Chưa có" : date.toLocaleString("vi-VN");
}

export default function AdminAccounts() {
  const { user, loading } = useAuth();
  const [authOpen, setAuthOpen] = useState(false);
  const [selectedUserId, setSelectedUserId] = useState<number | null>(null);
  const [editingUserId, setEditingUserId] = useState<number | null>(null);
  const [form, setForm] = useState({ name: "", email: "", password: "", role: "user" as "user" | "admin" });
  const accounts = trpc.adminAccounts.list.useQuery(undefined, { enabled: user?.role === "admin", refetchInterval: 10_000, retry: false });
  const devices = trpc.adminAccounts.devices.useQuery({ userId: selectedUserId || 0 }, { enabled: user?.role === "admin" && selectedUserId !== null, refetchInterval: 10_000, retry: false });
  const logoutAll = trpc.adminAccounts.logoutAll.useMutation({ onSuccess: () => { accounts.refetch(); if (selectedUserId) devices.refetch(); } });
  const updateAccount = trpc.adminAccounts.update.useMutation({ onSuccess: async () => { setEditingUserId(null); setForm({ name: "", email: "", password: "", role: "user" }); await accounts.refetch(); } });

  if (loading) return <PageShell><main className="content-wrap inner-page"><p>Đang kiểm tra quyền truy cập…</p></main></PageShell>;
  if (!user) return <PageShell><main className="content-wrap inner-page"><div className="empty-state"><ShieldCheck size={30} /><h3>Cần đăng nhập admin</h3><p>Đăng nhập tài khoản quản trị viên để quản lý tài khoản app.</p><button className="button button-primary" onClick={() => setAuthOpen(true)}>Đăng nhập</button></div><AuthDialog open={authOpen} onClose={() => setAuthOpen(false)} /></main></PageShell>;
  if (user.role !== "admin") return <PageShell><main className="content-wrap inner-page"><div className="empty-state"><ShieldCheck size={30} /><h3>Không có quyền truy cập</h3><p>Khu vực này chỉ dành cho quản trị viên.</p></div></main></PageShell>;

  function beginEdit(account: NonNullable<typeof accounts.data>[number]) {
    setEditingUserId(account.id);
    setForm({ name: account.name || "", email: account.email || "", password: "", role: account.role === "admin" ? "admin" : "user" });
  }

  return <PageShell><main className="content-wrap inner-page admin-accounts-page">
    <div className="page-topline"><Link href="/" className="back-link">← Trang chủ</Link><span className="result-note">Admin · cập nhật mỗi 10 giây</span></div>
    <SectionHeading eyebrow="CINEMORA ADMIN" title="Quản lý tất cả tài khoản app" action={<button className="admin-tv-refresh" onClick={() => accounts.refetch()} disabled={accounts.isFetching}><RefreshCw size={15} /></button>} />
    <p className="admin-accounts-note">Dữ liệu tài khoản, số thiết bị, yêu thích và lịch sử được lấy trực tiếp từ database. Website vẫn giữ thư viện local riêng.</p>
    <section className="admin-account-list">
      {accounts.isLoading ? <p>Đang tải danh sách tài khoản…</p> : (accounts.data ?? []).map((account) => <article className={`admin-account-card${selectedUserId === account.id ? " is-selected" : ""}`} key={account.id}>
        <div className="admin-account-main">
          <div className="admin-account-avatar"><ShieldCheck size={17} /></div>
          <div className="admin-account-copy"><strong>{account.name || "Chưa đặt tên"}</strong><span>{account.email || "Không có email"} · ID #{account.id} · {account.role}</span><small>Đăng ký: {formatDate(account.createdAt)} · Đăng nhập gần nhất: {formatDate(account.lastSignedIn)}</small></div>
          <div className="admin-account-stats"><b>{account.activeDeviceCount}/5</b><span>thiết bị</span><b>{account.favoriteCount}</b><span>yêu thích</span><b>{account.historyCount}</b><span>lịch sử</span></div>
          <button className="button button-ghost" onClick={() => setSelectedUserId(selectedUserId === account.id ? null : account.id)}><Smartphone size={14} /> Thiết bị</button>
          <button className="button button-ghost" onClick={() => editingUserId === account.id ? setEditingUserId(null) : beginEdit(account)}><Edit3 size={14} /> Sửa</button>
          <button className="button button-danger" disabled={logoutAll.isPending} onClick={() => { if (window.confirm(`Đăng xuất tất cả thiết bị của ${account.email || account.name}?`)) logoutAll.mutate({ userId: account.id }); }}><LogOut size={14} /> Logout all</button>
        </div>
        {editingUserId === account.id && <form className="admin-account-edit" onSubmit={(event) => { event.preventDefault(); updateAccount.mutate({ id: account.id, name: form.name.trim(), email: form.email.trim(), role: form.role, ...(form.password ? { password: form.password } : {}) }); }}>
          <div className="admin-account-edit-heading"><strong>Chỉnh sửa thông tin tài khoản</strong><button type="button" className="admin-tv-refresh" onClick={() => setEditingUserId(null)}><X size={14} /></button></div>
          <div className="admin-account-edit-grid"><label>Tên hiển thị<input value={form.name} onChange={event => setForm({ ...form, name: event.target.value })} required minLength={2} /></label><label>Email<input type="email" value={form.email} onChange={event => setForm({ ...form, email: event.target.value })} required /></label><label>Mật khẩu mới<input type="password" value={form.password} onChange={event => setForm({ ...form, password: event.target.value })} placeholder="Để trống nếu không đổi" minLength={8} /></label><label>Quyền<select value={form.role} onChange={event => setForm({ ...form, role: event.target.value as "user" | "admin" })}><option value="user">user</option><option value="admin">admin</option></select></label></div>
          <button className="button button-primary" disabled={updateAccount.isPending}><Save size={14} /> {updateAccount.isPending ? "Đang lưu…" : "Lưu thông tin"}</button>{updateAccount.error && <span className="admin-tv-error">{updateAccount.error.message}</span>}
        </form>}
        {selectedUserId === account.id && <div className="admin-account-devices">{devices.isLoading ? <span>Đang tải thiết bị…</span> : (devices.data ?? []).length ? devices.data?.map(device => <div className="admin-account-device" key={device.id}><span className={`device-status-dot${device.isOnline ? " online" : ""}`} /><strong>{device.deviceName}</strong><span>{device.ipAddress} · {device.location} · {device.isOnline ? "Online" : "Offline"}</span><small>Hoạt động: {formatDate(device.lastSeenAt)} · Tạo: {formatDate(device.createdAt)}</small></div>) : <span>Không có phiên đang hoạt động.</span>}</div>}
      </article>)}
    </section>
  </main></PageShell>;
}
