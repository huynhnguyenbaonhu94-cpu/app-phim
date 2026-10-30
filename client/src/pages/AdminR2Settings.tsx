import { useEffect, useState } from "react";
import { CheckCircle2, Cloud, DatabaseBackup, KeyRound, Link as LinkIcon, RefreshCw, Save, ShieldCheck, TestTube2 } from "lucide-react";
import { Link } from "wouter";
import { toast } from "sonner";
import { AuthDialog } from "@/components/AuthDialog";
import { PageShell, SectionHeading } from "@/components/CinemaChrome";
import { useAuth } from "@/_core/hooks/useAuth";
import { trpc } from "@/lib/trpc";

type BackupFrequency = "daily" | "weekly";
type BackupSchedule = { enabled: boolean; frequency: BackupFrequency; scheduleHourUtc: number };
type R2SettingsDraft = {
  accountId: string;
  bucket: string;
  accessKeyId: string;
  secretAccessKey: string;
  endpoint: string;
  region: string;
  publicBaseUrl: string;
};

type BackupStatus = {
  configured?: boolean;
  running?: boolean;
  latest?: { status?: string | null; startedAt?: string | Date | null; completedAt?: string | Date | null; errorMessage?: string | null; backupKey?: string | null; byteSize?: number | null } | null;
};

const emptyForm: R2SettingsDraft = { accountId: "", bucket: "", accessKeyId: "", secretAccessKey: "", endpoint: "", region: "auto", publicBaseUrl: "" };
const defaultEndpoint = (accountId: string) => accountId.trim() ? `https://${accountId.trim()}.r2.cloudflarestorage.com` : "";

function accountIdFromEndpoint(endpoint: string) {
  try {
    const hostname = new URL(endpoint).hostname;
    return hostname.split(".")[0] || "";
  } catch {
    return "";
  }
}

function formatDate(value: string | Date | null | undefined) {
  if (!value) return "Chưa có";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "Chưa có" : date.toLocaleString("vi-VN", { timeZone: "Asia/Ho_Chi_Minh" });
}

function formatBytes(value?: number | null) {
  if (!value || value < 0) return "—";
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  return `${(value / (1024 * 1024)).toFixed(1)} MB`;
}

