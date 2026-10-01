import express from "express";
import cors from "cors";
import records from "./routes/record.js";
import { client } from "./db/connection.js";

const PORT = process.env.PORT || 5050;

const app = express();

app.use(cors());
app.use(express.json());

app.get("/health", async (req, res) => {
  try {
    await client.db("admin").command({ ping: 1 });

    res.status(200).json({
      status: "healthy",
      database: "connected",
    });
  } catch (error) {
    console.error("Health check failed:", error);

    res.status(503).json({
      status: "unhealthy",
      database: "disconnected",
    });
  }
});

app.use("/record", records);

app.listen(PORT, () => {
  console.log(`Server listening on port ${PORT}`);
});
