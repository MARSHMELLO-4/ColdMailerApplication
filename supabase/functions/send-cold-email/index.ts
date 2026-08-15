import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

type Payload = {
  recipients?: unknown;
  subject?: unknown;
  body?: unknown;
  resumePath?: unknown;
  resumeFileName?: unknown;
  resumeContentType?: unknown;
};

type Attachment = {
  fileName: string;
  contentType: string;
  base64: string;
};

const corsHeaders = {
  'Access-Control-Allow-Origin': Deno.env.get('ALLOWED_ORIGIN') ?? '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (request.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  try {
    const payload = await parsePayload(request);
    const recipients = normalizeRecipients(payload.recipients);
    const subject = requiredString(payload.subject, 'subject');
    const body = requiredString(payload.body, 'body');

    if (recipients.length === 0) {
      return jsonResponse({ error: 'At least one valid recipient is required.' }, 400);
    }

    const supabase = createClient(
      requiredEnv('SUPABASE_URL'),
      requiredEnv('SUPABASE_SERVICE_ROLE_KEY'),
      { auth: { persistSession: false } },
    );

    const accessToken = await getGoogleAccessToken();
    const attachment = await loadAttachment(supabase, payload);
    const fromEmail = requiredEnv('GMAIL_FROM_EMAIL');
    const fromName = Deno.env.get('GMAIL_FROM_NAME') ?? '';
    const results = [];

    for (const recipient of recipients) {
      const personalizedSubject = personalize(subject, recipient);
      const personalizedBody = personalize(body, recipient);

      try {
        const gmailResult = await sendGmailMessage({
          accessToken,
          fromEmail,
          fromName,
          toEmail: recipient,
          subject: personalizedSubject,
          body: personalizedBody,
          attachment,
        });

        await recordDelivery(supabase, {
          recipient,
          subject: personalizedSubject,
          body: personalizedBody,
          resumePath: stringOrNull(payload.resumePath),
          status: 'sent',
          providerMessageId: gmailResult.id ?? null,
          errorMessage: null,
        });

        results.push({
          recipient,
          status: 'sent',
          providerMessageId: gmailResult.id ?? null,
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);

        await recordDelivery(supabase, {
          recipient,
          subject: personalizedSubject,
          body: personalizedBody,
          resumePath: stringOrNull(payload.resumePath),
          status: 'failed',
          providerMessageId: null,
          errorMessage: message,
        });

        results.push({ recipient, status: 'failed', error: message });
      }
    }

    const sent = results.filter((result) => result.status === 'sent').length;

    return jsonResponse({
      sent,
      failed: results.length - sent,
      results,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: message }, 500);
  }
});

async function parsePayload(request: Request): Promise<Payload> {
  try {
    return await request.json();
  } catch {
    throw new Error('Request body must be valid JSON.');
  }
}

function normalizeRecipients(value: unknown): string[] {
  const rawItems = Array.isArray(value)
    ? value
    : typeof value === 'string'
      ? value.split(/[\s,;]+/)
      : [];

  const seen = new Set<string>();
  const recipients: string[] = [];

  for (const item of rawItems) {
    const email = String(item).trim().toLowerCase();
    if (!isValidEmail(email) || seen.has(email)) {
      continue;
    }

    seen.add(email);
    recipients.push(email);
  }

  return recipients;
}

function isValidEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

function requiredString(value: unknown, field: string): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error(`${field} is required.`);
  }

  return value.trim();
}

function stringOrNull(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0
    ? value.trim()
    : null;
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }

  return value;
}

async function getGoogleAccessToken(): Promise<string> {
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: requiredEnv('GOOGLE_CLIENT_ID'),
      client_secret: requiredEnv('GOOGLE_CLIENT_SECRET'),
      refresh_token: requiredEnv('GOOGLE_REFRESH_TOKEN'),
      grant_type: 'refresh_token',
    }),
  });

  const data = await response.json();

  if (!response.ok || !data.access_token) {
    throw new Error(`Google OAuth failed: ${JSON.stringify(data)}`);
  }

  return data.access_token;
}

async function loadAttachment(
  supabase: ReturnType<typeof createClient>,
  payload: Payload,
): Promise<Attachment | null> {
  const resumePath = stringOrNull(payload.resumePath);

  if (!resumePath) {
    return null;
  }

  const bucket = Deno.env.get('SUPABASE_RESUME_BUCKET') ?? 'resume_uploads';
  const { data, error } = await supabase.storage.from(bucket).download(resumePath);

  if (error || !data) {
    throw new Error(`Unable to download resume: ${error?.message ?? 'unknown error'}`);
  }

  const bytes = new Uint8Array(await data.arrayBuffer());

  return {
    fileName: stringOrNull(payload.resumeFileName) ?? 'resume.pdf',
    contentType: stringOrNull(payload.resumeContentType) ?? 'application/pdf',
    base64: base64FromBytes(bytes),
  };
}

