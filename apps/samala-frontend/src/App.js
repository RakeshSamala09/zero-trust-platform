import React, { useEffect, useState } from "react";
import ProductList from "./components/ProductList";

// In-cluster this resolves via the samala-backend Service (ClusterIP + DNS).
// Overridden at build time by REACT_APP_API_BASE_URL if needed (e.g. via Ingress path).
const API_BASE = process.env.REACT_APP_API_BASE_URL || "/api";

function App() {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetch(`${API_BASE}/products`)
      .then((res) => {
        if (!res.ok) throw new Error("Failed to load products");
        return res.json();
      })
      .then((data) => {
        setProducts(data);
        setLoading(false);
      })
      .catch((err) => {
        setError(err.message);
        setLoading(false);
      });
  }, []);

  return (
    <div className="app">
      <header className="header">
        <h1>Samala</h1>
        <p>Simple, fast ecommerce.</p>
      </header>
      <main>
        {loading && <p>Loading products...</p>}
        {error && <p className="error">Error: {error}</p>}
        {!loading && !error && <ProductList products={products} />}
      </main>
    </div>
  );
}

export default App;

