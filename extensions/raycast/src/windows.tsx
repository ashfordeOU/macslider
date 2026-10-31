import { Action, ActionPanel, List, closeMainWindow } from "@raycast/api";
import { useEffect, useState } from "react";
import { api } from "./monorail";

type Window = { id: number; app: string; title: string; workspace?: number; slide?: number };

export default function Command() {
  const [windows, setWindows] = useState<Window[]>();
  useEffect(() => { api<Window[]>("GET", "/windows").then(setWindows); }, []);
  return (
    <List isLoading={!windows}>
      {windows?.map((window) => (
        <List.Item key={window.id} title={window.title || window.app} subtitle={window.app}
          accessories={window.workspace ? [{ text: `Workspace ${window.workspace} · slide ${window.slide}` }] : [{ text: "Floating" }]}
          actions={<ActionPanel><Action title="Go to Window" onAction={async () => {
            await closeMainWindow();
            await api("POST", "/focus", { id: window.id });
          }} /></ActionPanel>} />
      ))}
    </List>
  );
}
