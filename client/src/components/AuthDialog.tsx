import { Eye, EyeOff, LockKeyhole, Mail, UserRound, X } from "lucide-react";
import { FormEvent, useState } from "react";
import { trpc } from "@/lib/trpc";

type AuthDialogProps = { open: boolean; onClose: () => void };

export function AuthDialog({ open, onClose }: AuthDialogProps) {
  const [mode, setMode] = useState<"login" | "register">("login");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState("");
  const utils = trpc.useUtils();
  const login = trpc.auth.login.useMutation({ onSuccess: async () => { await utils.auth.me.invalidate(); onClose(); } });
  const register = trpc.auth.register.useMutation({ onSuccess: async () => { await utils.auth.me.invalidate(); onClose(); } });
  const pending = login.isPending || register.isPending;

  if (!open) return null;

  function switchMode(next: "login" | "register") {
    setMode(next);
    setError("");
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError("");
    try {
      if (mode === "register") await register.mutateAsync({ name, email, password });
      else await login.mutateAsync({ email, password });
    } catch (cause: any) {
      setError(cause?.message || "Không thể thực hiện lúc này. Vui lòng thử lại.");
    }
  }

  return <div className="auth-dialog-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
    <section className="auth-dialog" role="dialog" aria-modal="true" aria-labelledby="auth-dialog-title">
      <button type="button" className="auth-dialog-close" onClick={onClose} aria-label="Đóng"><X size={17} /></button>
      <div className="auth-dialog-mark"><UserRound size={22} /></div>
      <span className="eyebrow">CINEMORA ACCOUNT</span>
      <h2 id="auth-dialog-title">{mode === "login" ? "Chào mừng trở lại." : "Tạo tài khoản mới."}</h2>
      <p>{mode === "login" ? "Đăng nhập để tiếp tục lịch sử xem và danh sách yêu thích." : "Đăng ký bằng email của bạn, không cần tài khoản bên thứ ba."}</p>
      <div className="auth-tabs" role="tablist"><button type="button" className={mode === "login" ? "active" : ""} onClick={() => switchMode("login")}>Đăng nhập</button><button type="button" className={mode === "register" ? "active" : ""} onClick={() => switchMode("register")}>Đăng ký</button></div>
      <form onSubmit={submit} className="auth-form">
        {mode === "register" && <label><span>Họ và tên</span><div className="auth-input"><UserRound size={15} /><input value={name} onChange={(event) => setName(event.target.value)} autoComplete="name" placeholder="Nguyễn Văn A" required minLength={2} maxLength={80} /></div></label>}
        <label><span>Email</span><div className="auth-input"><Mail size={15} /><input value={email} onChange={(event) => setEmail(event.target.value)} autoComplete="email" type="email" placeholder="ban@example.com" required /></div></label>
        <label><span>Mật khẩu</span><div className="auth-input"><LockKeyhole size={15} /><input value={password} onChange={(event) => setPassword(event.target.value)} autoComplete={mode === "login" ? "current-password" : "new-password"} type={showPassword ? "text" : "password"} placeholder="Ít nhất 8 ký tự" required minLength={mode === "register" ? 8 : 1} maxLength={128} /><button type="button" onClick={() => setShowPassword((visible) => !visible)} aria-label={showPassword ? "Ẩn mật khẩu" : "Hiện mật khẩu"}>{showPassword ? <EyeOff size={15} /> : <Eye size={15} />}</button></div></label>
        {error && <div className="auth-error" role="alert">{error}</div>}
        <button className="button button-primary auth-submit" type="submit" disabled={pending}>{pending ? "Đang xử lý..." : mode === "login" ? "Đăng nhập" : "Tạo tài khoản"}</button>
      </form>
      <small className="auth-security-note">Mật khẩu được mã hóa an toàn và không bao giờ hiển thị trong trình duyệt.</small>
    </section>
  </div>;
}
