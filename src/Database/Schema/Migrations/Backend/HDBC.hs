module Database.Schema.Migrations.Backend.HDBC
    ( hdbcBackend
    )
where

import Database.HDBC
  ( quickQuery'
  , fromSql
  , toSql
  , IConnection(getTables, run, runRaw)
  , commit
  , rollback
  , disconnect
  )

import Database.Schema.Migrations.Backend
    ( Backend(..)
    , rootMigrationName
    )
import Database.Schema.Migrations.Migration
    ( Migration(..)
    , newMigration
    )

import Control.Applicative ( (<$>) )

migrationTableName :: String
migrationTableName = "installed_migrations"

createSql :: String
createSql = "CREATE TABLE " ++ migrationTableName ++ " (migration_id TEXT)"

revertSql :: String
revertSql = "DROP TABLE " ++ migrationTableName

-- |General Backend instance for all IO-driven HDBC connection
-- implementations.  You can provide a connection-specific instance if
-- need be; this implementation is provided with the hope that you
-- won't /have/ to do that.
hdbcBackend :: (IConnection conn) => conn -> Backend
hdbcBackend conn =
    Backend { isBootstrapped = elem migrationTableName <$> getTables conn
            , getBootstrapMigration =
                  do
                    m <- newMigration rootMigrationName
                    return $ m { mApply = createSql
                               , mRevert = Just revertSql
                               , mDesc = Just "Migration table installation"
                               }

            , applyMigration = \m -> do
                runRaw conn (mApply m)
                run conn ("INSERT INTO " ++ migrationTableName ++
                          " (migration_id) VALUES (?)") [toSql $ mId m]
                return ()

            , revertMigration = \m -> do
                  case mRevert m of
                    Nothing -> return ()
                    Just query -> runRaw conn query
                  -- Remove migration from installed_migrations in either case.
                  run conn ("DELETE FROM " ++ migrationTableName ++
                            " WHERE migration_id = ?") [toSql $ mId m]
                  return ()

            , getMigrations = do
                results <- quickQuery' conn ("SELECT migration_id FROM " ++ migrationTableName) []
                return $ map (fromSql . head) results

            , commitBackend = commit conn

            , rollbackBackend = rollback conn

            , disconnectBackend = disconnect conn
            }
