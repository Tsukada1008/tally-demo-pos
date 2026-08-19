"use client";

import { useState } from "react";
import { createClient } from "../../../lib/supabase/client";
import "../auth.css";

export default function AuthErrorPage() {
  const [status, setStatus] = useState<"idle" | "sending" | "sent">("idle");
  const [error, setError] = useState("");

  const resend = async () => {
    if (status === "sending") return;
    setStatus("sending");
    setError("");

    try {
      const request = createClient().auth.resetPasswordForEmail(
        "lethal.weapon@outlook.jp",
        { redirectTo: `${window.location.origin}/auth/update-password` },
      );
      const timeout = new Promise<never>((_, reject) =>
        window.setTimeout(
          () => reject(new Error("timeout")),
          15000,
        ),
      );
      const { error: sendError } = await Promise.race([request, timeout]);
      if (sendError) throw sendError;
      setStatus("sent");
    } catch (sendError) {
      console.error("Password reset email failed", sendError);
      setStatus("idle");
      setError(
        "メールを送信できませんでした。通信を確認し、少し時間を空けてもう一度押してください。",
      );
    }
  };

  return (
    <main className="auth-page">
      <section className="auth-card">
        <span>LINK ERROR</span>
        <h1>招待リンクの期限が切れています</h1>
        <p>
          古いメールのリンクは使用できません。新しいパスワード設定メールを発行してください。
        </p>
        {status === "sent" ? (
          <div
            className="auth-error"
            style={{ borderColor: "#0a755f", background: "#dff2eb", color: "#075c4b" }}
          >
            再設定メールを送信しました。最新のメールを確認してください。
          </div>
        ) : (
          <button type="button" onClick={resend} disabled={status === "sending"}>
            {status === "sending" ? "送信しています…" : "新しい設定メールを送る"}
          </button>
        )}
        {error && <div className="auth-error">{error}</div>}
      </section>
    </main>
  );
}
