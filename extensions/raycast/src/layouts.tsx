import { Action, ActionPanel, List, showHUD } from "@raycast/api";
import { useEffect, useState } from "react";
import { api } from "./monorail";

type Entry = { kind: string; name: string; path: string };

export default function Command() {
  const [entries, setEntries] = useState<Entry[]>();
  useEffect(() => {
    (async () => {
      const [layouts, pairs, templates, snapshots] = await Promise.all([
        api<string[]>("GET", "/layouts"), api<string[]>("GET", "/pairs"),
        api<string[]>("GET", "/templates"), api<string[]>("GET", "/snapshots"),
      ]);
      setEntries([
        ...layouts.map((name) => ({ kind: "Layout", name, path: "/layout" })),
        ...pairs.map((name) => ({ kind: "App pair", name, path: "/pair-name" })),
        ...templates.map((name) => ({ kind: "Template", name, path: "/template" })),
        ...snapshots.map((name) => ({ kind: "Snapshot", name, path: "/snapshot" })),
      ]);
    })();
  }, []);
  return (
    <List isLoading={!entries}>
      {entries?.map((entry) => (
        <List.Item key={entry.kind + entry.name} title={entry.name} accessories={[{ text: entry.kind }]}
          actions={<ActionPanel><Action title="Open" onAction={async () => {
            await api("POST", entry.path, { name: entry.name });
            await showHUD(`${entry.kind}: ${entry.name}`);
          }} /></ActionPanel>} />
      ))}
    </List>
  );
}
