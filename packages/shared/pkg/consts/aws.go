package consts

import (
	"os"
)

var (
	AWSAccountID          = os.Getenv("AWS_ACCOUNT_ID")
	AWSRegion             = os.Getenv("AWS_REGION")
	ECRRepository         = os.Getenv("AWS_ECR_REPOSITORY")
	AWS_ACCESS_KEY_ID     = os.Getenv("AWS_ACCESS_KEY_ID")
	AWS_SECRET_ACCESS_KEY = os.Getenv("AWS_SECRET_ACCESS_KEY")
)
