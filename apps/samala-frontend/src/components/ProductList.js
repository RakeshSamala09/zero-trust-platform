import React from "react";

function ProductList({ products }) {
  if (!products.length) {
    return <p>No products available.</p>;
  }
  return (
    <div className="product-grid">
      {products.map((p) => (
        <div className="product-card" key={p.id}>
          <h3>{p.name}</h3>
          <p>{p.description}</p>
          <p className="price">₹{p.price}</p>
          <p className="stock">{p.stock > 0 ? "In stock" : "Out of stock"}</p>
        </div>
      ))}
    </div>
  );
}

export default ProductList;

