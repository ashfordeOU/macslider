// Talks to Monorail's local API (Settings → Automation → Local API).
import { readFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";

const folder = join(homedir(), "Library", "Application Support", "Monorail");

function read(name: string): string {
  try {
    return readFileSync(join(folder, name), "utf8").trim();
  } catch {
    throw new Error("Turn on the local API in Monorail ▸ Settings ▸ Automation.");
  }
}

export async function api<T>(method: "GET" | "POST", path: string, body?: object): Promise<T> {
  const response = await fetch(`http://127.0.0.1:${read("api-port")}${path}`, {
    method,
    headers: { Authorization: `Bearer ${read("api-token")}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!response.ok) throw new Error(await response.text());
  return (await response.json()) as T;
}
