package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/google/uuid"

	"github.com/e2b-dev/infra/packages/shared/pkg/db"
	"github.com/e2b-dev/infra/packages/shared/pkg/models/accesstoken"
	"github.com/e2b-dev/infra/packages/shared/pkg/models/team"
)

// setupSystemRecords initializes the required database records for system operation
func setupSystemRecords(ctx context.Context, dbConn *db.DB, userEmail, orgID, authToken, apiKey string) {
	orgUUID := uuid.MustParse(orgID)
	
	// Initialize user record
	systemUser, err := dbConn.Client.User.Create().SetEmail(userEmail).SetID(uuid.New()).Save(ctx)
	if err != nil {
		panic(err)
	}

	// Clean up existing organization if present
	_, err = dbConn.Client.Team.Delete().Where(team.Email(userEmail)).Exec(ctx)
	if err != nil {
		fmt.Println("Note: Unable to remove existing organization:", err)
	}

	// Remove previous authentication tokens
	_, err = dbConn.Client.AccessToken.Delete().Where(accesstoken.UserID(systemUser.ID)).Exec(ctx)
	if err != nil {
		fmt.Println("Note: Unable to remove authentication token:", err)
	}

	// Create organization record
	organization, err := dbConn.Client.Team.Create().SetEmail(userEmail).SetName("E2B").SetID(orgUUID).SetTier("base_v1").Save(ctx)
	if err != nil {
		panic(err)
	}

	// Link user to organization
	_, err = dbConn.Client.UsersTeams.Create().SetUserID(systemUser.ID).SetTeamID(organization.ID).SetIsDefault(true).Save(ctx)
	if err != nil {
		panic(err)
	}
	
	// Generate authentication token
	_, err = dbConn.Client.AccessToken.Create().SetUser(systemUser).SetID(authToken).Save(ctx)
	if err != nil {
		panic(err)
	}

	// Create API access key
	_, err = dbConn.Client.TeamAPIKey.Create().SetTeam(organization).SetAPIKey(apiKey).Save(ctx)
	if err != nil {
		panic(err)
	}

	// Initialize environment template
	_, err = dbConn.Client.Env.Create().SetTeam(organization).SetID("rki5dems9wqfm4r03t7g").SetPublic(true).Save(ctx)
	if err != nil {
		panic(err)
	}
}

func main() {
	ctx := context.Background()

	// Establish database connection
	dbConn, err := db.NewClient()
	if err != nil {
		panic(err)
	}
	defer dbConn.Close()

	// Verify database state
	recordCount, err := dbConn.Client.Team.Query().Count(ctx)
	if err != nil {
		panic(err)
	}

	if recordCount > 1 {
		panic("Database already contains existing data")
	}

	// Locate user configuration directory
	userHomeDir, err := os.UserHomeDir()
	if err != nil {
		fmt.Println("Error accessing home directory:", err)
		return
	}

	// Attempt to load configuration
	configFilePath := filepath.Join(userHomeDir, ".e2b", "config.json")
	configData, err := os.ReadFile(configFilePath)
	if err != nil {
		fmt.Println("Note: Configuration file not found:", err)
		fmt.Println("Creating default AWS configuration...")
		
		// Default configuration values
		userEmail := "admin@example.com"
		orgID := "00000000-0000-0000-0000-000000000000"
		authToken := "e2b_access_token"
		apiKey := "e2b_team_api_key"
		
		// Initialize database with default values
		setupSystemRecords(ctx, dbConn, userEmail, orgID, authToken, apiKey)
		
		// Generate default configuration file
		defaultConfig := map[string]interface{}{
			"email":       userEmail,
			"teamId":      orgID,
			"accessToken": authToken,
			"teamApiKey":  apiKey,
			"cloud":       "aws",
			"region":      "us-east-1",
		}
		
		formattedConfig, err := json.MarshalIndent(defaultConfig, "", "  ")
		if err != nil {
			panic(err)
		}
		
		// Ensure configuration directory exists
		os.MkdirAll(filepath.Join(userHomeDir, ".e2b"), 0755)
		
		if err := os.WriteFile(configFilePath, formattedConfig, 0644); err != nil {
			panic(err)
		}
		
		fmt.Println("Default AWS configuration created at:", configFilePath)
		return
	}

	// Parse configuration data
	configMap := map[string]interface{}{}
	err = json.Unmarshal(configData, &configMap)
	if err != nil {
		panic(err)
	}

	// Ensure AWS configuration is present
	if _, exists := configMap["cloud"]; !exists {
		configMap["cloud"] = "aws"
		configMap["region"] = "us-east-1"
		
		// Update configuration file
		updatedConfig, err := json.MarshalIndent(configMap, "", "  ")
		if err != nil {
			panic(err)
		}
		
		if err := os.WriteFile(configFilePath, updatedConfig, 0644); err != nil {
			panic(err)
		}
		
		fmt.Println("Configuration updated with AWS settings")
	}

	// Extract configuration values
	userEmail := configMap["email"].(string)
	orgID := configMap["teamId"].(string)
	authToken := configMap["accessToken"].(string)
	apiKey := configMap["teamApiKey"].(string)

	// Initialize database with configuration values
	setupSystemRecords(ctx, dbConn, userEmail, orgID, authToken, apiKey)
	
	fmt.Printf("Database initialization complete.\n")
}
