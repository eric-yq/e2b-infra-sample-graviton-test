#!/bin/bash
# init-db.sh - One-click database initialization (including table creation and data population)

set -e

# Change to the directory of the script
cd "$(dirname "$0")"

MIGRATION_SQL="./.migration.sql"
SEED_SQL="./.seed-db.sql"
CONFIG_PATH="./config.json"
CONFIG_FILE="/opt/config.properties"


# First, execute init-config.sh to generate configuration
echo "Generating configuration file..."
if [ -f "./init-config.sh" ]; then
    bash ./init-config.sh
    if [ $? -ne 0 ]; then
        echo "Error: Failed to generate configuration"
        exit 1
    fi
    echo "Configuration generated successfully!"
else
    echo "Error: init-config.sh not found"
    exit 1
fi
# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file $CONFIG_FILE does not exist"
    exit 1
fi

# Read database connection information from config file
DB_HOST=$(grep "^postgres_host=" "$CONFIG_FILE" | cut -d'=' -f2)
DB_PORT=$(grep "^DB_PORT=" "$CONFIG_FILE" | cut -d'=' -f2)
DB_NAME=$(grep "^DB_NAME=" "$CONFIG_FILE" | cut -d'=' -f2)
DB_USER=$(grep "^postgres_user=" "$CONFIG_FILE" | cut -d'=' -f2)
DB_PASSWORD=$(grep "^postgres_password=" "$CONFIG_FILE" | cut -d'=' -f2)

# Check if all database variables are set
for VAR_NAME in DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD; do
    VAR_VALUE=${!VAR_NAME}
    if [ -z "$VAR_VALUE" ]; then
        echo "Error: $VAR_NAME variable is missing in the configuration file"
        exit 1
    fi
    echo "Using $VAR_NAME = $VAR_VALUE"
done

# Check if migration.sql exists
if [ ! -f "$MIGRATION_SQL" ]; then
    echo "Error: migration.sql file not found: $MIGRATION_SQL"
    exit 1
fi

# Check if seed-db.sql exists
if [ ! -f "$SEED_SQL" ]; then
    echo "Error: seed-db.sql file not found: $SEED_SQL"
    exit 1
fi

# Read configuration file
echo "Reading information from configuration file..."
if command -v jq &> /dev/null; then
    email=$(jq -r '.email' "$CONFIG_PATH")
    teamId=$(jq -r '.teamId' "$CONFIG_PATH")
    accessToken=$(jq -r '.accessToken' "$CONFIG_PATH")
    teamApiKey=$(jq -r '.teamApiKey' "$CONFIG_PATH")
    cloud=$(jq -r '.cloud // "aws"' "$CONFIG_PATH")
    region=$(jq -r '.region // "us-east-1"' "$CONFIG_PATH")
else
    echo "Warning: jq tool not found"
    exit 1
fi

# Check database connection
if ! PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c '\q' &>/dev/null; then
    echo "Error: Cannot connect to PostgreSQL database server. Please check connection parameters."
    exit 1
fi

# Step 1: Execute migration.sql to create table structure
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$MIGRATION_SQL"
if [ $? -ne 0 ]; then
    echo "Error: Table structure creation failed"
    exit 1
fi
echo "Table structure created successfully!"

# Step 2: Check if database contains data
TEAM_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM teams;" 2>/dev/null || echo "0")
TEAM_COUNT=$(echo $TEAM_COUNT | tr -d ' ')

if [ "$TEAM_COUNT" = "" ] || [ "$TEAM_COUNT" = "0" ]; then
    # Step 3: Execute seed-db.sql to populate initial data
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -v email="$email" \
        -v teamID="$teamId" \
        -v accessToken="$accessToken" \
        -v teamAPIKey="$teamApiKey" \
        -f "$SEED_SQL"
    
    if [ $? -ne 0 ]; then
        echo "Error: Data population failed"
        exit 1
    fi
    echo "Database initialization completed!"
elif [ "$TEAM_COUNT" -gt 1 ]; then
    echo "Database already contains data (team count: $TEAM_COUNT). Skipping data population step."
else
    echo "Database already has one team. To reinitialize, please clear the database first."
fi

echo "==================="
echo "User: $email"
echo "Team ID: $teamId"
echo "Access Token: $accessToken"
echo "Team API Key: $teamApiKey"