export default function AdminR2Settings() {
  const { user, loading } = useAuth();
  const [authOpen, setAuthOpen] = useState(false);
  const [form, setForm] = useState<R2SettingsDraft>(emptyForm);
  const [schedule, setSchedule] = useState<BackupSchedule>({ enabled: false, frequency: "daily", scheduleHourUtc: 2 });
  const settings = trpc.adminR2.getSettings.useQuery(undefined, { enabled: user?.role === "admin", retry: false });
  const backupStatusQuery = trpc.adminR2.getBackupStatus.useQuery(undefined, { enabled: user?.role === "admin", retry: false, refetchInterval: 10_000 });
  const saveSettings = trpc.adminR2.saveSettings.useMutation();
  const testConnection = trpc.adminR2.testConnection.useMutation();
  const runBackup = trpc.adminR2.runBackup.useMutation();
  const updateBackupSchedule = trpc.adminR2.updateBackupSchedule.useMutation();

  useEffect(() => {
    const value = settings.data;
    if (!value) return;
    setForm(current => ({
      ...current,
      accountId: accountIdFromEndpoint(value.endpoint || ""),
      bucket: value.bucket || "",
      accessKeyId: "",
      secretAccessKey: "",
      endpoint: value.endpoint || "",
      region: value.region || "auto",
      publicBaseUrl: value.publicBaseUrl || "",
    }));
    setSchedule({ enabled: Boolean(value.backupEnabled), frequency: value.backupFrequency === "weekly" ? "weekly" : "daily", scheduleHourUtc: value.scheduleHourUtc ?? 2 });
  }, [settings.data]);

  useEffect(() => {
    if (settings.error) toast.error("Không thể tải cấu hình R2", { description: settings.error.message });
  }, [settings.error]);

  if (loading) return <PageShell><main className="content-wrap inner-page"><p>Đang kiểm tra quyền truy cập…</p></main></PageShell>;
  if (!user) return <PageShell><main className="content-wrap inner-page"><div className="empty-state"><ShieldCheck size={30} /><h3>Cần đăng nhập admin</h3><p>Đăng nhập tài khoản quản trị viên để cấu hình lưu trữ và backup.</p><button className="button button-primary" onClick={() => setAuthOpen(true)}>Đăng nhập</button></div><AuthDialog open={authOpen} onClose={() => setAuthOpen(false)} /></main></PageShell>;
  if (user.role !== "admin") return <PageShell><main className="content-wrap inner-page"><div className="empty-state"><ShieldCheck size={30} /><h3>Không có quyền truy cập</h3><p>Khu vực này chỉ dành cho quản trị viên.</p></div></main></PageShell>;

  function updateField(field: keyof R2SettingsDraft, value: string) {
    setForm(current => ({ ...current, [field]: value }));
  }

  function updateAccountId(value: string) {
    setForm(current => {
      const oldDefault = defaultEndpoint(current.accountId);
      const shouldUpdateEndpoint = !current.endpoint || current.endpoint === oldDefault;
      return { ...current, accountId: value, endpoint: shouldUpdateEndpoint ? defaultEndpoint(value) : current.endpoint };
    });
  }

  function currentEndpoint() {
    return form.endpoint.trim() || defaultEndpoint(form.accountId);
  }

  function validateSettings() {
    if (!form.bucket.trim() || !currentEndpoint()) {
      toast.error("Thiếu thông tin R2", { description: "Cần điền bucket và Account ID hoặc S3 API endpoint." });
      return false;
    }
    const hasSaved = Boolean(settings.data?.hasAccessKeyId && settings.data?.hasSecretAccessKey);
    if ((!form.accessKeyId.trim() || !form.secretAccessKey.trim()) && !hasSaved) {
      toast.error("Thiếu API credentials", { description: "Nhập Access Key ID và Secret Access Key mới của R2." });
      return false;
    }
    if (settings.data?.encryptionKeyConfigured === false) {
      toast.error("Chưa cấu hình khóa mã hóa", { description: "Thêm R2_SETTINGS_ENCRYPTION_KEY vào biến môi trường Node.js trên cPanel, sau đó khởi động lại ứng dụng." });
      return false;
    }
    return true;
  }

  function settingsPayload() {
    return {
      endpoint: currentEndpoint(),
      bucket: form.bucket.trim(),
      region: form.region.trim() || "auto",
      publicBaseUrl: form.publicBaseUrl.trim() || null,
      backupEnabled: schedule.enabled,
      backupFrequency: schedule.frequency,
      scheduleHourUtc: Math.min(23, Math.max(0, Number(schedule.scheduleHourUtc) || 0)),
      ...(form.accessKeyId.trim() ? { accessKeyId: form.accessKeyId.trim() } : {}),
      ...(form.secretAccessKey.trim() ? { secretAccessKey: form.secretAccessKey.trim() } : {}),
    };
  }

  async function saveConfiguration() {
    if (!validateSettings()) return false;
    try {
      await saveSettings.mutateAsync(settingsPayload());
      setForm(current => ({ ...current, accessKeyId: "", secretAccessKey: "" }));
      await settings.refetch();
      toast.success("Đã lưu cấu hình Cloudflare R2.");
      return true;
    } catch (error) {
      toast.error("Không thể lưu cấu hình R2", { description: error instanceof Error ? error.message : "Vui lòng kiểm tra thông tin và thử lại." });
      return false;
    }
  }

  async function saveAndTest() {
    const saved = await saveConfiguration();
    if (!saved) return;
    try {
      const result = await testConnection.mutateAsync({});
      await backupStatusQuery.refetch();
      toast.success("Kết nối Cloudflare R2 thành công", { description: `Đã upload, đọc và xóa object kiểm tra (${formatBytes(result.bytes)}).` });
    } catch (error) {
      toast.error("Kết nối R2 thất bại", { description: error instanceof Error ? error.message : "Kiểm tra endpoint, quyền bucket và credentials." });
    }
  }

  async function saveSchedule() {
    if (!settings.data?.configured) {
      toast.error("Hãy cấu hình và kiểm tra R2 trước khi bật lịch backup.");
      return;
    }
    try {
      await updateBackupSchedule.mutateAsync({ enabled: schedule.enabled, frequency: schedule.frequency, scheduleHourUtc: schedule.scheduleHourUtc });
      await backupStatusQuery.refetch();
      toast.success("Đã cập nhật lịch backup.");
    } catch (error) {
      toast.error("Không thể cập nhật lịch backup", { description: error instanceof Error ? error.message : "Vui lòng thử lại." });
    }
  }

  async function backupNow() {
    try {
      const result = await runBackup.mutateAsync({});
      await backupStatusQuery.refetch();
      if (result.success) toast.success("Backup hoàn tất", { description: `Đã lưu ${formatBytes(result.bytes)} lên R2.` });
      else toast.error("Backup chưa hoàn tất", { description: result.error || "Xem trạng thái backup để biết thêm chi tiết." });
    } catch (error) {
      toast.error("Không thể chạy backup", { description: error instanceof Error ? error.message : "Vui lòng thử lại." });
    }
  }

  const status = backupStatusQuery.data as BackupStatus | undefined;
  const latest = status?.latest;
  const statusLabel = status?.running || latest?.status === "running" ? "Đang chạy" : latest?.status === "completed" ? "Thành công" : latest?.status === "failed" ? "Lỗi" : "Chưa chạy";
  const lastBackupAt = latest?.completedAt || latest?.startedAt;
  const encryptionReady = settings.data?.encryptionKeyConfigured !== false;
  const credentialsReady = Boolean(settings.data?.hasAccessKeyId && settings.data?.hasSecretAccessKey);
  const r2Ready = Boolean(settings.data?.configured);

  return <PageShell><main className="content-wrap inner-page admin-r2-page">
    <div className="page-topline"><Link href="/admin/accounts" className="back-link">← Tài khoản</Link><span className="result-note"><Link href="/admin/accounts" className="text-link">Quản lý tài khoản</Link> · <Link href="/admin/special-chat" className="text-link">Chat đặc quyền</Link> · R2 backup</span></div>
    <SectionHeading eyebrow="CINEMORA ADMIN · STORAGE" title="Cloudflare R2 & backup" action={<button className="admin-tv-refresh" onClick={() => { void settings.refetch(); void backupStatusQuery.refetch(); }} disabled={Boolean(settings.isFetching || backupStatusQuery.isFetching)} title="Cập nhật trạng thái"><RefreshCw size={15} /></button>} />
    <p className="admin-r2-intro">Lưu tệp chat riêng tư, ảnh poster/thumbnail và phụ đề admin upload vào object storage; sao lưu database theo lịch. Tệp đã tồn tại trong thư mục uploads cũ không bị xóa hoặc tự chuyển. Secret chỉ được gửi khi nhập mới và không bao giờ trả về trình duyệt.</p>

    <section className="admin-r2-grid">
      <div className="admin-r2-card admin-r2-form">
        <div className="admin-r2-card-heading"><span className="admin-r2-icon"><Cloud size={17} /></span><div><strong>Đích lưu trữ R2</strong><small>Cloudflare R2 tương thích giao thức S3.</small></div></div>
        <div className="admin-r2-help"><strong>Tạo bucket và token giới hạn quyền</strong><span>Trong Cloudflare Dashboard → R2 → Overview, tạo bucket. Tại Manage R2 API Tokens, tạo token <b>Object Read &amp; Write</b> và giới hạn vào đúng bucket. Giữ token ở server, không chia sẻ với người dùng.</span><a href="https://developers.cloudflare.com/r2/get-started/s3/" target="_blank" rel="noreferrer">Hướng dẫn tạo bucket, endpoint và S3 credentials ↗</a><a href="https://developers.cloudflare.com/r2/api/tokens/" target="_blank" rel="noreferrer">Chi tiết quyền và token R2 ↗</a></div>
        <div className="admin-r2-fields">
          <label>Account ID<input value={form.accountId} onChange={event => updateAccountId(event.target.value)} placeholder="Account ID trong R2 Overview" autoComplete="off" /></label>
          <label>Bucket<input value={form.bucket} onChange={event => updateField("bucket", event.target.value)} placeholder="cinemora-media" autoComplete="off" /></label>
          <label>Access Key ID<small>{settings.data?.hasAccessKeyId ? "Đã lưu an toàn; để trống để giữ nguyên." : "Nhập Access Key ID của R2."}</small><input value={form.accessKeyId} onChange={event => updateField("accessKeyId", event.target.value)} placeholder={settings.data?.hasAccessKeyId ? "Đã cấu hình · nhập mới nếu muốn thay" : "R2 Access Key ID"} autoComplete="off" /></label>
          <label>Secret Access Key<small>{settings.data?.hasSecretAccessKey ? "Không hiển thị secret đã lưu; để trống để giữ nguyên." : "Nhập Secret Access Key mới từ Cloudflare."}</small><input type="password" value={form.secretAccessKey} onChange={event => updateField("secretAccessKey", event.target.value)} placeholder={settings.data?.hasSecretAccessKey ? "Đã cấu hình · nhập mới nếu muốn thay" : "R2 Secret Access Key"} autoComplete="new-password" /></label>
          <label className="is-wide">S3 API endpoint<input value={form.endpoint} onChange={event => updateField("endpoint", event.target.value)} placeholder="https://ACCOUNT_ID.r2.cloudflarestorage.com" autoComplete="url" /></label>
        </div>
        <div className="admin-r2-note"><KeyRound size={14} /><span>Endpoint mặc định là <b>https://ACCOUNT_ID.r2.cloudflarestorage.com</b>. Nếu bucket thuộc jurisdiction riêng (EU/US/FedRAMP), dùng endpoint tương ứng của Cloudflare.</span></div>
        {!encryptionReady && <div className="admin-r2-warning"><ShieldCheck size={15} /><span>Trước khi lưu credentials, đặt biến môi trường <code>R2_SETTINGS_ENCRYPTION_KEY</code> trong cấu hình Node.js cPanel (chuỗi bí mật ổn định, tối thiểu 32 ký tự), rồi restart. Không thay đổi khóa sau khi đã lưu R2 credentials.</span></div>}
        <div className="admin-r2-actions"><button type="button" className="button button-ghost" disabled={saveSettings.isPending || testConnection.isPending} onClick={() => void saveAndTest()}><TestTube2 size={14} /> {saveSettings.isPending || testConnection.isPending ? "Đang lưu & kiểm tra…" : "Lưu & kiểm tra kết nối"}</button><button type="button" className="button button-primary" disabled={saveSettings.isPending} onClick={() => void saveConfiguration()}><Save size={14} /> {saveSettings.isPending ? "Đang lưu…" : "Lưu cấu hình"}</button></div>
      </div>

      <div className="admin-r2-card">
        <div className="admin-r2-card-heading"><span className="admin-r2-icon"><LinkIcon size={17} /></span><div><strong>Phục vụ ảnh & tệp</strong><small>Public media và dữ liệu riêng được tách namespace.</small></div></div>
        <div className="admin-r2-fields">
          <label>Storage region<input value={form.region} onChange={event => updateField("region", event.target.value)} placeholder="auto" /></label>
          <label className="is-wide">Public base URL <span className="optional-label">(tuỳ chọn)</span><input value={form.publicBaseUrl} onChange={event => updateField("publicBaseUrl", event.target.value)} placeholder="https://cdn.example.com/cinemora" autoComplete="url" /></label>
        </div>
        <p className="admin-r2-field-hint">Để trống Public base URL nếu chưa cấu hình custom domain/public bucket; ảnh public sẽ được phục vụ qua endpoint của website. Chỉ điền khi domain đã trỏ đến vùng public của R2. Media chat và bản backup luôn ở vùng private, không dùng public URL.</p>
        <div className="admin-r2-guide"><strong>Thiết lập backup tự động trên cPanel</strong><ol><li>Trong <b>Setup Node.js App → Environment variables</b>, thêm <code>R2_SETTINGS_ENCRYPTION_KEY</code> là chuỗi ngẫu nhiên ổn định ít nhất 32 byte; restart Node.js app sau khi lưu.</li><li>Nhập endpoint, bucket và R2 API credentials ở bên trái, sau đó bấm <b>Lưu &amp; kiểm tra kết nối</b>. Kiểm tra sẽ upload, đọc lại và xóa một object tạm.</li><li>Bật lịch hàng ngày/hàng tuần, chọn giờ UTC rồi bấm <b>Lưu lịch</b>. Tiến trình Node.js phải tiếp tục chạy để scheduler thực thi.</li><li>Nút <b>Backup ngay</b> dùng <code>mysqldump</code> có sẵn trên máy chủ, nén SQL và ghi backup private vào prefix <code>backups/</code>.</li></ol></div>
        <div className="admin-r2-schedule">
          <div><strong>Lịch tự động</strong><small>Thời gian được tính theo UTC.</small></div>
          <label className="admin-switch"><input type="checkbox" checked={schedule.enabled} disabled={!r2Ready} onChange={event => setSchedule(current => ({ ...current, enabled: event.target.checked }))} /><span /></label>
          <select value={schedule.frequency} onChange={event => setSchedule(current => ({ ...current, frequency: event.target.value as BackupFrequency }))} disabled={!schedule.enabled || !r2Ready}><option value="daily">Hàng ngày</option><option value="weekly">Hàng tuần</option></select>
          <label className="admin-r2-hour">Giờ UTC<input type="number" min={0} max={23} value={schedule.scheduleHourUtc} disabled={!schedule.enabled || !r2Ready} onChange={event => setSchedule(current => ({ ...current, scheduleHourUtc: Number(event.target.value) }))} /></label>
          <button type="button" className="button button-ghost" disabled={updateBackupSchedule.isPending || !r2Ready} onClick={() => void saveSchedule()}><Save size={13} /> Lưu lịch</button>
        </div>
        <div className="admin-r2-retention"><strong>Giữ lại backup</strong><span>Backup không tự xóa để tránh mất dữ liệu. Nếu muốn giới hạn thời gian lưu, tạo lifecycle rule trong cài đặt bucket Cloudflare R2 cho prefix <code>backups/</code>; kiểm tra chính sách khôi phục trước khi bật xóa tự động.</span><a href="https://developers.cloudflare.com/r2/buckets/object-lifecycles/" target="_blank" rel="noreferrer">Hướng dẫn R2 Object Lifecycle</a></div>
      </div>
    </section>

    <section className="admin-r2-status-card">
      <div className="admin-r2-status-heading"><div><span className="eyebrow">BACKUP STATUS</span><h2>Trạng thái database backup</h2></div><button className="button button-primary" disabled={runBackup.isPending || Boolean(status?.running) || !r2Ready} onClick={() => void backupNow()}><DatabaseBackup size={14} /> {runBackup.isPending || status?.running ? "Đang chuẩn bị…" : "Backup ngay"}</button></div>
      <div className="admin-r2-status-grid">
        <div><span>Trạng thái</span><strong className={`admin-r2-status admin-r2-status--${latest?.status || "idle"}`}><CheckCircle2 size={14} />{statusLabel}</strong></div>
        <div><span>Backup gần nhất (giờ Việt Nam)</span><strong>{formatDate(lastBackupAt)}</strong></div>
        <div><span>Kích thước</span><strong>{formatBytes(latest?.byteSize)}</strong></div>
        <div><span>Lỗi gần nhất</span><strong className={latest?.errorMessage ? "has-error" : ""}>{latest?.errorMessage || "Không có lỗi"}</strong></div>
      </div>
      {!credentialsReady && <p className="admin-r2-field-hint">Chưa có R2 credentials được lưu. Hãy lưu cấu hình rồi dùng “Lưu & kiểm tra kết nối” trước khi chạy backup.</p>}
      {!r2Ready && <p className="admin-r2-field-hint">Lịch backup sẽ chỉ hoạt động sau khi endpoint, bucket và credentials hợp lệ; hãy dùng nút kiểm tra kết nối trước.</p>}
      {credentialsReady && <p className="admin-r2-field-hint">Backup dùng <code>mysqldump</code> trên máy chủ Node.js; nếu không có lệnh này, backend sẽ đánh dấu backup thất bại và hiển thị lý do.</p>}
    </section>
  </main></PageShell>;
}