async function sendGmailMessage(input: {
  accessToken: string;
  fromEmail: string;
  fromName: string;
  toEmail: string;
  subject: string;
  body: string;
  attachment: Attachment | null;
}): Promise<{ id?: string }> {
  const raw = buildMimeMessage(input);

  const response = await fetch(
    'https://gmail.googleapis.com/gmail/v1/users/me/messages/send',
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${input.accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ raw }),
    },
  );

  const data = await response.json();

  if (!response.ok) {
    throw new Error(`Gmail send failed: ${JSON.stringify(data)}`);
  }

  return data;
}

function buildMimeMessage(input: {
  fromEmail: string;
  fromName: string;
  toEmail: string;
  subject: string;
  body: string;
  attachment: Attachment | null;
}): string {
  const boundary = `cold_mailer_${crypto.randomUUID()}`;
  const lines = [
    `From: ${formatAddress(input.fromName, input.fromEmail)}`,
    `To: ${input.toEmail}`,
    `Subject: ${mimeEncodeHeader(input.subject)}`,
    'MIME-Version: 1.0',
    `Content-Type: multipart/mixed; boundary="${boundary}"`,
    '',
    `--${boundary}`,
    'Content-Type: text/plain; charset="UTF-8"',
    'Content-Transfer-Encoding: 8bit',
    '',
    input.body,
    '',
  ];

  if (input.attachment) {
    const fileName = sanitizeHeaderValue(input.attachment.fileName);
    lines.push(
      `--${boundary}`,
      `Content-Type: ${input.attachment.contentType}; name="${fileName}"`,
      `Content-Disposition: attachment; filename="${fileName}"`,
      'Content-Transfer-Encoding: base64',
      '',
      wrapBase64(input.attachment.base64),
      '',
    );
  }

  lines.push(`--${boundary}--`, '');

  return base64UrlEncode(lines.join('\r\n'));
}

function personalize(value: string, recipient: string): string {
  const localPart = recipient.split('@')[0] ?? '';
  const firstName = localPart
    .split(/[._-]/)
    .filter(Boolean)[0] ?? 'there';

  return value
    .replaceAll('{{email}}', recipient)
    .replaceAll('{{first_name}}', capitalize(firstName));
}

function capitalize(value: string): string {
  if (value.length === 0) {
    return value;
  }

  return `${value[0].toUpperCase()}${value.slice(1)}`;
}

function formatAddress(name: string, email: string): string {
  const cleanEmail = sanitizeHeaderValue(email);
  if (!name.trim()) {
    return cleanEmail;
  }

  return `${mimeEncodeHeader(name.trim())} <${cleanEmail}>`;
}

function mimeEncodeHeader(value: string): string {
  const clean = sanitizeHeaderValue(value);
  return /[^\x20-\x7E]/.test(clean)
    ? `=?UTF-8?B?${base64FromBytes(new TextEncoder().encode(clean))}?=`
    : clean;
}

function sanitizeHeaderValue(value: string): string {
  return value.replace(/[\r\n"]/g, ' ').trim();
}

function base64UrlEncode(value: string): string {
  return base64FromBytes(new TextEncoder().encode(value))
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replace(/=+$/g, '');
}

function base64FromBytes(bytes: Uint8Array): string {
  let binary = '';
  const chunkSize = 0x8000;

  for (let index = 0; index < bytes.length; index += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(index, index + chunkSize));
  }

  return btoa(binary);
}

function wrapBase64(value: string): string {
  return value.match(/.{1,76}/g)?.join('\r\n') ?? value;
}

async function recordDelivery(
  supabase: ReturnType<typeof createClient>,
  input: {
    recipient: string;
    subject: string;
    body: string;
    resumePath: string | null;
    status: 'sent' | 'failed';
    providerMessageId: string | null;
    errorMessage: string | null;
  },
) {
  const { error } = await supabase.rpc('record_email_delivery', {
    p_recipient_email: input.recipient,
    p_subject: input.subject,
    p_body: input.body,
    p_resume_storage_path: input.resumePath,
    p_status: input.status,
    p_provider_message_id: input.providerMessageId,
    p_error_message: input.errorMessage,
  });

  if (error) {
    throw new Error(`Failed to record email delivery: ${error.message}`);
  }
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  });
}
