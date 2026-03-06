import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";

// Disable right-click context menu (Inspect Element) in production
document.addEventListener('contextmenu', (e) => e.preventDefault());

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
