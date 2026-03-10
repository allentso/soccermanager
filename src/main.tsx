import React from "react";
import ReactDOM from "react-dom/client";
import "flag-icons/css/flag-icons.min.css";
import { ThemeProvider } from "./context/ThemeContext";
import "./i18n";
import App from "./App";

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <ThemeProvider>
      <App />
    </ThemeProvider>
  </React.StrictMode>,
);
