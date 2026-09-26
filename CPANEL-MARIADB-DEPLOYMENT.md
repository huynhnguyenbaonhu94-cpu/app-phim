# Cinemora — cPanel Node.js + MariaDB

## Production configuration

The backend already exposes the required tRPC procedures:

- `auth.register`
- `auth.login`
- `auth.logout`
- `auth.me`
- `account.favorites`
- `account.addFavorite`
- `account.removeFavorite`
- `account.history`
- `account.recordHistory`

The iOS app calls `https://cungcapicloud.id.vn/api/trpc` over HTTPS. The app never contains database credentials.

## cPanel Node.js App environment variables

Set these in **cPanel → Setup Node.js App → Environment Variables**. Do not commit them to GitHub or put them in the iOS app.

```env
NODE_ENV=production
DATABASE_URL=mysql://DB_USER:NEW_DB_PASSWORD@localhost:3306/DB_NAME
JWT_SECRET=GENERATE_A_LONG_RANDOM_SECRET_AT_LEAST_32_CHARACTERS
```

Use the database username and database name configured in cPanel. Replace `NEW_DB_PASSWORD` with the newly rotated password; never reuse the password that was previously exposed.

## Database migration

Run the Drizzle migrations once against the production database, from the Node.js app environment or an approved deployment shell:

```sh
pnpm install --frozen-lockfile
pnpm run db:push
pnpm run build
```

The migrations create/extend:

- `users`
- `movie_favorites`
- `movie_watch_history`

## Node.js app settings

- Node.js: `22.18.0`
- Application URL: `https://cungcapicloud.id.vn/`
- API base used by the iOS app: `https://cungcapicloud.id.vn/api/trpc`
- Start command: `node dist/index.js`
- Set `NODE_ENV=production`

## Security checklist

- Rotate the database password before deployment.
- Generate a new random `JWT_SECRET` and keep it private.
- Use HTTPS only.
- Do not expose port 3306 publicly.
- Do not put `DATABASE_URL` in the ZIP or mobile source.
- After deployment, test registration, login, favorite toggle, logout, and history recording with a test account.
