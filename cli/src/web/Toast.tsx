import React, { useState, useEffect, useCallback } from "react";
import { onToast } from "./hooks.ts";

interface ToastItem {
  id: number;
  message: string;
  leaving: boolean;
}

let nextId = 0;

export function ToastContainer() {
  const [toasts, setToasts] = useState<ToastItem[]>([]);

  const addToast = useCallback((message: string) => {
    const id = nextId++;
    setToasts((prev) => [...prev, { id, message, leaving: false }]);

    setTimeout(() => {
      setToasts((prev) =>
        prev.map((t) => (t.id === id ? { ...t, leaving: true } : t))
      );
      setTimeout(() => {
        setToasts((prev) => prev.filter((t) => t.id !== id));
      }, 150);
    }, 4000);
  }, []);

  useEffect(() => {
    onToast(addToast);
  }, [addToast]);

  if (toasts.length === 0) return null;

  return (
    <div className="toast-container">
      {toasts.map((t) => (
        <div key={t.id} className={`toast ${t.leaving ? "toast-out" : ""}`}>
          {t.message}
        </div>
      ))}
    </div>
  );
}
