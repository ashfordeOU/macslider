import { Action, ActionPanel, List, showHUD, showToast, Toast } from "@raycast/api";
import { useEffect, useState } from "react";
import { api } from "./monorail";

type MonorailAction = { name: string; title: string };

export default function Command() {
  const [actions, setActions] = useState<MonorailAction[]>();
  useEffect(() => {
    api<MonorailAction[]>("GET", "/actions").then(setActions).catch((error) =>
      showToast({ style: Toast.Style.Failure, title: "Monorail", message: String(error.message ?? error) }),
    );
  }, []);
  return (
    <List isLoading={!actions} searchBarPlaceholder="Focus left, overview, focus mode…">
      {actions?.map((action) => (
        <List.Item key={action.name} title={action.title} subtitle={action.name}
          actions={<ActionPanel><Action title="Run" onAction={async () => {
            await api("POST", "/action", { action: action.name });
            await showHUD(action.title);
          }} /></ActionPanel>} />
      ))}
    </List>
  );
}
