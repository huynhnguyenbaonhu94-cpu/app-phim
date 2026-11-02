import { memo, useState } from "react";
import { CircleAlert, Cloud, KeyRound, Loader2, RefreshCw } from "lucide-react";
import { Area, AreaChart, Bar, BarChart, CartesianGrid, Legend, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { toast } from "sonner";
import { trpc } from "@/lib/trpc";

type Props = { configured: boolean; hasToken: boolean };
type AnalyticsPeriod = "monthToDate" | "last7Days" | "last30Days";
const periodLabels: Record<AnalyticsPeriod, string> = {
  monthToDate: "Tháng này đến hiện tại",
  last7Days: "7 ngày gần nhất",
  last30Days: "30 ngày gần nhất",
};

function formatDate(value: string | Date | null | undefined) {
  if (!value) return "chưa có mẫu";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "chưa có mẫu" : date.toLocaleString("vi-VN", { timeZone: "Asia/Ho_Chi_Minh" });
}

// Cloudflare displays R2 capacity using decimal units (1 GB = 1,000,000,000 bytes).
function formatUsageBytes(value?: number | null) {
  if (value === null || value === undefined || !Number.isFinite(value)) return "—";
  if (value < 1000) return `${Math.round(value)} B`;
  const units = ["KB", "MB", "GB", "TB", "PB"];
  let amount = value;
  let unit = "B";
  for (const next of units) { amount /= 1000; unit = next; if (amount < 1000) break; }
  return `${amount.toLocaleString("vi-VN", { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ${unit}`;
}

function formatUsageCount(value?: number | null) {
  return value === null || value === undefined ? "—" : Math.round(value).toLocaleString("vi-VN");
}

const chartTooltipStyle = { background: "#131720", border: "1px solid #343a47", borderRadius: 10 };
const storageFormatter = (value: unknown) => formatUsageBytes(Number(value));
const countFormatter = (value: unknown) => formatUsageCount(Number(value));
const dateLabel = (value: unknown) => String(value);
const shortDateLabel = (value: unknown) => String(value).slice(5);
const tickCount = (value: unknown) => Number(value).toLocaleString("vi-VN");

const AdminR2AnalyticsPanel = memo(function AdminR2AnalyticsPanel({ configured, hasToken }: Props) {
  const [period, setPeriod] = useState<AnalyticsPeriod>("monthToDate");
  const periodLabel = periodLabels[period];
  const analyticsQuery = trpc.adminR2.getAnalytics.useQuery({ period }, {
    enabled: configured && hasToken,
    retry: false,
    staleTime: 0,
    refetchOnMount: "always",
    refetchOnWindowFocus: false,
    refetchOnReconnect: false,
  });
  const data = analyticsQuery.data;

  async function refreshAnalytics() {
    const result = await analyticsQuery.refetch({ cancelRefetch: true });
    if (result.error) {
      toast.error("Không lấy được thống kê R2", { description: result.error.message });
      return;
    }
    if (result.data) {
      toast.success("Đã truy vấn Cloudflare Analytics", {
        description: `Mẫu storage mới nhất: ${formatDate(result.data.sourceTimestamps.storage)}. Cloudflare có thể cập nhật số liệu trễ.`,
      });
    }
  }

  const operationTotal = (value: number) => `${data?.completeness.operationsLimitReached ? "≥ " : ""}${formatUsageCount(value)}`;

  return <section className="admin-r2-status-card admin-r2-analytics-card">
    <div className="admin-r2-status-heading">
      <div><span className="eyebrow">CLOUDFLARE ANALYTICS · {periodLabel.toUpperCase()} · GMT+7</span><h2>Thống kê R2 Object Storage</h2><p>Chọn cùng khoảng thời gian để đối chiếu với Cloudflare; tổng request được cộng gộp theo ngày và loại thao tác.</p></div>
      <div className="admin-r2-analytics-actions">
        <label className="admin-r2-analytics-period"><span>Khoảng thời gian</span><select aria-label="Khoảng thời gian thống kê R2" value={period} onChange={(event) => setPeriod(event.target.value as AnalyticsPeriod)}>
          <option value="monthToDate">Tháng này đến hiện tại</option>
          <option value="last7Days">7 ngày gần nhất</option>
          <option value="last30Days">30 ngày gần nhất</option>
        </select></label>
        <button type="button" className="button button-ghost" disabled={!hasToken || analyticsQuery.isFetching} onClick={() => void refreshAnalytics()}>
          <RefreshCw size={14} className={analyticsQuery.isFetching ? "admin-r2-refresh-spinning" : undefined} /> {analyticsQuery.isFetching ? "Đang truy vấn Cloudflare…" : "Làm mới số liệu"}
        </button>
      </div>
    </div>
    {!configured ? <div className="admin-r2-analytics-empty"><Cloud size={18} /><div><strong>Cần cấu hình R2 trước</strong><p>Lưu và kiểm tra endpoint, bucket cùng credentials ở phần cấu hình phía trên trước khi truy vấn thống kê.</p></div></div>
      : !hasToken ? <div className="admin-r2-analytics-empty"><KeyRound size={18} /><div><strong>Cần token Analytics chỉ đọc riêng</strong><p>Nhập Cloudflare API token có quyền <b>Account → Account Analytics → Read</b> ở phần cấu hình phía trên, rồi lưu. Token R2 S3 không dùng để gọi Analytics.</p><a href="https://developers.cloudflare.com/analytics/graphql-api/getting-started/authentication/api-token-auth/" target="_blank" rel="noreferrer">Hướng dẫn tạo API token Analytics ↗</a></div></div>
        : analyticsQuery.error ? <p className="admin-r2-backfill-error"><CircleAlert size={15} /> Không tải được Cloudflare Analytics: {analyticsQuery.error.message}</p>
          : !data ? <div className="admin-r2-analytics-empty"><Loader2 size={17} /> Đang tải số liệu analytics…</div>
            : <>
              {analyticsQuery.isFetching && <p className="admin-r2-analytics-loading"><Loader2 size={14} /> Đang lấy mẫu mới từ Cloudflare; số liệu cũ vẫn được giữ đến khi truy vấn hoàn tất.</p>}
              <div className="admin-r2-analytics-kpis">
                <div><span>Dung lượng ở mẫu storage mới nhất</span><strong>{formatUsageBytes(data.current.storageBytes)}</strong></div>
                <div><span>Đỉnh storage trung bình mỗi ngày · GMT+7</span><strong>{formatUsageBytes(data.averages.storageBytes)}</strong></div>
                <div><span>Objects ở mẫu mới nhất</span><strong>{formatUsageCount(data.current.objectCount)}</strong></div>
                <div><span>Class A requests · {periodLabel}</span><strong>{operationTotal(data.totals.classA)}</strong></div>
                <div><span>Class B requests · {periodLabel}</span><strong>{operationTotal(data.totals.classB)}</strong></div>
                <div><span>Upload / download · {periodLabel}</span><strong>{formatUsageBytes(data.totals.uploadBytes)} / {formatUsageBytes(data.totals.downloadBytes)}</strong></div>
              </div>
              <p className="admin-r2-analytics-status-breakdown"><strong>Trạng thái request:</strong> {formatUsageCount(data.totals.requestStatuses.success)} thành công · {formatUsageCount(data.totals.requestStatuses.userError)} lỗi người dùng · {formatUsageCount(data.totals.requestStatuses.internalError)} lỗi nội bộ · {formatUsageCount(data.totals.requestStatuses.unknown)} không rõ.</p>
              {(data.totals.freeOperations > 0 || data.totals.otherOperations > 0) && <p className="admin-r2-analytics-status-breakdown"><strong>Ngoài Class A/B:</strong> {formatUsageCount(data.totals.freeOperations)} thao tác miễn phí · {formatUsageCount(data.totals.otherOperations)} thao tác chưa phân loại.</p>}
              {(data.completeness.operationsLimitReached || data.completeness.storageLimitReached || data.completeness.bandwidthLimitReached) && <p className="admin-r2-analytics-warning"><CircleAlert size={14} /> {data.completeness.operationsLimitReached ? "Một ngày chạm giới hạn nhóm thao tác; Class A/B được đánh dấu là số tối thiểu (≥), không phải tổng đầy đủ. " : ""}{data.completeness.storageLimitReached || data.completeness.bandwidthLimitReached ? "Một tập dữ liệu khác chạm giới hạn dòng; xem timestamp và lưu ý về độ đầy đủ bên dưới." : ""}</p>}
              <div className="admin-r2-analytics-chart-grid">
                <article className="admin-r2-analytics-chart"><h3>Storage theo ngày</h3><small>Đỉnh dung lượng payload + metadata của mỗi ngày GMT+7</small><div className="admin-r2-chart"><ResponsiveContainer width="100%" height="100%"><AreaChart data={data.daily}><CartesianGrid strokeDasharray="3 3" stroke="#252936" /><XAxis dataKey="date" tickFormatter={shortDateLabel} stroke="#858b9a" /><YAxis width={68} tickFormatter={storageFormatter} stroke="#858b9a" /><Tooltip formatter={storageFormatter} labelFormatter={dateLabel} contentStyle={chartTooltipStyle} /><Area type="monotone" dataKey="storageBytes" name="Đỉnh storage" stroke="#c1ed62" fill="#a4d651" fillOpacity={0.16} connectNulls /></AreaChart></ResponsiveContainer></div></article>
                <article className="admin-r2-analytics-chart"><h3>Class A / Class B operations</h3><small>Số request mỗi ngày · {periodLabel} · GMT+7</small><div className="admin-r2-chart"><ResponsiveContainer width="100%" height="100%"><AreaChart data={data.daily}><CartesianGrid strokeDasharray="3 3" stroke="#252936" /><XAxis dataKey="date" tickFormatter={shortDateLabel} stroke="#858b9a" /><YAxis width={58} tickFormatter={tickCount} stroke="#858b9a" /><Tooltip formatter={countFormatter} labelFormatter={dateLabel} contentStyle={chartTooltipStyle} /><Legend /><Area type="monotone" dataKey="classA" name="Class A" stroke="#ffbd59" fill="#ffbd59" fillOpacity={0.13} /><Area type="monotone" dataKey="classB" name="Class B" stroke="#7bc9ff" fill="#7bc9ff" fillOpacity={0.13} /></AreaChart></ResponsiveContainer></div></article>
                <article className="admin-r2-analytics-chart admin-r2-analytics-chart--wide"><h3>Request Distribution</h3><small>Phân bổ theo loại thao tác; thao tác không nhận diện được được giữ trong “Khác”</small><div className="admin-r2-chart"><ResponsiveContainer width="100%" height="100%"><BarChart data={data.distribution.slice(0, 10)} layout="vertical" margin={{ left: 8, right: 20 }}><CartesianGrid strokeDasharray="3 3" stroke="#252936" /><XAxis type="number" tickFormatter={tickCount} stroke="#858b9a" /><YAxis type="category" dataKey="actionType" width={178} tick={{ fontSize: 11 }} stroke="#858b9a" /><Tooltip formatter={countFormatter} contentStyle={chartTooltipStyle} /><Bar dataKey="requests" name="Requests" fill="#c1ed62" radius={[0, 5, 5, 0]} /></BarChart></ResponsiveContainer></div></article>
              </div>
              <div className="admin-r2-analytics-freshness">
                <span>Khoảng dữ liệu GMT+7: {formatDate(data.range.from)} – {formatDate(data.range.to)}</span>
                <span>Mẫu mới nhất · Storage: {formatDate(data.sourceTimestamps.storage)} · Operations: {formatDate(data.sourceTimestamps.operations)} · Bandwidth: {formatDate(data.sourceTimestamps.bandwidth)}</span>
                <span>Truy vấn Cloudflare hoàn tất lúc: {formatDate(data.collectedAt)}. Bấm làm mới gửi truy vấn mới; thời điểm mẫu có thể không đổi nếu Cloudflare chưa cập nhật dataset.</span>
              </div>
              <p className="admin-r2-analytics-note">{data.note} Băng thông không bao gồm từng lượt truyền dưới 100 KiB theo giới hạn dataset Cloudflare.</p>
            </>}
  </section>;
});

export default AdminR2AnalyticsPanel;
