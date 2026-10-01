import { MongoClient } from "mongodb";

const URI = process.env.MONGO_URI;

if (!URI) {
  throw new Error("MONGO_URI environment variable is required");
}

const client = new MongoClient(URI);

try {
  await client.connect();
  await client.db("admin").command({ ping: 1 });

  console.log("MongoDB connection established successfully.");
} catch (err) {
  console.error("MongoDB connection failed:", err);
  process.exit(1);
}

const db = client.db("employees");

export { client };

export default db;
