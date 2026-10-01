const appUsername = process.env.MONGO_APP_USERNAME;
const appPassword = process.env.MONGO_APP_PASSWORD;

if (!appUsername || !appPassword) {
  throw new Error("MONGO_APP_USERNAME and MONGO_APP_PASSWORD are required");
}

db = db.getSiblingDB("employees");

db.createUser({
  user: appUsername,
  pwd: appPassword,
  roles: [
    {
      role: "readWrite",
      db: "employees"
    }
  ]
});

print(`Application user '${appUsername}' created for database 'employees'.`);
