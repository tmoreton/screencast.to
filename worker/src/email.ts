import type { Env } from "./env";

const DEFAULT_REPLY_TO = "support@screencast.to";

interface PurchaseEmailConfiguration {
  binding: SendEmail;
  from: string;
  replyTo: string;
}

function configuredValue(value: string | undefined, maximum: number): string | null {
  if (typeof value !== "string" || value.length > maximum || /[\x00-\x1f\x7f]/.test(value)) return null;
  return value.trim() || null;
}

function validEmail(value: string | undefined): string | null {
  const email = configuredValue(value, 254);
  return email && /^[^\s@<>,;:\"]+@[^\s@<>,;:\"]+\.[^\s@<>,;:\"]+$/.test(email) ? email : null;
}

function configuration(env: Env): PurchaseEmailConfiguration | null {
  if (env.PURCHASE_EMAIL_ENABLED !== "true" || typeof env.PURCHASE_EMAIL?.send !== "function") return null;
  const from = validEmail(env.PURCHASE_EMAIL_FROM);
  const replyTo = env.PURCHASE_EMAIL_REPLY_TO?.trim()
    ? validEmail(env.PURCHASE_EMAIL_REPLY_TO) : DEFAULT_REPLY_TO;
  if (!from || !replyTo) return null;
  return { binding: env.PURCHASE_EMAIL, from, replyTo };
}

export function isPurchaseEmailConfigured(env: Env): boolean {
  return configuration(env) !== null;
}

function validatedRestoreURL(value: string): string {
  if (value.length > 16_384) throw new Error("Invalid purchase restore URL.");
  let url: URL;
  try { url = new URL(value); }
  catch { throw new Error("Invalid purchase restore URL."); }
  const parameters = ["restore", "code_challenge", "state"];
  const restore = url.searchParams.get("restore");
  const challenge = url.searchParams.get("code_challenge");
  const state = url.searchParams.get("state");
  const bindingValid = challenge === null && state === null ||
    challenge !== null && /^[A-Za-z0-9_-]{43}$/.test(challenge) &&
    state !== null && /^[A-Za-z0-9_-]{32,128}$/.test(state);
  if (url.origin !== "https://screencast.to" || url.pathname !== "/connect-sharing.html" ||
      url.username || url.password || url.hash ||
      !restore || !/^[A-Za-z0-9_-]{43}$/.test(restore) || !bindingValid ||
      parameters.some((key) => url.searchParams.getAll(key).length > 1) ||
      [...url.searchParams.keys()].some((key) => !parameters.includes(key))) {
    throw new Error("Invalid purchase restore URL.");
  }
  return url.href;
}

function htmlEscape(value: string): string {
  return value.replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[character]!);
}

/** Only called after an explicit restore request and purchase verification. */
export async function sendPurchaseRestoreEmail(env: Env, to: string, restoreURL: string): Promise<void> {
  const settings = configuration(env);
  if (!settings) throw new Error("Purchase email delivery is not configured.");
  const recipient = validEmail(to);
  if (!recipient) throw new Error("Invalid purchase email recipient.");
  const url = validatedRestoreURL(restoreURL);
  const safeURL = htmlEscape(url);
  const safeReplyTo = htmlEscape(settings.replyTo);
  const message = {
    from: { email: settings.from, name: "Screencast.to" },
    to: [recipient],
    replyTo: settings.replyTo,
    subject: "Connect sharing in Screencast.to",
    text: [
      "You requested access to temporary sharing for your Screencast.to website purchase.",
      "Open this private link on the Mac where you requested sharing access:",
      url,
      "This link expires shortly. Keep it private and do not forward it.",
      "If you did not request this email, you can ignore it.",
      `Need help? Reply to this email or contact ${settings.replyTo}.`,
    ].join("\n\n"),
    html: `<!doctype html><html><body style="margin:0;background:#f5f0e6;color:#181816;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif"><div style="max-width:560px;margin:0 auto;padding:40px 24px"><div style="font-size:28px;font-weight:800">Screencast.to</div><h1 style="font-size:30px;line-height:1.15;margin:28px 0 16px">Connect temporary sharing</h1><p style="font-size:16px;line-height:1.6">You requested sharing access for your Screencast.to website purchase. Open this private link on the Mac where you made the request.</p><p style="margin:28px 0"><a href="${safeURL}" style="display:inline-block;background:#f0444d;color:#ffffff;text-decoration:none;font-weight:700;padding:14px 20px">Connect sharing</a></p><p style="font-size:14px;line-height:1.6">This link expires shortly. Keep it private and do not forward it. If you did not request this email, you can ignore it.</p><p style="font-size:14px;line-height:1.6">Need help? Reply to this email or contact <a href="mailto:${safeReplyTo}">${safeReplyTo}</a>.</p></div></body></html>`,
  };
  try {
    const result = await settings.binding.send(message);
    if (!result || typeof result.messageId !== "string" || !result.messageId) throw new Error("Provider response was invalid.");
  } catch {
    // Provider responses and errors can contain the recipient or private link.
    // Never attach them as a cause or expose their body to application logging.
    throw new Error("Purchase restore email could not be sent.");
  }
}
