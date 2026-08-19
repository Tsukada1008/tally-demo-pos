"use client";

import { FormEvent, useState } from "react";
import { CheckCircle2, LockKeyhole } from "lucide-react";
import { createClient } from "../../../lib/supabase/client";
import "../auth.css";

export default function UpdatePasswordPage() {
  const appName = process.env.NEXT_PUBLIC_APP_ENV === "demo" ? "Tally" : "TIPSY";
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [error, setError] = useState("");
  const [done, setDone] = useState(false);
  const submit = async (event: FormEvent) => {
    event.preventDefault(); setError("");
    if (password.length < 12) return setError("パスワードは12文字以上にしてください。");
    if (password !== confirm) return setError("確認用パスワードが一致しません。");
    const { error } = await createClient().auth.updateUser({ password });
    if (error) return setError("リンクの有効期限が切れているか、設定に失敗しました。");
    setDone(true);
  };
  return <main className="auth-page"><section className="auth-card">{done?<><CheckCircle2 className="auth-success"/><span>SETUP COMPLETE</span><h1>設定が完了しました</h1><p>管理者パスワードを安全に保存しました。</p><a href="/">{appName}を開く</a></>:<><div className="auth-icon"><LockKeyhole/></div><span>OWNER ACCOUNT</span><h1>管理者パスワード設定</h1><p>英大文字・小文字・数字を組み合わせた12文字以上を推奨します。</p><form onSubmit={submit}><label>新しいパスワード</label><input type="password" autoComplete="new-password" value={password} onChange={e=>setPassword(e.target.value)}/><label>確認用パスワード</label><input type="password" autoComplete="new-password" value={confirm} onChange={e=>setConfirm(e.target.value)}/>{error&&<div className="auth-error">{error}</div>}<button>パスワードを設定する</button></form></>}</section></main>;
}
