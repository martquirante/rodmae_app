import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { GoogleAuth } from "npm:google-auth-library";

interface WebhookPayload {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  record: Record<string, unknown>;
  old_record?: Record<string, unknown>;
}

serve(async (req: Request) => {
  // Only allow POST
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  // Optional webhook authorization check
  const authHeader = req.headers.get("authorization");
  const expectedSecret = Deno.env.get("WEBHOOK_SECRET");
  if (expectedSecret && authHeader !== `Bearer ${expectedSecret}`) {
    return new Response("Unauthorized", { status: 401 });
  }

  let payload: WebhookPayload;
  try {
    payload = await req.json();
  } catch {
    return new Response("Bad Request", { status: 400 });
  }

  // Only handle INSERT events
  if (payload.type !== "INSERT") {
    return new Response("OK", { status: 200 });
  }

  const record = payload.record;
  const table = payload.table;

  let title = "RodMae 💕";
  let body = "";
  let type = "general";
  let sender = "Your partner";

  // Build notification content based on table
  if (table === "chat_history") {
    sender = String(record["sender"] ?? "Your partner");
    const message = String(record["message"] ?? "");
    title = `${sender} 💬`;
    body = message;
    type = "chat";
  } else if (table === "surprise_notes") {
    sender = String(record["sender"] ?? "Your partner");
    const content = String(record["content"] ?? "");
    title = `Sweet note from ${sender} 🌸`;
    body = content.length > 80 ? content.slice(0, 80) + "…" : content;
    type = "note";
  } else if (table === "love_triggers") {
    sender = String(record["sender"] ?? "Your partner");
    const triggerType = String(record["trigger_type"] ?? "love signal");
    title = `${sender} sent a love signal! 💕`;
    body = triggerType;
    type = "signal";
  } else {
    title = "RodMae 💕";
    body = "You have a new update!";
    type = "general";
  }

  // Truncate body if too long
  if (body.length > 160) {
    body = body.slice(0, 160) + "…";
  }

  try {
    // 1. Get Firebase Service Account credentials
    const serviceAccountStr = Deno.env.get("FCM_SERVICE_ACCOUNT");
    if (!serviceAccountStr) {
      throw new Error("FCM_SERVICE_ACCOUNT secret is not configured in Supabase");
    }

    const credentials = JSON.parse(serviceAccountStr);
    const projectId = credentials.project_id;
    if (!projectId) {
      throw new Error("Invalid service account: missing 'project_id'");
    }

    // 2. Initialize GoogleAuth and retrieve OAuth2 Access Token
    const auth = new GoogleAuth({
      credentials,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
    const accessToken = await auth.getAccessToken();
    if (!accessToken) {
      throw new Error("Failed to retrieve access token from GoogleAuth");
    }

    // 3. Build FCM HTTP v1 request payload
    const fcmEndpoint = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
    const fcmPayload = {
      message: {
        topic: "couple-rodmae-2026",
        notification: {
          title,
          body,
        },
        data: {
          type,
          title,
          body,
          sender, // Pass sender name to prevent self-notification loops
        },
        android: {
          priority: "HIGH",
          notification: {
            channel_id: "rodmae_love_channel",
            sound: "default",
            notification_priority: "PRIORITY_MAX",
            default_vibrate_timings: true,
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      },
    };

    // 4. Send message to FCM v1 API
    const fcmResponse = await fetch(fcmEndpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${accessToken}`,
      },
      body: JSON.stringify(fcmPayload),
    });

    if (!fcmResponse.ok) {
      const errorText = await fcmResponse.text();
      throw new Error(`FCM API Error: ${fcmResponse.status} - ${errorText}`);
    }

    const result = await fcmResponse.json();
    return new Response(JSON.stringify({ success: true, result }), {
      headers: { "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error: any) {
    console.error("FCM Edge Function Error:", error);
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { "Content-Type": "application/json" },
      status: 500,
    });
  }
});
